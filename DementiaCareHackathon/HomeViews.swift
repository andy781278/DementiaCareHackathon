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

    @StateObject private var connection = CaretakerConnection()
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                patientStatus
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
        .onAppear {
            connection.connect(pairingCode: profile.patientPairingCode, caretakerEmail: profile.email)
        }
        .onChange(of: profile) { newProfile in
            connection.connect(pairingCode: newProfile.patientPairingCode, caretakerEmail: newProfile.email)
        }
        .confirmationDialog(
            "Change role? This clears all setup on this phone.",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Clear setup", role: .destructive) {
                connection.disconnect()
                store.reset()
            }
        }
    }

    @ViewBuilder
    private var patientStatus: some View {
        switch connection.state {
        case .idle, .connecting:
            HStack(spacing: 12) {
                ProgressView()
                Text("Connecting…")
                    .font(.title3)
            }
            .padding(.vertical, 4)

        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundColor(.green)
            if let patient = connection.patient {
                SummaryRow(label: "Name", value: patient.name)
                SummaryRow(label: "Home address", value: patient.homeAddress)
                SummaryRow(label: "Alert distance", value: String(format: "%.1f miles", patient.safeRadiusMiles))
                SummaryRow(label: "Dementia level", value: patient.dementiaLevel?.title ?? "Unknown")
                if let updatedAt = patient.updatedAt {
                    SummaryRow(label: "Last update", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

        case .notFound:
            Label(
                "No patient found with this code. Check the code shown on the patient's phone.",
                systemImage: "xmark.circle.fill"
            )
            .font(.title3)
            .foregroundColor(.red)

        case .emailMismatch:
            Label(
                "This patient listed a different caretaker email. Your email must match the one entered on the patient's phone.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title3)
            .foregroundColor(.orange)

        case .failed(let message):
            Label("Could not connect: \(message)", systemImage: "wifi.exclamationmark")
                .font(.title3)
                .foregroundColor(.red)
        }
    }
}
