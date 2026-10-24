//
//  Notifications.swift
//  DementiaCareHackathon
//
//  Local notifications: immediate alerts and scheduled event reminders.
//

import Foundation
import UserNotifications

enum LocalNotifier {
    /// Shows a notification right away (trigger nil means deliver now).
    static func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

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

    /// Replaces all scheduled event reminders on this phone with reminders for the given events.
    /// The dementia level adds repeats of each reminder.
    static func reschedule(events: [ScheduleEvent], level: DementiaLevel) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let oldIDs = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)

            let now = Date()
            for event in events where event.hasReminder {
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

                    let content = UNMutableNotificationContent()
                    content.title = event.title
                    if repeatIndex > 0 {
                        content.body = "Reminder: \(event.title)"
                    } else if event.reminderMinutesBefore == 0 {
                        content.body = "It is time for \(event.title)."
                    } else {
                        content.body = "\(event.title) starts in \(event.reminderMinutesBefore) minutes."
                    }
                    content.sound = .default

                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: components,
                        repeats: event.repeatRule != .never
                    )
                    let request = UNNotificationRequest(
                        identifier: "\(prefix)\(event.id)-\(repeatIndex)",
                        content: content,
                        trigger: trigger
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
