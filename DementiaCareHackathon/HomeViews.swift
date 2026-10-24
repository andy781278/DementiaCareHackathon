//
//  HomeViews.swift
//  DementiaCareHackathon
//
//  Screens shown after setup is saved. Tapping an item opens that field on its own screen to change it.
//

import SwiftUI

struct PatientHomeView: View {
    @EnvironmentObject private var store: AppStore
    let profile: PatientProfile

    @State private var confirmingReset = false

    var body: some View {
        List {
            if profile.hasCaretaker {
                Section {
                    Text(profile.formattedPairingCode)
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } header: {
                    Text("Pairing code")
                        .font(.headline)
                } footer: {
                    Text("The caretaker enters this code in their app.")
                        .font(.body)
                }
            }

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
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Text("Change role")
                        .font(.title3)
                }
            }
        }
        .navigationTitle(profile.name)
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

struct CaretakerHomeView: View {
    @EnvironmentObject private var store: AppStore
    let profile: CaretakerProfile

    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                SummaryRow(label: "Status", value: "Not connected")
            } header: {
                Text("Patient")
                    .font(.headline)
            }

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
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Text("Change role")
                        .font(.title3)
                }
            }
        }
        .navigationTitle(profile.name)
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
