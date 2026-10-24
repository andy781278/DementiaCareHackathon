//
//  DementiaCareHackathonApp.swift
//  DementiaCareHackathon
//
//  Created by Andy Zhu on 10/24/26.
//

import SwiftUI
import UserNotifications

@main
struct DementiaCareHackathonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            } else if !granted {
                print("Notification permission denied")
            }
        }
        return true
    }

    // Show the notification even when the app is open in the foreground.
    // If it has no spoken sound file, read its text aloud instead of playing the chime.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let hasAudioFile = info[NotificationAudio.hasAudioFileKey] as? Bool ?? false
        if !hasAudioFile, let spokenText = info[NotificationAudio.spokenTextKey] as? String {
            ForegroundSpeaker.shared.speak(spokenText)
            completionHandler([.banner, .list])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }
}
