# Dementia Care

iOS app for people with dementia and their caretakers. Built by a team at the c0mpiled-16 UCSD hackathon (October 2026), where it won 3rd place.

The app has two roles on one install. The patient's phone runs in the background and reports location, battery, and reminder status. The caretaker's phone receives alerts. The two phones are linked by a pairing code.

## Features

- **Wander alerts:** the patient's phone tracks distance from home. Alerts escalate in tiers the longer the patient stays outside the home zone. The caretaker can mark the patient as safe to stop the alerts.
- **Schedule reminders:** the caretaker sets daily events such as medication and meals. Reminders play the caretaker's recorded voice, or text-to-speech when there is no recording. Reminder settings are adjusted to the patient's dementia level.
- **Battery alerts:** the caretaker is notified when the patient's phone battery is low.
- **Sync:** patient status is stored in Firebase Firestore through its REST API.

## Built with

Swift, SwiftUI, Core Location, AVFoundation (voice recording and speech synthesis), UserNotifications, Firebase Firestore

## Running it

1. Open `DementiaCareHackathon.xcodeproj` in Xcode.
2. Replace `GoogleService-Info.plist` with the config file from your own Firebase project.
3. Build and run on two iPhones. Choose "Patient" on one and "Caretaker" on the other, then enter the same pairing code on both.
