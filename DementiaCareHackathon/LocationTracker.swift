//
//  LocationTracker.swift
//  DementiaCareHackathon
//
//  Runs on the patient's phone. Tracks location, checks it against the home zone,
//  warns the patient when they leave it, and shares the location through Firestore.
//

import Foundation
import CoreLocation
import AVFoundation
import UIKit

final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var isOutside = false
    @Published var distanceFromHome: CLLocationDistance?

    private let manager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
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

        if nowOutside && (!wasOutside || firstCheck) {
            warnPatient()
        }

        let stateChanged = nowOutside != wasOutside || firstCheck
        let intervalPassed = lastUploadAt.map { Date().timeIntervalSince($0) > uploadInterval } ?? true
        if forceUpload || stateChanged || intervalPassed {
            lastUploadAt = Date()
            PatientCloud.updateLocation(
                pairingCode: profile.pairingCode,
                location: location,
                isOutside: nowOutside,
                distanceMeters: distance
            )
        }
    }

    private func warnPatient() {
        let message = "You are far from home. Please turn around and go back home."
        LocalNotifier.send(id: "zone-exit", title: "Please turn around", body: message)

        // Speak the warning out loud when the app is open.
        if UIApplication.shared.applicationState == .active {
            let utterance = AVSpeechUtterance(string: message)
            utterance.rate = 0.45
            speech.speak(utterance)
        }
    }
}
