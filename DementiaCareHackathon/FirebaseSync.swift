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

    static func updateLocation(pairingCode: String, location: CLLocation, isOutside: Bool, distanceMeters: Double) {
        guard pairingCode.count == 6 else { return }
        let fields: [String: [String: Any]] = [
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
    var distanceFromHomeMeters: Double?

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
        distanceFromHomeMeters = data["distanceFromHomeMeters"] as? Double
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
    private var lastKnownOutside: Bool?

    /// Starts checking the patient in this caretaker's setup.
    /// Does not restart if the code and email are unchanged; alert preferences are always updated.
    func connect(profile: CaretakerProfile) {
        notifyOnAlert = profile.notifyOnAlert
        vibrateOnAlert = profile.vibrateOnAlert

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
            }
        }
    }

    func disconnect() {
        poller.stop()
        isFetching = false
        currentCode = ""
        currentEmail = ""
        patient = nil
        lastKnownOutside = nil
        state = .idle
    }

    private func handleZoneChange(_ remote: RemotePatient) {
        // Only alert once a location has been shared.
        guard remote.lastCoordinate != nil else { return }
        let outside = remote.isOutsideZone
        defer { lastKnownOutside = outside }

        if outside && lastKnownOutside != true {
            var body = "\(remote.displayName) has left the safe zone."
            if let meters = remote.distanceFromHomeMeters {
                body += " They are \(Distance.milesText(meters: meters)) from home."
            }
            alert(title: "\(remote.displayName) wandered off", body: body)
        } else if !outside && lastKnownOutside == true {
            alert(title: "\(remote.displayName) is back", body: "\(remote.displayName) is inside the safe zone again.")
        }
    }

    private func alert(title: String, body: String) {
        if notifyOnAlert {
            LocalNotifier.send(id: "caretaker-zone", title: title, body: body, spokenText: "\(title). \(body)")
        }
        if vibrateOnAlert {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    deinit {
        poller.stop()
    }
}
