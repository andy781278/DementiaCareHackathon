//
//  Notifications.swift
//  DementiaCareHackathon
//
//  Local notifications with spoken sounds: immediate alerts and scheduled event reminders.
//
//  Sound for each notification:
//  - a recording, if one exists
//  - otherwise a spoken (text-to-speech) sound file, if one could be made
//  - otherwise the default chime
//  While the app is open, AppDelegate plays the recording or reads the text aloud itself.
//

import Foundation
import UserNotifications
import AudioToolbox

/// Vibration patterns for alerts. The simulator does not vibrate.
enum AlertVibration {
    case none
    /// About 2.5 seconds of pulses.
    case short
    /// About 10 seconds of pulses.
    case long

    /// When the current vibration should stop. Main thread only.
    private static var endTime: Date?

    var duration: TimeInterval {
        switch self {
        case .none: return 0
        case .short: return 2.5
        case .long: return 10
        }
    }

    func play() {
        guard duration > 0 else { return }
        let duration = self.duration
        DispatchQueue.main.async {
            let alreadyRunning = AlertVibration.endTime != nil
            AlertVibration.endTime = Date().addingTimeInterval(duration)
            if !alreadyRunning {
                AlertVibration.pulse()
            }
        }
    }

    /// Starts the next pulse only after the previous one finished. Back-to-back vibration calls made on a
    /// timer can be dropped by iOS, which is why the earlier version did not reach 10 seconds.
    private static func pulse() {
        guard let end = endTime, Date() < end else {
            endTime = nil
            return
        }
        AudioServicesPlaySystemSoundWithCompletion(kSystemSoundID_Vibrate) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pulse()
            }
        }
    }
}

/// Repeats an urgent notification a few times, a couple of seconds apart, so the phone keeps buzzing
/// when the app is in the background (where the app itself cannot vibrate the phone).
enum UrgentRepeat {
    static let count = 5
    static let intervalSeconds: TimeInterval = 2

    static func identifiers(id: String) -> [String] {
        (1...count).map { "\(id)-repeat-\($0)" }
    }

    static func schedule(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        for (index, identifier) in identifiers(id: id).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = id
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: intervalSeconds * Double(index + 1),
                repeats: false
            )
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(id: id))
    }
}

