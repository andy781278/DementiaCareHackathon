//
//  Models.swift
//  DementiaCareHackathon
//

import Foundation

// MARK: - Roles and levels

enum UserRole: String, Codable {
    case patient
    case caretaker
}

enum DementiaLevel: String, Codable, CaseIterable, Identifiable {
    case mild
    case moderate
    case severe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    /// Number of extra times each reminder repeats after the first one.
    var repeatCount: Int {
        switch self {
        case .mild: return 0
        case .moderate: return 1
        case .severe: return 3
        }
    }

    /// Minutes between repeats of the same reminder.
    var repeatIntervalMinutes: Int {
        switch self {
        case .mild: return 0
        case .moderate: return 15
        case .severe: return 10
        }
    }

    var reminderDescription: String {
        switch self {
        case .mild:
            return "One reminder at each scheduled time."
        case .moderate:
            return "Each reminder repeats once after 15 minutes."
        case .severe:
            return "Each reminder repeats 3 more times, 10 minutes apart."
        }
    }
}

// MARK: - Profiles

struct PatientProfile: Codable, Equatable {
    var name: String = ""

    var homeAddress: String = ""
    var resolvedHomeAddress: String = ""
    var homeLatitude: Double?
    var homeLongitude: Double?
    var safeRadiusMiles: Double = 0.5

    var hasCaretaker: Bool = true
    var caretakerEmail: String = ""
    var pairingCode: String = PatientProfile.generatePairingCode()

    var dementiaLevel: DementiaLevel = .mild

    var isHomeLocated: Bool {
        homeLatitude != nil && homeLongitude != nil
    }

    var displayHomeAddress: String {
        resolvedHomeAddress.isEmpty ? homeAddress : resolvedHomeAddress
    }

    /// Pairing code with a space in the middle, e.g. "123 456".
    var formattedPairingCode: String {
        guard pairingCode.count == 6 else { return pairingCode }
        return "\(pairingCode.prefix(3)) \(pairingCode.suffix(3))"
    }

    static func generatePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }
}

struct CaretakerProfile: Codable, Equatable {
    var name: String = ""
    var email: String = ""
    var patientPairingCode: String = ""
    var vibrateOnAlert: Bool = true
    var notifyOnAlert: Bool = true
}

// MARK: - Store

/// Holds the role and setup for this phone and saves it to UserDefaults on every change.
final class AppStore: ObservableObject {
    @Published var role: UserRole? {
        didSet { save() }
    }
    @Published var patientProfile: PatientProfile? {
        didSet {
            save()
            syncPatient(previous: oldValue)
        }
    }
    @Published var caretakerProfile: CaretakerProfile? {
        didSet { save() }
    }

    private static let storageKey = "appState.v1"

    private struct StoredState: Codable {
        var role: UserRole?
        var patientProfile: PatientProfile?
        var caretakerProfile: CaretakerProfile?
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: AppStore.storageKey),
           let state = try? JSONDecoder().decode(StoredState.self, from: data) {
            role = state.role
            patientProfile = state.patientProfile
            caretakerProfile = state.caretakerProfile
        }
        // Make sure the shared record exists, e.g. for a setup saved before syncing was added.
        if role == .patient, let profile = patientProfile {
            PatientCloud.upload(profile)
        }
    }

    /// Uploads the patient's setup, and removes the old shared record when setup is cleared.
    private func syncPatient(previous: PatientProfile?) {
        if let current = patientProfile {
            PatientCloud.upload(current)
        }
        if let previous = previous, patientProfile?.pairingCode != previous.pairingCode {
            PatientCloud.delete(pairingCode: previous.pairingCode)
        }
    }

    /// Clears the role and all setup on this phone.
    func reset() {
        role = nil
        patientProfile = nil
        caretakerProfile = nil
    }

    private func save() {
        let state = StoredState(
            role: role,
            patientProfile: patientProfile,
            caretakerProfile: caretakerProfile
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: AppStore.storageKey)
        }
    }

    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}

enum Distance {
    static let metersPerMile = 1609.344

    static func milesText(meters: Double) -> String {
        String(format: "%.2f miles", meters / metersPerMile)
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
