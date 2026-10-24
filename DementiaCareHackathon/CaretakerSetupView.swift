//
//  CaretakerSetupView.swift
//  DementiaCareHackathon
//
//  Caretaker setup, one field per screen. The patient's pairing code is entered last.
//

import SwiftUI

// MARK: - Steps

enum CaretakerStep: Hashable, CaseIterable {
    case name
    case email
    case alerts
    case pairingCode
    case lowBattery

    /// Steps used in the setup flow. The battery alert level is only changed in Settings (default 10%).
    static let setupSteps: [CaretakerStep] = [.name, .email, .alerts, .pairingCode]

    var title: String {
        switch self {
        case .name: return "Your name"
        case .email: return "Your email"
        case .alerts: return "How should we alert you?"
        case .pairingCode: return "Patient's pairing code"
        case .lowBattery: return "Low battery alert"
        }
    }

    var subtitle: String? {
        switch self {
        case .name: return nil
        case .email: return "The patient's setup uses this email to find you."
        case .alerts: return "Alerts are sent when the patient leaves the home area, misses a reminder, has low battery, or stops sharing location."
        case .pairingCode: return "Enter the 6-digit code shown at the end of the patient's setup."
        case .lowBattery: return "You are alerted when the patient's phone battery drops to this level."
        }
    }

    var rowLabel: String {
        switch self {
        case .name: return "Name"
        case .email: return "Email"
        case .alerts: return "Alerts"
        case .pairingCode: return "Patient's pairing code"
        case .lowBattery: return "Low battery alert"
        }
    }

    func value(for profile: CaretakerProfile) -> String {
        switch self {
        case .name:
            return profile.name
        case .email:
            return profile.email
        case .alerts:
            var methods: [String] = []
            if profile.vibrateOnAlert { methods.append("Vibrate") }
            if profile.notifyOnAlert { methods.append("Notifications") }
            return methods.isEmpty ? "None" : methods.joined(separator: ", ")
        case .pairingCode:
            return profile.patientPairingCode
        case .lowBattery:
            return "At \(profile.batteryThreshold)%"
        }
    }

    func isComplete(_ profile: CaretakerProfile) -> Bool {
        switch self {
        case .name: return !profile.name.trimmed.isEmpty
        case .email: return AppStore.isValidEmail(profile.email)
        case .alerts: return true
        case .pairingCode: return profile.patientPairingCode.count == 6
        case .lowBattery: return true
        }
    }
}

// MARK: - Step content

struct CaretakerStepContent: View {
    let step: CaretakerStep
    @Binding var profile: CaretakerProfile

    var body: some View {
        switch step {
        case .name:
            BigTextField(
                placeholder: "Full name",
                text: $profile.name,
                contentType: .name,
                capitalization: .words
            )

        case .email:
            BigTextField(
                placeholder: "you@email.com",
                text: $profile.email,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                capitalization: .never,
                autocorrect: false
            )

        case .alerts:
            VStack(spacing: 16) {
                ChoiceCard(
                    title: "Vibrate",
                    detail: "Your phone vibrates when something changes.",
                    systemImage: "iphone.radiowaves.left.and.right",
                    isSelected: profile.vibrateOnAlert
                ) {
                    profile.vibrateOnAlert.toggle()
                }
                ChoiceCard(
                    title: "Notifications",
                    detail: "You get a notification with details.",
                    systemImage: "bell.fill",
                    isSelected: profile.notifyOnAlert
                ) {
                    profile.notifyOnAlert.toggle()
                }
            }

        case .pairingCode:
            PairingCodeInput(code: $profile.patientPairingCode)

        case .lowBattery:
            BatteryThresholdInput(percent: Binding(
                get: { profile.batteryThreshold },
                set: { profile.lowBatteryPercent = $0 }
            ))
        }
    }
}

struct PairingCodeInput: View {
    @Binding var code: String

    var body: some View {
        TextField("000000", text: $code)
            .font(.system(size: 44, weight: .bold, design: .monospaced))
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .padding(.vertical, 20)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
            .onChange(of: code) { newValue in
                let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(6))
                if digits != newValue {
                    code = digits
                }
            }
    }
}

// MARK: - Setup flow

struct CaretakerSetupFlow: View {
    @EnvironmentObject private var store: AppStore

    @State private var profile = CaretakerProfile()
    @State private var index = 0

    private let steps = CaretakerStep.setupSteps

    var body: some View {
        Group {
            if index < steps.count {
                let step = steps[index]
                SetupStepLayout(
                    stepLabel: "Step \(index + 1) of \(steps.count)",
                    title: step.title,
                    subtitle: step.subtitle,
                    buttonTitle: "Continue",
                    buttonEnabled: step.isComplete(profile),
                    action: goForward
                ) {
                    CaretakerStepContent(step: step, profile: $profile)
                }
                .id(step)
            } else {
                finishScreen
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackToolbarButton(action: goBack)
            }
        }
    }

    private var finishScreen: some View {
        SetupStepLayout(
            title: "Setup complete",
            subtitle: "Check your details, then tap Done.",
            buttonTitle: "Done",
            action: finish
        ) {
            SummaryBox(rows: steps.map { (label: $0.rowLabel, value: $0.value(for: profile)) })
        }
    }

    private func goForward() {
        withAnimation {
            index += 1
        }
    }

    private func goBack() {
        if index == 0 {
            store.role = nil
        } else {
            withAnimation {
                index -= 1
            }
        }
    }

    private func finish() {
        var saved = profile
        saved.name = saved.name.trimmed
        saved.email = saved.email.trimmed
        store.caretakerProfile = saved
    }
}

// MARK: - Editing one field later

struct CaretakerFieldEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let step: CaretakerStep
    @State private var profile: CaretakerProfile

    init(step: CaretakerStep, profile: CaretakerProfile) {
        self.step = step
        _profile = State(initialValue: profile)
    }

    var body: some View {
        SetupStepLayout(
            title: step.title,
            subtitle: step.subtitle,
            buttonTitle: "Save",
            buttonEnabled: step.isComplete(profile),
            action: save
        ) {
            CaretakerStepContent(step: step, profile: $profile)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        var saved = profile
        saved.name = saved.name.trimmed
        saved.email = saved.email.trimmed
        store.caretakerProfile = saved
        dismiss()
    }
}
