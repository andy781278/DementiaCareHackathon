//
//  BatteryMonitor.swift
//  DementiaCareHackathon
//
//  Runs on the patient's phone. Reads the battery level, shares it through Firestore,
//  and tells the patient to charge the phone when it is low.
//

import Foundation
import UIKit

final class BatteryMonitor: ObservableObject {
    @Published var percent: Int?
    @Published var isCharging = false
    /// A test level set by hand. The simulator has no battery, so this is used to try the alert there.
    @Published var testPercent: Int?

    /// Sound file of a recorded low battery message, if one was recorded.
    var lowBatterySoundFile: String?

    static let defaultMessage = "Your phone battery is low. Please plug in your phone to charge it."

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var profile: PatientProfile?
    private var hasAlerted = false
    private var lastUploaded: (percent: Int, charging: Bool)?
    private var observers: [NSObjectProtocol] = []

    func start(profile: PatientProfile) {
        self.profile = profile
        UIDevice.current.isBatteryMonitoringEnabled = true

        if observers.isEmpty {
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            })
            observers.append(center.addObserver(
                forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            })
        }

        // Make the spoken message ahead of time so the alert does not wait for it.
        SpeechFileMaker.shared.make(
            text: BatteryMonitor.defaultMessage,
            url: SoundFiles.url(SoundFiles.ttsFileName(for: BatteryMonitor.defaultMessage))
        ) { _ in }

        refresh()
    }

    /// Call when the setup changes (for example the alert level).
    func update(profile: PatientProfile) {
        self.profile = profile
        evaluate(forceUpload: false)
    }

    /// Sets or clears the test level.
    func setTestPercent(_ value: Int?) {
        testPercent = value
        refresh()
    }

    private func refresh() {
        if let testPercent = testPercent {
            percent = testPercent
            isCharging = false
        } else {
            let device = UIDevice.current
            if device.batteryLevel >= 0 {
                percent = Int((device.batteryLevel * 100).rounded())
                isCharging = device.batteryState == .charging || device.batteryState == .full
            } else {
                // The level is unknown, for example in the simulator.
                percent = nil
                isCharging = false
            }
        }
        evaluate(forceUpload: false)
    }

    private func evaluate(forceUpload: Bool) {
        guard let profile = profile, let percent = percent else { return }

        if forceUpload || lastUploaded?.percent != percent || lastUploaded?.charging != isCharging {
            lastUploaded = (percent, isCharging)
            PatientCloud.updateBattery(pairingCode: profile.pairingCode, percent: percent, isCharging: isCharging)
        }

        let isLow = percent <= profile.batteryThreshold && !isCharging
        if isLow && !hasAlerted {
            hasAlerted = true
            LocalNotifier.send(
                id: "battery-low",
                title: "Battery low",
                body: "Your phone battery is at \(percent)%. Please plug in your phone to charge it.",
                soundFile: lowBatterySoundFile,
                spokenText: BatteryMonitor.defaultMessage
            )
        } else if !isLow {
            hasAlerted = false
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
