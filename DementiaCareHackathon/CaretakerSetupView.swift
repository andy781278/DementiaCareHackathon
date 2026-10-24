//
//  CaretakerSetupView.swift
//  DementiaCareHackathon
//

import SwiftUI

struct CaretakerSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CaretakerProfile

    let isEditing: Bool

    init(profile: CaretakerProfile, isEditing: Bool) {
        _draft = State(initialValue: profile)
        self.isEditing = isEditing
    }

    var body: some View {
        Form {
            Section {
                TextField("Full name", text: $draft.name)
                    .textContentType(.name)
                TextField("Email", text: $draft.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            } header: {
                Text("About you")
            }

            Section {
                TextField("6-digit pairing code", text: $draft.patientPairingCode)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
            } header: {
                Text("Sync with patient")
            } footer: {
                Text("Enter the pairing code shown on the patient's setup screen.")
            }

            Section {
                Toggle("Vibrate on alerts", isOn: $draft.vibrateOnAlert)
                Toggle("Send notifications", isOn: $draft.notifyOnAlert)
            } header: {
                Text("Alerts")
            } footer: {
                Text("Alerts are sent when the patient leaves the home area, misses a reminder, has low battery, or stops sharing location.")
            }

            if let message = validationMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Caretaker Setup" : "Caretaker Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isEditing ? "Cancel" : "Back") {
                    if isEditing {
                        dismiss()
                    } else {
                        store.role = nil
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(validationMessage != nil)
            }
        }
        .onChange(of: draft.patientPairingCode) { newValue in
            let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(6))
            if digits != newValue {
                draft.patientPairingCode = digits
            }
        }
    }

    private var validationMessage: String? {
        if draft.name.trimmed.isEmpty {
            return "Enter your name."
        }
        if !AppStore.isValidEmail(draft.email) {
            return "Enter a valid email."
        }
        if draft.patientPairingCode.count != 6 {
            return "Enter the patient's 6-digit pairing code."
        }
        return nil
    }

    private func save() {
        var profile = draft
        profile.name = profile.name.trimmed
        profile.email = profile.email.trimmed
        store.caretakerProfile = profile
        if isEditing {
            dismiss()
        }
    }
}
