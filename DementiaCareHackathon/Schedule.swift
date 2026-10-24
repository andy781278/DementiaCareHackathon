//
//  Schedule.swift
//  DementiaCareHackathon
//
//  Schedule events shared between the patient and caretaker through Firestore.
//

import Foundation
import FirebaseFirestore

enum RepeatRule: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        }
    }
}

enum ReminderOption: Int, CaseIterable, Identifiable {
    case none = -1
    case atTime = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "No reminder"
        case .atTime: return "At time of event"
        case .fiveMinutes: return "5 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        }
    }
}

struct ScheduleEvent: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String = ""
    /// Date and time of the first occurrence.
    var date: Date
    var repeatRule: RepeatRule = .never
    /// Minutes before the event to remind. -1 means no reminder.
    var reminderMinutesBefore: Int = 0
    /// "patient" or "caretaker".
    var createdBy: String = ""
    /// True when a voice message was recorded for this event.
    var hasCustomRecording: Bool = false

    var hasReminder: Bool {
        reminderMinutesBefore >= 0
    }

    var minutesSinceMidnight: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    var timeText: String {
        date.formatted(date: .omitted, time: .shortened)
    }

    var reminderText: String {
        ReminderOption(rawValue: reminderMinutesBefore)?.title
            ?? "\(reminderMinutesBefore) minutes before"
    }

    func occurs(on day: Date) -> Bool {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: date)
        let targetDay = calendar.startOfDay(for: day)
        switch repeatRule {
        case .never:
            return startDay == targetDay
        case .daily:
            return targetDay >= startDay
        case .weekly:
            return targetDay >= startDay
                && calendar.component(.weekday, from: date) == calendar.component(.weekday, from: day)
        }
    }

    var firestoreData: [String: Any] {
        [
            "title": title,
            "date": Timestamp(date: date),
            "repeat": repeatRule.rawValue,
            "reminderMinutesBefore": reminderMinutesBefore,
            "createdBy": createdBy,
            "hasRecording": hasCustomRecording
        ]
    }
}

extension ScheduleEvent {
    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String,
              let timestamp = data["date"] as? Timestamp else { return nil }
        self.id = id
        self.title = title
        self.date = timestamp.dateValue()
        self.repeatRule = (data["repeat"] as? String).flatMap { RepeatRule(rawValue: $0) } ?? .never
        self.reminderMinutesBefore = data["reminderMinutesBefore"] as? Int ?? 0
        self.createdBy = data["createdBy"] as? String ?? ""
        self.hasCustomRecording = data["hasRecording"] as? Bool ?? false
    }
}

/// Listens to a patient's events in Firestore and adds or deletes events.
final class ScheduleStore: ObservableObject {
    @Published var events: [ScheduleEvent] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var pairingCode = ""

    private var collection: CollectionReference? {
        guard pairingCode.count == 6 else { return nil }
        return PatientCloud.patients.document(pairingCode).collection("events")
    }

    func listen(pairingCode: String) {
        if listener != nil && pairingCode == self.pairingCode {
            return
        }
        stop()
        self.pairingCode = pairingCode
        guard let collection = collection else { return }

        listener = collection.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }
            self.errorMessage = nil
            self.events = snapshot?.documents.compactMap { document in
                ScheduleEvent(id: document.documentID, data: document.data())
            } ?? []
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
        pairingCode = ""
        events = []
    }

    /// Saves the event, and its voice message if one was recorded.
    func add(_ event: ScheduleEvent, recording: Data?) {
        var saved = event
        saved.hasCustomRecording = recording != nil
        if let recording = recording {
            RecordingCloud.upload(pairingCode: pairingCode, id: saved.id, data: recording)
        }
        collection?.document(saved.id).setData(saved.firestoreData) { error in
            if let error = error {
                print("Event save error: \(error)")
            }
        }
    }

    func delete(_ event: ScheduleEvent) {
        if event.hasCustomRecording {
            RecordingCloud.delete(pairingCode: pairingCode, id: event.id)
        }
        collection?.document(event.id).delete { error in
            if let error = error {
                print("Event delete error: \(error)")
            }
        }
    }

    deinit {
        listener?.remove()
    }
}
