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
            return "A reminder at each scheduled time, repeated once after 15 minutes."
        case .severe:
            return "A reminder at each scheduled time, repeated 3 more times, 10 minutes apart."
        }
    }
}

// MARK: - Time helpers

enum TimeOfDay {
    /// Today's date at the given hour and minute. Only the hour and minute are used for reminders.
    static func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static func minutesSinceMidnight(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func display(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Medication and meals

struct DoseTime: Identifiable, Codable, Equatable {
    var id = UUID()
    var time: Date
}

struct Medication: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    var dosage: String = ""
    var doseTimes: [DoseTime] = [DoseTime(time: TimeOfDay.date(hour: 9))]
    var startDate: Date = Calendar.current.startOfDay(for: Date())
    var hasEndDate: Bool = false
    var endDate: Date = Calendar.current.date(
        byAdding: .day,
        value: 30,
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()

    var sortedTimes: [Date] {
        doseTimes
            .map { $0.time }
            .sorted { TimeOfDay.minutesSinceMidnight($0) < TimeOfDay.minutesSinceMidnight($1) }
    }

    var summary: String {
        let times = sortedTimes.map { TimeOfDay.display($0) }.joined(separator: ", ")
        let dose = dosage.trimmed
        return dose.isEmpty ? times : "\(dose) at \(times)"
    }
}

struct MealReminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var time: Date
    var enabled: Bool = true
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
    var medications: [Medication] = []
    var meals: [MealReminder] = PatientProfile.defaultMeals

    var isHomeLocated: Bool {
        homeLatitude != nil && homeLongitude != nil
    }

    static var defaultMeals: [MealReminder] {
        [
            MealReminder(name: "Breakfast", time: TimeOfDay.date(hour: 8)),
            MealReminder(name: "Lunch", time: TimeOfDay.date(hour: 12)),
            MealReminder(name: "Dinner", time: TimeOfDay.date(hour: 18))
        ]
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
        didSet { save() }
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

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
