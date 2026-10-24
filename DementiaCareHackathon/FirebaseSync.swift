//
//  FirebaseSync.swift
//  DementiaCareHackathon
//
//  Shares patient data through Firestore.
//  Each patient is stored at patients/{pairingCode}. Schedule events are at patients/{pairingCode}/events.
//

import Foundation
import CoreLocation
import AudioToolbox
import FirebaseFirestore

// MARK: - Patient side

enum PatientCloud {
    static var patients: CollectionReference {
        Firestore.firestore().collection("patients")
    }

    /// Writes the patient's setup to Firestore. Uses merge so location fields are kept.
    static func upload(_ profile: PatientProfile) {
        guard profile.pairingCode.count == 6 else { return }

        var data: [String: Any] = [
            "name": profile.name,
            "homeAddress": profile.displayHomeAddress,
            "safeRadiusMiles": profile.safeRadiusMiles,
            "hasCaretaker": profile.hasCaretaker,
            "caretakerEmail": profile.caretakerEmail.trimmed.lowercased(),
            "dementiaLevel": profile.dementiaLevel.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let latitude = profile.homeLatitude, let longitude = profile.homeLongitude {
            data["homeLocation"] = GeoPoint(latitude: latitude, longitude: longitude)
        }

        patients.document(profile.pairingCode).setData(data, merge: true) { error in
            if let error = error {
                print("Firestore upload error: \(error)")
            }
        }
    }

    static func updateLocation(pairingCode: String, location: CLLocation, isOutside: Bool, distanceMeters: Double) {
        guard pairingCode.count == 6 else { return }
        let data: [String: Any] = [
            "lastLocation": GeoPoint(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            "lastLocationAt": FieldValue.serverTimestamp(),
            "isOutsideZone": isOutside,
            "distanceFromHomeMeters": distanceMeters
        ]
        patients.document(pairingCode).setData(data, merge: true) { error in
            if let error = error {
                print("Firestore location error: \(error)")
            }
        }
    }

    static func delete(pairingCode: String) {
        guard pairingCode.count == 6 else { return }
        patients.document(pairingCode).delete { error in
            if let error = error {
                print("Firestore delete error: \(error)")
            }
        }
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
        updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        if let home = data["homeLocation"] as? GeoPoint {
            homeLatitude = home.latitude
            homeLongitude = home.longitude
        }
        if let last = data["lastLocation"] as? GeoPoint {
            lastLatitude = last.latitude
            lastLongitude = last.longitude
        }
        lastLocationAt = (data["lastLocationAt"] as? Timestamp)?.dateValue()
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

/// Listens to one patient's record, reports whether the caretaker is connected,
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

    private var listener: ListenerRegistration?
    private var currentCode = ""
    private var currentEmail = ""
    private var notifyOnAlert = true
    private var vibrateOnAlert = true
    private var lastKnownOutside: Bool?

    /// Starts listening to the patient in this caretaker's setup.
    /// Does not restart if the code and email are unchanged; alert preferences are always updated.
    func connect(profile: CaretakerProfile) {
        notifyOnAlert = profile.notifyOnAlert
        vibrateOnAlert = profile.vibrateOnAlert

        let code = profile.patientPairingCode
        let email = profile.email.trimmed.lowercased()
        if listener != nil && code == currentCode && email == currentEmail {
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

        listener = PatientCloud.patients
            .document(code)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    self.patient = nil
                    self.state = .failed(error.localizedDescription)
                    return
                }

                guard let snapshot = snapshot, snapshot.exists, let data = snapshot.data() else {
                    self.patient = nil
                    self.state = .notFound
                    return
                }

                let remote = RemotePatient(data: data)
                if remote.caretakerEmail != self.currentEmail {
                    self.patient = nil
                    self.state = .emailMismatch
                    return
                }

                self.patient = remote
                self.state = .connected
                self.handleZoneChange(remote)
            }
    }

    func disconnect() {
        listener?.remove()
        listener = nil
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
            LocalNotifier.send(id: "caretaker-zone", title: title, body: body)
        }
        if vibrateOnAlert {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    deinit {
        listener?.remove()
    }
}
