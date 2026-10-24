//
//  Schedule.swift
//  DementiaCareHackathon
//
//  Schedule events shared between the patient and caretaker through Firestore.
//

import Foundation

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

    var firestoreFields: [String: [String: Any]] {
        [
            "title": FirestoreREST.string(title),
            "date": FirestoreREST.timestamp(date),
            "repeat": FirestoreREST.string(repeatRule.rawValue),
            "reminderMinutesBefore": FirestoreREST.int(reminderMinutesBefore),
            "createdBy": FirestoreREST.string(createdBy),
            "hasRecording": FirestoreREST.bool(hasCustomRecording)
        ]
    }
}

extension ScheduleEvent {
    init?(id: String, data: [String: Any]) {
        guard let title = data["title"] as? String,
              let date = data["date"] as? Date else { return nil }
        self.id = id
        self.title = title
        self.date = date
        self.repeatRule = (data["repeat"] as? String).flatMap { RepeatRule(rawValue: $0) } ?? .never
        self.reminderMinutesBefore = data["reminderMinutesBefore"] as? Int ?? 0
        self.createdBy = data["createdBy"] as? String ?? ""
        self.hasCustomRecording = data["hasRecording"] as? Bool ?? false
    }
}

/// Keeps a patient's events in sync with Firestore by checking every few seconds,
/// and adds or deletes events.
final class ScheduleStore: ObservableObject {
    static let pollSeconds: TimeInterval = 4

    @Published var events: [ScheduleEvent] = []
    @Published var errorMessage: String?

    private let poller = Poller()
    private var pairingCode = ""
    private var isFetching = false
    /// While a write is in progress, check results are ignored so they do not undo the local change.
    private var writesInProgress = 0

    private var collectionPath: String {
        "\(PatientCloud.path(pairingCode: pairingCode))/events"
    }

    func listen(pairingCode: String) {
        if pairingCode == self.pairingCode && !self.pairingCode.isEmpty {
            return
        }
        stop()
        guard pairingCode.count == 6 else { return }
        self.pairingCode = pairingCode

        poller.start(every: ScheduleStore.pollSeconds) { [weak self] in
            self?.fetch()
        }
    }

    func stop() {
        poller.stop()
        pairingCode = ""
        isFetching = false
        if !events.isEmpty {
            events = []
        }
    }

    private func fetch() {
        guard !isFetching, writesInProgress == 0, pairingCode.count == 6 else { return }
        isFetching = true
        let code = pairingCode

        FirestoreREST.list(collectionPath) { [weak self] result in
            guard let self = self else { return }
            self.isFetching = false
            guard code == self.pairingCode, self.writesInProgress == 0 else { return }

            switch result {
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            case .success(let documents):
                if self.errorMessage != nil {
                    self.errorMessage = nil
                }
                let fetched = documents
                    .compactMap { ScheduleEvent(id: $0.id, data: $0.fields) }
                    .sorted { $0.id < $1.id }
                // Only publish when something changed, so reminders are not rescheduled every check.
                if fetched != self.events {
                    self.events = fetched
                }
            }
        }
    }

    /// Saves the event, and its voice message if one was recorded.
    func add(_ event: ScheduleEvent, recording: Data?) {
        guard pairingCode.count == 6 else { return }
        var saved = event
        saved.hasCustomRecording = recording != nil
        if let recording = recording {
            RecordingCloud.upload(pairingCode: pairingCode, id: saved.id, data: recording)
        }

        events = (events + [saved]).sorted { $0.id < $1.id }
        writesInProgress += 1
        FirestoreREST.patch("\(collectionPath)/\(saved.id)", fields: saved.firestoreFields) { [weak self] _ in
            self?.writesInProgress -= 1
        }
    }

    func delete(_ event: ScheduleEvent) {
        guard pairingCode.count == 6 else { return }
        if event.hasCustomRecording {
            RecordingCloud.delete(pairingCode: pairingCode, id: event.id)
        }

        events.removeAll { $0.id == event.id }
        writesInProgress += 1
        FirestoreREST.delete("\(collectionPath)/\(event.id)") { [weak self] _ in
            self?.writesInProgress -= 1
        }
    }
}
