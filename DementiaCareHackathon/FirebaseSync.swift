//
//  FirebaseSync.swift
//  DementiaCareHackathon
//
//  Shares patient data through Firestore (using FirestoreREST).
//  Each patient is stored at patients/{pairingCode}. Schedule events are at patients/{pairingCode}/events.
//

import Foundation
import CoreLocation
import AudioToolbox

// MARK: - Patient side

enum PatientCloud {
    static func path(pairingCode: String) -> String {
        "patients/\(pairingCode)"
    }

    /// Writes the patient's setup to Firestore. Only these fields change; location fields are kept.
    static func upload(_ profile: PatientProfile) {
        guard profile.pairingCode.count == 6 else { return }

        var fields: [String: [String: Any]] = [
            "name": FirestoreREST.string(profile.name),
            "homeAddress": FirestoreREST.string(profile.displayHomeAddress),
            "safeRadiusMiles": FirestoreREST.double(profile.safeRadiusMiles),
            "hasCaretaker": FirestoreREST.bool(profile.hasCaretaker),
            "caretakerEmail": FirestoreREST.string(profile.caretakerEmail.trimmed.lowercased()),
            "dementiaLevel": FirestoreREST.string(profile.dementiaLevel.rawValue),
            "updatedAt": FirestoreREST.timestamp(Date())
        ]
        if let latitude = profile.homeLatitude, let longitude = profile.homeLongitude {
            fields["homeLocation"] = FirestoreREST.geoPoint(latitude: latitude, longitude: longitude)
        }
        FirestoreREST.patch(path(pairingCode: profile.pairingCode), fields: fields)
    }

    static func updateLocation(
        pairingCode: String,
        location: CLLocation,
        isOutside: Bool,
        outsideSince: Date?,
        distanceMeters: Double
    ) {
        guard pairingCode.count == 6 else { return }
        let fields: [String: [String: Any]] = [
            "outsideSince": outsideSince.map { FirestoreREST.timestamp($0) } ?? FirestoreREST.null(),
            "lastLocation": FirestoreREST.geoPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            "lastLocationAt": FirestoreREST.timestamp(Date()),
            "isOutsideZone": FirestoreREST.bool(isOutside),
            "distanceFromHomeMeters": FirestoreREST.double(distanceMeters)
        ]
        FirestoreREST.patch(path(pairingCode: pairingCode), fields: fields)
    }

    static func updateBattery(pairingCode: String, percent: Int, isCharging: Bool) {
        guard pairingCode.count == 6 else { return }
        FirestoreREST.patch(path(pairingCode: pairingCode), fields: [
            "batteryPercent": FirestoreREST.int(percent),
            "batteryCharging": FirestoreREST.bool(isCharging),
            "batteryAt": FirestoreREST.timestamp(Date())
        ])
    }

    /// Marks the current time outside the safe zone as safe (no more wander alerts until the patient returns).
    static func setMarkedSafe(pairingCode: String, safe: Bool, completion: ((Error?) -> Void)? = nil) {
        guard pairingCode.count == 6 else {
            completion?(nil)
            return
        }
        FirestoreREST.patch(
            path(pairingCode: pairingCode),
            fields: ["markedSafe": FirestoreREST.bool(safe)],
            completion: completion
        )
    }

    /// Sets a test time outside the safe zone, used by both phones instead of the real time. nil clears it.
    static func setTestMinutesOutside(pairingCode: String, minutes: Double?) {
        guard pairingCode.count == 6 else { return }
        FirestoreREST.patch(path(pairingCode: pairingCode), fields: [
            "testMinutesOutside": FirestoreREST.double(minutes ?? -1)
        ])
    }

    /// Sets a test battery level that the patient phone uses instead of its real battery. nil clears it.
    static func setTestBattery(pairingCode: String, percent: Int?) {
        guard pairingCode.count == 6 else { return }
        FirestoreREST.patch(path(pairingCode: pairingCode), fields: [
            "testBatteryPercent": FirestoreREST.int(percent ?? -1)
        ])
    }

    static func delete(pairingCode: String) {
        guard pairingCode.count == 6 else { return }
        FirestoreREST.delete(path(pairingCode: pairingCode))
    }
}

// MARK: - Caretaker side

struct RemotePatient: Equatable {
    var name: String
    var homeAddress: String
    var safeRadiusMiles: Double
    var caretakerEmail: String
    var dementiaLevel: DementiaLevel?
    var updatedAt: Date?

    var homeLatitude: Double?
    var homeLongitude: Double?
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastLocationAt: Date?
    var isOutsideZone: Bool
    /// When the patient left the safe zone, or nil while inside.
    var outsideSince: Date?
    /// True when the caretaker marked the current time outside as safe.
    var markedSafe: Bool
    var distanceFromHomeMeters: Double?

    var batteryPercent: Int?
    var batteryCharging: Bool
    var batteryAt: Date?
    /// Test battery level set from the caretaker phone, or nil when the real battery is used.
    var testBatteryPercent: Int?
    /// Test time outside set from the caretaker phone, or nil when the real time is used.
    var testMinutesOutside: Double?