extension String {
    /// The text without emoji, for reading aloud.
    var withoutEmoji: String {
        let kept = unicodeScalars.filter { scalar in
            if scalar.value == 0xFE0F || scalar.value == 0x200D { return false }
            let properties = scalar.properties
            return !(properties.isEmoji && (properties.isEmojiPresentation || scalar.value > 0x238C))
        }
        var text = String(String.UnicodeScalarView(kept))
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// Sets a notification's sound and stores what to play while the app is open.
enum NotificationAudio {
    static let spokenTextKey = "spokenText"
    static let soundFileKey = "soundFile"

    static func apply(to content: UNMutableNotificationContent, soundFile: String?, spokenText: String?) {
        if let soundFile = soundFile {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
        } else {
            content.sound = .default
        }
        var info: [String: Any] = [:]
        if let soundFile = soundFile {
            info[soundFileKey] = soundFile
        }
        if let spokenText = spokenText {
            info[spokenTextKey] = spokenText
        }
        content.userInfo = info
    }
}

enum WanderNotification {
    static let category = "WANDER_ALERT"
    static let markSafeAction = "MARK_SAFE"
    static let pairingCodeKey = "pairingCode"

    /// Adds a "Mark as safe" button to wander alerts on the caretaker phone.
    static func registerCategory() {
        let markSafe = UNNotificationAction(identifier: markSafeAction, title: "Mark as safe", options: [])
        let category = UNNotificationCategory(
            identifier: self.category,
            actions: [markSafe],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

enum LocalNotifier {
    /// Longest wait for a spoken sound file before showing the alert with the default chime.
    private static let speechWaitSeconds: TimeInterval = 2

    /// Shows a notification right away.
    static func send(
        id: String,
        title: String,
        body: String,
        soundFile: String? = nil,
        spokenText: String? = nil,
        category: String? = nil,
        extraInfo: [String: Any] = [:]
    ) {
        func post(soundFile: String?, spokenText: String?) {
            self.post(
                id: id, title: title, body: body, soundFile: soundFile, spokenText: spokenText,
                category: category, extraInfo: extraInfo
            )
        }

        if let soundFile = soundFile, SoundFiles.exists(soundFile) {
            post(soundFile: soundFile, spokenText: spokenText)
            return
        }

        guard let spokenText = spokenText else {
            post(soundFile: nil, spokenText: nil)
            return
        }

        let name = SoundFiles.ttsFileName(for: spokenText)
        if SoundFiles.exists(name) {
            post(soundFile: name, spokenText: spokenText)
            return
        }

        // Make the spoken file, but do not hold the alert back for more than a moment.
        var posted = false
        SpeechFileMaker.shared.make(text: spokenText, url: SoundFiles.url(name)) { success in
            guard !posted else { return }
            posted = true
            post(soundFile: success ? name : nil, spokenText: spokenText)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + speechWaitSeconds) {
            guard !posted else { return }
            posted = true
            post(soundFile: nil, spokenText: spokenText)
        }
    }

    private static func post(
        id: String,
        title: String,
        body: String,
        soundFile: String?,
        spokenText: String?,
        category: String?,
        extraInfo: [String: Any]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        NotificationAudio.apply(to: content, soundFile: soundFile, spokenText: spokenText)
        if let category = category {
            content.categoryIdentifier = category
        }
        if !extraInfo.isEmpty {
            var info = content.userInfo
            for (key, value) in extraInfo {
                info[key] = value
            }
            content.userInfo = info
        }

        // A nil trigger delivers the notification right away.
        let request = UNNotificationRequest(
            identifier: "\(id)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
}

enum ReminderScheduler {
    private static let prefix = "event-"

    /// Increases on every reschedule, so an older reschedule that finishes late does nothing. Main thread only.
    private static var generation = 0

    private struct PlannedReminder {
        let identifier: String
        let title: String
        let body: String
        let components: DateComponents
        let repeats: Bool
        let recordingFile: String?
        let spokenText: String
    }

    /// Replaces all scheduled event reminders on this phone.
    /// Reminders are scheduled right away with whatever sounds already exist. Missing spoken
    /// sounds are then made in the background, and the reminders are scheduled once more to use them.
    static func reschedule(events: [ScheduleEvent], level: DementiaLevel, recordingFiles: [String: String]) {
        DispatchQueue.main.async {
            generation += 1
            let currentGeneration = generation
            let planned = plan(events: events, level: level, recordingFiles: recordingFiles)
            schedule(planned)

            let missingTexts = Array(Set(
                planned
                    .filter { $0.recordingFile == nil }
                    .map { $0.spokenText }
                    .filter { !SoundFiles.exists(SoundFiles.ttsFileName(for: $0)) }
            ))
            guard !missingTexts.isEmpty else { return }

            makeSpeechFiles(missingTexts) {
                // Schedule again only if nothing newer replaced this reschedule.
                guard currentGeneration == generation else { return }
                schedule(planned)
            }
        }
    }

    private static func schedule(_ planned: [PlannedReminder]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let oldIDs = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)

            let now = Date()
            for item in planned {
                let trigger = UNCalendarNotificationTrigger(dateMatching: item.components, repeats: item.repeats)
                // Skip one-time reminders whose time has already passed.
                guard let next = trigger.nextTriggerDate(), next > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body

                let soundName = item.recordingFile ?? SoundFiles.ttsFileName(for: item.spokenText)
                NotificationAudio.apply(
                    to: content,
                    soundFile: SoundFiles.exists(soundName) ? soundName : nil,
                    spokenText: item.spokenText
                )

                let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
                center.add(request) { error in
                    if let error = error {
                        print("Reminder scheduling error: \(error)")
                    }
                }
            }
        }
    }

    private static func plan(events: [ScheduleEvent], level: DementiaLevel, recordingFiles: [String: String]) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        let calendar = Calendar.current

        for event in events where event.hasReminder {
            let recordingFile = event.hasCustomRecording ? recordingFiles[event.id] : nil

            for repeatIndex in 0...level.repeatCount {
                let minutesFromEvent = -event.reminderMinutesBefore + repeatIndex * level.repeatIntervalMinutes
                let fireDate = event.date.addingTimeInterval(TimeInterval(minutesFromEvent * 60))

                let components: DateComponents
                switch event.repeatRule {
                case .never:
                    components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                case .daily:
                    components = calendar.dateComponents([.hour, .minute], from: fireDate)
                case .weekly:
                    components = calendar.dateComponents([.weekday, .hour, .minute], from: fireDate)
                }

                let body: String
                if repeatIndex > 0 {
                    body = "Reminder: \(event.title)."
                } else if event.reminderMinutesBefore == 0 {
                    body = "It is time for \(event.title)."
                } else {
                    body = "\(event.title) starts in \(event.reminderMinutesBefore) minutes."
                }

                planned.append(PlannedReminder(
                    identifier: "\(prefix)\(event.id)-\(repeatIndex)",
                    title: event.title,
                    body: body,
                    components: components,
                    repeats: event.repeatRule != .never,
                    recordingFile: recordingFile,
                    spokenText: event.title
                ))
            }
        }
        return planned
    }

    private static func makeSpeechFiles(_ texts: [String], completion: @escaping () -> Void) {
        guard let first = texts.first else {
            completion()
            return
        }
        SpeechFileMaker.shared.make(text: first, url: SoundFiles.url(SoundFiles.ttsFileName(for: first))) { _ in
            makeSpeechFiles(Array(texts.dropFirst()), completion: completion)
        }
    }
}
