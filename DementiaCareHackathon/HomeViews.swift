//
//  HomeViews.swift
//  DementiaCareHackathon
//
//  Screens shown after setup is saved. They show the saved setup and let it be edited.
//

import SwiftUI

struct PatientHomeView: View {
    @EnvironmentObject private var store: AppStore
    let profile: PatientProfile

    @State private var showingEdit = false
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: profile.name)
                LabeledContent("Dementia level", value: profile.dementiaLevel.title)
            } header: {
                Text("Patient")
            }

            Section {
                LabeledContent(
                    "Address",
                    value: profile.resolvedHomeAddress.isEmpty ? profile.homeAddress : profile.resolvedHomeAddress
                )
                LabeledContent("Alert distance", value: String(format: "%.1f mi", profile.safeRadiusMiles))
            } header: {
                Text("Home")
            }

            Section {
                if profile.hasCaretaker {
                    LabeledContent("Email", value: profile.caretakerEmail)
                    LabeledContent("Pairing code", value: profile.pairingCode)
                } else {
                    Text("Independent mode")
                }
            } header: {
                Text("Caretaker")
            }

            Section {
                if profile.medications.isEmpty {
                    Text("None")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(profile.medications) { medication in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(medication.name)
                            Text(medication.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Medications")
            }

            Section {
                let enabledMeals = profile.meals.filter { $0.enabled }
                if enabledMeals.isEmpty {
                    Text("None")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(enabledMeals) { meal in
                        LabeledContent(meal.name, value: TimeOfDay.display(meal.time))
                    }
                }
            } header: {
                Text("Meal reminders")
            }

            Section {
                Button("Change role", role: .destructive) {
                    confirmingReset = true
                }
            }
        }
        .navigationTitle("Patient")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                PatientSetupView(profile: profile, isEditing: true)
            }
            .environmentObject(store)
        }
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

    @State private var showingEdit = false
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: profile.name)
                LabeledContent("Email", value: profile.email)
            } header: {
                Text("You")
            }

            Section {
                LabeledContent("Pairing code", value: profile.patientPairingCode)
                LabeledContent("Status", value: "Not connected")
            } header: {
                Text("Patient")
            }

            Section {
                LabeledContent("Vibrate", value: profile.vibrateOnAlert ? "On" : "Off")
                LabeledContent("Notifications", value: profile.notifyOnAlert ? "On" : "Off")
            } header: {
                Text("Alerts")
            }

            Section {
                Button("Change role", role: .destructive) {
                    confirmingReset = true
                }
            }
        }
        .navigationTitle("Caretaker")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                CaretakerSetupView(profile: profile, isEditing: true)
            }
            .environmentObject(store)
        }
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
