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
    // The app plays the recording or reads the text aloud itself, instead of relying on the notification sound.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let soundFile = info[NotificationAudio.soundFileKey] as? String
        let spokenText = info[NotificationAudio.spokenTextKey] as? String

        if soundFile != nil || spokenText != nil {
            ForegroundSpeaker.shared.play(soundFile: soundFile, spokenText: spokenText)
            completionHandler([.banner, .list])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }
}