    init(data: [String: Any]) {
        name = data["name"] as? String ?? ""
        homeAddress = data["homeAddress"] as? String ?? ""
        safeRadiusMiles = data["safeRadiusMiles"] as? Double ?? 0
        caretakerEmail = data["caretakerEmail"] as? String ?? ""
        dementiaLevel = (data["dementiaLevel"] as? String).flatMap { DementiaLevel(rawValue: $0) }
        updatedAt = data["updatedAt"] as? Date

        if let home = data["homeLocation"] as? GeoPoint {
            homeLatitude = home.latitude
            homeLongitude = home.longitude
        }
        if let last = data["lastLocation"] as? GeoPoint {
            lastLatitude = last.latitude
            lastLongitude = last.longitude
        }
        lastLocationAt = data["lastLocationAt"] as? Date
        isOutsideZone = data["isOutsideZone"] as? Bool ?? false
        outsideSince = data["outsideSince"] as? Date
        markedSafe = data["markedSafe"] as? Bool ?? false
        distanceFromHomeMeters = data["distanceFromHomeMeters"] as? Double

        batteryPercent = data["batteryPercent"] as? Int
        batteryCharging = data["batteryCharging"] as? Bool ?? false
        batteryAt = data["batteryAt"] as? Date
        testBatteryPercent = (data["testBatteryPercent"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
        testMinutesOutside = (data["testMinutesOutside"] as? Double).flatMap { $0 >= 0 ? $0 : nil }
    }

    var displayName: String {
        name.isEmpty ? "The patient" : name
    }

    var homeCoordinate: CLLocationCoordinate2D? {
        guard let latitude = homeLatitude, let longitude = homeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var lastCoordinate: CLLocationCoordinate2D? {
        guard let latitude = lastLatitude, let longitude = lastLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Checks one patient's record every few seconds, reports whether the caretaker is connected,
/// and alerts the caretaker when the patient leaves or returns to the safe zone.
final class CaretakerConnection: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case notFound
        case emailMismatch
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var patient: RemotePatient?

    static let pollSeconds: TimeInterval = 3

    private let poller = Poller()
    private var isFetching = false
    private var currentCode = ""
    private var currentEmail = ""
    private var notifyOnAlert = true
    private var vibrateOnAlert = true
    /// Minutes the patient has been outside the safe zone, or nil while inside.
    @Published var minutesOutside: Double?
    /// A test value set with the caretaker's slider, used instead of the real time outside.
    @Published var testMinutesOutside: Double?
    /// The highest wander alert tier already sent during the current time outside (0 = none).
    @Published var alertedTier = 0

    private var batteryThreshold = Battery.defaultThreshold
    private var hasAlertedBattery = false

    /// Starts checking the patient in this caretaker's setup.
    /// Does not restart if the code and email are unchanged; alert preferences are always updated.
    func connect(profile: CaretakerProfile) {
        notifyOnAlert = profile.notifyOnAlert
        vibrateOnAlert = profile.vibrateOnAlert
        batteryThreshold = profile.batteryThreshold

        let code = profile.patientPairingCode
        let email = profile.email.trimmed.lowercased()
        if code == currentCode && email == currentEmail && !currentCode.isEmpty {
            return
        }

        disconnect()
        guard code.count == 6 else {
            state = .notFound
            return
        }

        currentCode = code
        currentEmail = email
        state = .connecting

        // Check the patient's record every few seconds.
        poller.start(every: CaretakerConnection.pollSeconds) { [weak self] in
            self?.fetch()
        }
    }

    private func fetch() {
        guard !isFetching, currentCode.count == 6 else { return }
        isFetching = true
        let code = currentCode

        FirestoreREST.get(PatientCloud.path(pairingCode: code)) { [weak self] result in
            guard let self = self else { return }
            self.isFetching = false
            // Ignore a response for a code that is no longer in use.
            guard code == self.currentCode else { return }

            switch result {
            case .failure(let error):
                // Keep showing the last known data if a single check fails.
                if self.patient == nil {
                    self.state = .failed(error.localizedDescription)
                }

            case .success(nil):
                self.patient = nil
                self.state = .notFound

            case .success(let document?):
                let remote = RemotePatient(data: document.fields)
                if remote.caretakerEmail != self.currentEmail {
                    self.patient = nil
                    self.state = .emailMismatch
                    return
                }
                if self.patient != remote {
                    self.patient = remote
                }
                if self.state != .connected {
                    self.state = .connected
                }
                self.handleZoneChange(remote)
                self.handleBattery(remote)
            }
        }
    }

    /// Alerts once when the patient's battery is at or below the caretaker's alert level and not charging.
    private func handleBattery(_ remote: RemotePatient) {
        guard let percent = remote.batteryPercent else { return }
        let isLow = percent <= batteryThreshold && !remote.batteryCharging
        if isLow && !hasAlertedBattery {
            hasAlertedBattery = true
            alert(
                title: "\(remote.displayName)'s battery is low",
                body: "\(remote.displayName)'s phone battery is at \(percent)%. Location tracking stops if the phone turns off."
            )
        } else if !isLow {
            hasAlertedBattery = false
        }
    }

    /// Sets or clears (nil) the test battery level on the patient phone.
    func setTestBattery(_ percent: Int?) {
        PatientCloud.setTestBattery(pairingCode: currentCode, percent: percent)
    }

    func disconnect() {
        poller.stop()
        isFetching = false
        currentCode = ""
        currentEmail = ""
        patient = nil
        alertedTier = 0
        minutesOutside = nil
        testMinutesOutside = nil
        hasAlertedBattery = false
        state = .idle
    }

    /// Marks the current time outside the safe zone as safe, or undoes it.
    /// While marked safe, no more wander alerts are sent on either phone until the patient returns.
    func setMarkedSafe(_ safe: Bool) {
        patient?.markedSafe = safe
        PatientCloud.setMarkedSafe(pairingCode: currentCode, safe: safe)
    }

    /// Sets (or clears with nil) a test time outside, to try the alert tiers without waiting.
    func setTestMinutesOutside(_ minutes: Double?) {
        testMinutesOutside = minutes
        PatientCloud.setTestMinutesOutside(pairingCode: currentCode, minutes: minutes)
        if let patient = patient {
            handleZoneChange(patient)
        }
    }

    /// Three alert tiers while the patient is outside the safe zone:
    /// 1. when they leave: a notification
    /// 2. after 10 minutes: a notification and vibration
    /// 3. after 30 minutes: a notification and 10 seconds of vibration
    private func handleZoneChange(_ remote: RemotePatient) {
        // Only alert once a location has been shared.
        guard remote.lastCoordinate != nil else { return }

        guard remote.isOutsideZone else {
            if alertedTier > 0 {
                alert(
                    title: "\(remote.displayName) is back",
                    body: "\(remote.displayName) is inside the safe zone again.",
                    vibration: .none
                )
            }
            alertedTier = 0
            if minutesOutside != nil { minutesOutside = nil }
            if testMinutesOutside != nil { testMinutesOutside = nil }
            return
        }

        let realMinutes = remote.outsideSince.map { max(0, Date().timeIntervalSince($0) / 60) } ?? 0
        let minutes = testMinutesOutside ?? remote.testMinutesOutside ?? realMinutes
        minutesOutside = minutes

        // The caretaker marked this time outside as safe: no more alerts until the patient returns.
        if remote.markedSafe { return }

        let tier = WanderTier.tier(forMinutesOutside: minutes)
        guard tier > alertedTier else { return }
        alertedTier = tier

        var distanceText = ""
        if let meters = remote.distanceFromHomeMeters {
            distanceText = " They are \(Distance.milesText(meters: meters)) from home."
        }
        let name = remote.displayName

        switch tier {
        case 1:
            alert(
                title: "\(name) left the safe zone",
                body: "\(name) has left the safe zone.\(distanceText)",
                vibration: .none,
                offerMarkSafe: true
            )
        case 2:
            alert(
                title: "\(name) has been outside for 10 minutes",
                body: "\(name) has been outside the safe zone for 10 minutes.\(distanceText)",
                vibration: .short,
                offerMarkSafe: true
            )
        default:
            alert(
                title: "\(name) has been outside for 30 minutes",
                body: "\(name) has been outside the safe zone for 30 minutes.\(distanceText) Open the map to see where they are.",
                vibration: .long,
                offerMarkSafe: true
            )
        }
    }

    /// offerMarkSafe adds a "Mark as safe" button to the notification.
    private func alert(title: String, body: String, vibration: AlertVibration = .short, offerMarkSafe: Bool = false) {
        if notifyOnAlert {
            LocalNotifier.send(
                id: "caretaker-alert",
                title: title,
                body: body,
                spokenText: "\(title). \(body)",
                category: offerMarkSafe ? WanderNotification.category : nil,
                extraInfo: offerMarkSafe ? [WanderNotification.pairingCodeKey: currentCode] : [:]
            )
        }
        if vibrateOnAlert {
            vibration.play()
        }
    }

    deinit {
        poller.stop()
    }
}

enum WanderTier {
    static let secondTierMinutes: Double = 10
    static let thirdTierMinutes: Double = 30

    /// 0 means inside the safe zone.
    static func tier(forMinutesOutside minutes: Double) -> Int {
        if minutes >= thirdTierMinutes { return 3 }
        if minutes >= secondTierMinutes { return 2 }
        return 1
    }

    static func description(_ tier: Int) -> String {
        switch tier {
        case 1: return "Alert 1 sent: left the safe zone"
        case 2: return "Alert 2 sent: outside 10 minutes, with vibration"
        case 3: return "Alert 3 sent: outside 30 minutes, 10 seconds of vibration"
        default: return "No alerts sent"
        }
    }
}
