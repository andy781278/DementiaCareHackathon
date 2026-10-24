//
//  HomeViews.swift
//  DementiaCareHackathon
//
//  Settings tabs. Tapping an item opens that field on its own screen to change it.
//

import SwiftUI

struct PatientSettingsView: View {
    @EnvironmentObject private var store: AppStore
    let profile: PatientProfile

    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                ForEach(PatientStep.homeRows, id: \.self) { step in
                    NavigationLink(destination: PatientFieldEditor(step: step, profile: profile)) {
                        SummaryRow(label: step.rowLabel, value: step.value(for: profile))
                    }
                }
            } header: {
                Text("Setup")
                    .font(.headline)
            } footer: {
                Text("Tap an item to change it.")
                    .font(.body)
            }

            Section {
                NavigationLink(destination: WanderingMessageView(pairingCode: profile.pairingCode)) {
                    SummaryRow(
                        label: "Wandering voice message",
                        value: "Record what the patient hears when they leave the safe zone"
                    )
                }
            } header: {
                Text("Voice messages")
                    .font(.headline)
            }

            Section {
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Text("Change role")
                        .font(.title3)
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Change role? This clears all setup on this phone.",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Clear setup", role: .destructive) {
                store.reset()
            }
        }
    }
}

struct CaretakerSettingsView: View {
    @EnvironmentObject private var store: AppStore
    let profile: CaretakerProfile

    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                ForEach(CaretakerStep.allCases, id: \.self) { step in
                    NavigationLink(destination: CaretakerFieldEditor(step: step, profile: profile)) {
                        SummaryRow(label: step.rowLabel, value: step.value(for: profile))
                    }
                }
            } header: {
                Text("Setup")
                    .font(.headline)
            } footer: {
                Text("Tap an item to change it.")
                    .font(.body)
            }

            Section {
                NavigationLink(destination: WanderingMessageView(pairingCode: profile.patientPairingCode)) {
                    SummaryRow(
                        label: "Wandering voice message",
                        value: "Record what the patient hears when they leave the safe zone"
                    )
                }
            } header: {
                Text("Voice messages")
                    .font(.headline)
            }

            Section {
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Text("Change role")
                        .font(.title3)
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Change role? This clears all setup on this phone.",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Clear setup", role: .destructive) {
                store.reset()
            }
        }
    }
}
