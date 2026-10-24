//
//  FirebaseSync.swift
//  DementiaCareHackathon
//
//  Shares patient data through Firestore.
//  Each patient with a caretaker is stored at patients/{pairingCode}.
//

import Foundation
import FirebaseFirestore

// MARK: - Patient side

enum PatientCloud {
    private static var patients: CollectionReference {
        Firestore.firestore().collection("patients")
    }

    /// Writes the patient's setup to Firestore. Uses merge so later fields (location, battery) are kept.
    static func upload(_ profile: PatientProfile) {
        guard profile.hasCaretaker, profile.pairingCode.count == 6 else { return }

        var data: [String: Any] = [
            "name": profile.name,
            "homeAddress": profile.displayHomeAddress,
            "safeRadiusMiles": profile.safeRadiusMiles,
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

    init(data: [String: Any]) {
        name = data["name"] as? String ?? ""
        homeAddress = data["homeAddress"] as? String ?? ""
        safeRadiusMiles = data["safeRadiusMiles"] as? Double ?? 0
        caretakerEmail = data["caretakerEmail"] as? String ?? ""
        dementiaLevel = (data["dementiaLevel"] as? String).flatMap { DementiaLevel(rawValue: $0) }
        updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
    }
}

/// Listens to one patient's record and reports whether the caretaker is connected.
final class CaretakerConnection: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case notFound
        case emailMismatch
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var patient: RemotePatient?

    private var listener: ListenerRegistration?
    private var currentCode = ""
    private var currentEmail = ""

    /// Starts listening to the patient with this pairing code. Does nothing if already listening to the same code and email.
    func connect(pairingCode: String, caretakerEmail: String) {
        let email = caretakerEmail.trimmed.lowercased()
        if listener != nil && pairingCode == currentCode && email == currentEmail {
            return
        }

        disconnect()
        guard pairingCode.count == 6 else {
            state = .notFound
            return
        }

        currentCode = pairingCode
        currentEmail = email
        state = .connecting

        listener = Firestore.firestore()
            .collection("patients")
            .document(pairingCode)
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
            }
    }

    func disconnect() {
        listener?.remove()
        listener = nil
        currentCode = ""
        currentEmail = ""
        patient = nil
        state = .idle
    }

    deinit {
        listener?.remove()
    }
}
