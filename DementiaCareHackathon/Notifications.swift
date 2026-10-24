//
//  Notifications.swift
//  DementiaCareHackathon
//
//  Local notifications with spoken sounds: immediate alerts and scheduled event reminders.
//

import Foundation
import UserNotifications

enum LocalNotifier {
    /// Shows a notification right away.
    /// Sound: the recording in soundFile if it exists, otherwise spokenText read aloud, otherwise the default chime.
    static func send(
        id: String,
        title: String,
        body: String,
        soundFile: String? = nil,
        spokenText: String? = nil
    ) {
        if let soundFile = soundFile, SoundFiles.exists(soundFile) {
            post(id: id, title: title, body: body, soundFile: soundFile, spokenText: nil)
            return
        }

        if let spokenText = spokenText {
            let name = SoundFiles.ttsFileName(for: spokenText)
            SpeechFileMaker.shared.make(text: spokenText, url: SoundFiles.url(name)) { success in
                post(id: id, title: title, body: body, soundFile: success ? name : nil, spokenText: spokenText)
            }
            return
        }

        post(id: id, title: title, body: body, soundFile: nil, spokenText: nil)
    }

    private static func post(id: String, title: String, body: String, soundFile: String?, spokenText: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        NotificationAudio.apply(to: content, soundFile: soundFile, spokenText: spokenText)

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

/// Sets a notification's sound and records how it should be spoken.
enum NotificationAudio {
    static let spokenTextKey = "spokenText"
    static let hasAudioFileKey = "hasAudioFile"

    /// soundFile is a file in Library/Sounds (a recording or a spoken file). Without one, the default chime is used,
    /// and if the app is open the spoken text is read aloud instead (see AppDelegate).
    static func apply(to content: UNMutableNotificationContent, soundFile: String?, spokenText: String?) {
        if let soundFile = soundFile {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundFile))
        } else {
            content.sound = .default
        }
        var info: [String: Any] = [hasAudioFileKey: soundFile != nil]
        if let spokenText = spokenText {
            info[spokenTextKey] = spokenText
        }
        content.userInfo = info
    }
}

enum ReminderScheduler {
    private static let prefix = "event-"

    /// Increases on every reschedule, so an older reschedule that finishes late does nothing. Main thread only.
    private static var generation = 0

    private struct PlannedReminder {
        let identifier: String
        let content: UNMutableNotificationContent
        let trigger: UNCalendarNotificationTrigger
        let recordingFile: String?
        let spokenText: String
    }

    /// Replaces all scheduled event reminders on this phone.
    /// The dementia level adds repeats. Each reminder plays the event's recording if it has one,
    /// otherwise the event name read aloud.
    static func reschedule(events: [ScheduleEvent], level: DementiaLevel, recordingFiles: [String: String]) {
        DispatchQueue.main.async {
            generation += 1
            let currentGeneration = generation
            let planned = plan(events: events, level: level, recordingFiles: recordingFiles)

            let textsToSpeak = Array(Set(planned.filter { $0.recordingFile == nil }.map { $0.spokenText }))
            makeSpeechFiles(textsToSpeak) {
                guard currentGeneration == generation else { return }

                let center = UNUserNotificationCenter.current()
                center.getPendingNotificationRequests { requests in
                    let oldIDs = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
                    center.removePendingNotificationRequests(withIdentifiers: oldIDs)

                    for item in planned {
                        let soundName = item.recordingFile ?? SoundFiles.ttsFileName(for: item.spokenText)
                        NotificationAudio.apply(
                            to: item.content,
                            soundFile: SoundFiles.exists(soundName) ? soundName : nil,
                            spokenText: item.spokenText
                        )

                        let request = UNNotificationRequest(
                            identifier: item.identifier,
                            content: item.content,
                            trigger: item.trigger
                        )
                        center.add(request) { error in
                            if let error = error {
                                print("Reminder scheduling error: \(error)")
                            }
                        }
                    }
                }
            }
        }
    }

    private static func plan(events: [ScheduleEvent], level: DementiaLevel, recordingFiles: [String: String]) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []
        let now = Date()

        for event in events where event.hasReminder {
            let recordingFile = event.hasCustomRecording ? recordingFiles[event.id] : nil

            for repeatIndex in 0...level.repeatCount {
                let minutesFromEvent = -event.reminderMinutesBefore + repeatIndex * level.repeatIntervalMinutes
                let fireDate = event.date.addingTimeInterval(TimeInterval(minutesFromEvent * 60))

                let components: DateComponents
                switch event.repeatRule {
                case .never:
                    if fireDate < now { continue }
                    components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                case .daily:
                    components = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
                case .weekly:
                    components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: fireDate)
                }

                let body: String
                if repeatIndex > 0 {
                    body = "Reminder: \(event.title)."
                } else if event.reminderMinutesBefore == 0 {
                    body = "It is time for \(event.title)."
                } else {
                    body = "\(event.title) starts in \(event.reminderMinutesBefore) minutes."
                }

                let content = UNMutableNotificationContent()
                content.title = event.title
                content.body = body

                planned.append(PlannedReminder(
                    identifier: "\(prefix)\(event.id)-\(repeatIndex)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: event.repeatRule != .never),
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
