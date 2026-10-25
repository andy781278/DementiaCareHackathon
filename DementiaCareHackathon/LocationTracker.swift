//
//  LocationTracker.swift
//  DementiaCareHackathon
//
//  Runs on the patient's phone. Tracks location, checks it against the home zone,
//  warns the patient when they leave it, and shares the location through Firestore.
//

import Foundation
import CoreLocation
import UIKit

final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var isOutside = false
    @Published var distanceFromHome: CLLocationDistance?
    /// When the patient left the safe zone, or nil while inside.
    @Published var outsideSince: Date?
    /// The highest wander alert tier already given during the current time outside (0 = none).
    @Published var alertedTier = 0
    /// Test time outside set from the caretaker phone, or nil when the real time is used.
    @Published var testMinutesOutside: Double?
    /// True when the caretaker marked the current time outside as safe.
    @Published var markedSafe = false

    private let tierPoller = Poller()
    private var isFetchingTest = false

    /// Sound file of a recorded wandering message, if one was recorded.
    var wanderingSoundFile: String?

    static let wanderingMessage = "You are far from home. Please turn around and go back home."

    private let manager = CLLocationManager()
    private var profile: PatientProfile?
    private var hasEvaluated = false
    private var lastUploadAt: Date?

    /// Seconds between location uploads when nothing important changed.
    private let uploadInterval: TimeInterval = 15

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func start(profile: PatientProfile) {
        self.profile = profile
        // Make the spoken warning ahead of time so the alert does not wait for it.
        SpeechFileMaker.shared.make(
            text: LocationTracker.wanderingMessage,
            url: SoundFiles.url(SoundFiles.ttsFileName(for: LocationTracker.wanderingMessage))
        ) { _ in }
        // Every few seconds: check for a test time set by the caretaker, and give later alerts as time passes.
        tierPoller.start(every: 3) { [weak self] in
            self?.fetchTestMinutes()
            self?.checkTier()
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            beginUpdates()
        case .authorizedAlways:
            beginUpdates()
        default:
            break
        }
    }

    /// Call when the setup changes (home address or alert distance).
    func update(profile: PatientProfile) {
        self.profile = profile
        if let location = location {
            evaluate(location, forceUpload: true)
        }
    }

    /// Text explaining a location permission problem, or nil when location works fully.
    var permissionMessage: String? {
        switch authorization {
        case .notDetermined:
            return "Waiting for location permission."
        case .denied, .restricted:
            return "Location access is off. Turn it on in Settings so the app can check where you are."
        case .authorizedWhenInUse:
            return "Location is only checked while the app is open. Choose \"Always\" in Settings to keep checking in the background."
        case .authorizedAlways:
            return nil
        @unknown default:
            return nil
        }
    }

    private func beginUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        guard profile != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            beginUpdates()
        case .authorizedAlways:
            beginUpdates()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        evaluate(latest, forceUpload: false)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }

    // MARK: - Zone check

    private func evaluate(_ location: CLLocation, forceUpload: Bool) {
        guard let profile = profile,
              let latitude = profile.homeLatitude,
              let longitude = profile.homeLongitude else { return }

        let home = CLLocation(latitude: latitude, longitude: longitude)
        let distance = location.distance(from: home)
        let radius = profile.safeRadiusMiles * Distance.metersPerMile
        distanceFromHome = distance

        // Once outside, the patient must come back to 90% of the radius to count as inside again.
        // This stops repeated alerts when standing right at the edge.
        let wasOutside = isOutside
        let nowOutside = wasOutside ? distance > radius * 0.9 : distance > radius
        let firstCheck = !hasEvaluated
        hasEvaluated = true
        isOutside = nowOutside
        if nowOutside && outsideSince == nil {
            outsideSince = Date()
        } else if !nowOutside {
            outsideSince = nil
        }

        if nowOutside && (!wasOutside || firstCheck) {
            alertedTier = 1
            warnPatient(tier: 1)
        } else if !nowOutside && (wasOutside || firstCheck) {
            alertedTier = 0
            // Clear a test time and a "marked safe" once the patient is back inside.
            if testMinutesOutside != nil {
                testMinutesOutside = nil
                PatientCloud.setTestMinutesOutside(pairingCode: profile.pairingCode, minutes: nil)
            }
            if markedSafe {
                markedSafe = false
                PatientCloud.setMarkedSafe(pairingCode: profile.pairingCode, safe: false)
            }
        }

        let stateChanged = nowOutside != wasOutside || firstCheck
        let intervalPassed = lastUploadAt.map { Date().timeIntervalSince($0) > uploadInterval } ?? true
        if forceUpload || stateChanged || intervalPassed {
            lastUploadAt = Date()
            PatientCloud.updateLocation(
                pairingCode: profile.pairingCode,
                location: location,
                isOutside: nowOutside,
                outsideSince: outsideSince,
                distanceMeters: distance
            )
        }
    }

    private func fetchTestMinutes() {
        guard !isFetchingTest, let code = profile?.pairingCode, code.count == 6 else { return }
        isFetchingTest = true
        FirestoreREST.get(PatientCloud.path(pairingCode: code)) { [weak self] result in
            guard let self = self else { return }
            self.isFetchingTest = false
            guard case .success(let document) = result else { return }
            let value = (document?.fields["testMinutesOutside"] as? Double).flatMap { $0 >= 0 ? $0 : nil }
            let safe = document?.fields["markedSafe"] as? Bool ?? false
            if safe != self.markedSafe {
                self.markedSafe = safe
            }
            if value != self.testMinutesOutside {
                self.testMinutesOutside = value
                self.checkTier()
            }
        }
    }

    /// Gives the 10-minute and 30-minute alerts while the patient stays outside.
    private func checkTier() {
        // No more alerts once the caretaker marked this time outside as safe.
        guard isOutside, !markedSafe else { return }
        let realMinutes = outsideSince.map { max(0, Date().timeIntervalSince($0) / 60) } ?? 0
        let minutes = testMinutesOutside ?? realMinutes
        let tier = WanderTier.tier(forMinutesOutside: minutes)
        guard tier > alertedTier else { return }
        alertedTier = tier
        warnPatient(tier: tier)
    }

    /// Plays the recorded wandering message if there is one, otherwise the warning for this tier read aloud.
    private func warnPatient(tier: Int) {
        let hasCaretaker = profile?.hasCaretaker ?? false
        let title: String
        let message: String
        let vibration: AlertVibration
        switch tier {
        case 1:
            title = "Please turn around"
            message = LocationTracker.wanderingMessage
            vibration = .none
        case 2:
            title = "You have been away for 10 minutes"
            message = "You have been away from home for 10 minutes. Please turn around and go back home."
            vibration = .short
        default:
            title = "You have been away for 30 minutes"
            message = hasCaretaker
                ? "You have been away from home for 30 minutes. Please stay where you are. Your caretaker has been told where you are."
                : "You have been away from home for 30 minutes. Please go back home, or ask someone nearby for help."
            vibration = .long
        }

        LocalNotifier.send(
            id: "zone-exit-\(tier)",
            title: title,
            body: message,
            soundFile: wanderingSoundFile,
            spokenText: message
        )
        vibration.play()
    }
}
