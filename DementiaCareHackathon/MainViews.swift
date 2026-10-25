//
//  MainViews.swift
//  DementiaCareHackathon
//
//  The main screens after setup: a bottom tab bar with Map, Schedule, Details, and Settings.
//

import SwiftUI
import CoreLocation

extension PatientProfile {
    var homeCoordinate: CLLocationCoordinate2D? {
        guard let latitude = homeLatitude, let longitude = homeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Patient

struct PatientMainView: View {
    let profile: PatientProfile

    @StateObject private var tracker = LocationTracker()
    @StateObject private var schedule = ScheduleStore()
    @StateObject private var recordings = RecordingSync()
    @StateObject private var battery = BatteryMonitor()

    var body: some View {
        TabView {
            MapScreen(
                home: profile.homeCoordinate,
                radiusMiles: profile.safeRadiusMiles,
                patient: tracker.location?.coordinate,
                isOutside: tracker.isOutside,
                distanceMeters: tracker.distanceFromHome,
                lastUpdate: tracker.location?.timestamp,
                waitingMessage: tracker.permissionMessage,
                batteryPercent: battery.percent,
                batteryCharging: battery.isCharging,
                lowBatteryThreshold: profile.batteryThreshold
            )
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }

            NavigationStack {
                ScheduleView(schedule: schedule, createdBy: "patient", isAvailable: true)
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }

            NavigationStack {
                PatientDetailsView(profile: profile, tracker: tracker, battery: battery)
            }
            .tabItem {
                Label("Details", systemImage: "person.text.rectangle")
            }

            NavigationStack {
                PatientSettingsView(profile: profile)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .onAppear {
            tracker.start(profile: profile)
            battery.start(profile: profile)
            schedule.listen(pairingCode: profile.pairingCode)
            recordings.listen(pairingCode: profile.pairingCode)
        }
        .onChange(of: profile) { newProfile in
            tracker.update(profile: newProfile)
            battery.update(profile: newProfile)
            schedule.listen(pairingCode: newProfile.pairingCode)
            recordings.listen(pairingCode: newProfile.pairingCode)
            ReminderScheduler.reschedule(
                events: schedule.events,
                level: newProfile.dementiaLevel,
                recordingFiles: recordings.recordingFiles
            )
        }
        // @Published sends the new value before the property changes, so use the value passed in.
        .onReceive(schedule.$events) { events in
            ReminderScheduler.reschedule(
                events: events,
                level: profile.dementiaLevel,
                recordingFiles: recordings.recordingFiles
            )
        }
        .onReceive(recordings.$recordingFiles) { files in
            tracker.wanderingSoundFile = files[RecordingCloud.wanderingID]
            battery.lowBatterySoundFile = files[RecordingCloud.lowBatteryID]
            ReminderScheduler.reschedule(
                events: schedule.events,
                level: profile.dementiaLevel,
                recordingFiles: files
            )
        }
    }
}

struct PatientDetailsView: View {
    let profile: PatientProfile
    @ObservedObject var tracker: LocationTracker
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        List {
            Section {
                if tracker.location == nil {
                    Label("Location not available yet", systemImage: "location.slash")
                        .font(.title3.bold())
                } else {
                    Label(
                        tracker.isOutside ? "Outside the safe zone" : "Inside the safe zone",
                        systemImage: tracker.isOutside ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                    )
                    .font(.title3.bold())
                    .foregroundColor(tracker.isOutside ? .red : .green)

                    if let distance = tracker.distanceFromHome {
                        SummaryRow(label: "Distance from home", value: Distance.milesText(meters: distance))
                    }
                }

                if let message = tracker.permissionMessage {
                    Text(message)
                        .font(.body)
                        .foregroundColor(.orange)
                    if tracker.authorization != .notDetermined {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.title3)
                    }
                }
            } header: {
                Text("Status")
                    .font(.headline)
            }

            Section {
                if let percent = battery.percent {
                    Label(
                        Battery.text(percent: percent, charging: battery.isCharging),
                        systemImage: Battery.iconName(percent: percent, charging: battery.isCharging)
                    )
                    .font(.title3.bold())
                    .foregroundColor(percent <= profile.batteryThreshold && !battery.isCharging ? .red : .primary)
                } else {
                    Text("Battery level unknown")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                SummaryRow(label: "Alert at", value: "\(profile.batteryThreshold)%")

                if let testPercent = battery.testPercent {
                    Text("Test level \(testPercent)% set from the caretaker's phone.")
                        .font(.body)
                        .foregroundColor(.orange)
                }
            } header: {
                Text("Battery")
                    .font(.headline)
            }

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
                SummaryRow(label: "Name", value: profile.name)
                SummaryRow(label: "Home address", value: profile.displayHomeAddress)
                SummaryRow(label: "Alert distance", value: String(format: "%.1f miles", profile.safeRadiusMiles))
                SummaryRow(
                    label: "Caretaker",
                    value: profile.hasCaretaker ? profile.caretakerEmail : "None (independent mode)"
                )
                SummaryRow(label: "Dementia level", value: profile.dementiaLevel.title)
            } header: {
                Text("Patient")
                    .font(.headline)
            }
        }
        .navigationTitle(profile.name)
    }
}

// MARK: - Caretaker

struct CaretakerMainView: View {
    let profile: CaretakerProfile

    @StateObject private var connection = CaretakerConnection()
    @StateObject private var schedule = ScheduleStore()

    var body: some View {
        TabView {
            mapTab
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }

            NavigationStack {
                ScheduleView(
                    schedule: schedule,
                    createdBy: "caretaker",
                    isAvailable: connection.state == .connected
                )
            }
            .tabItem {
                Label("Schedule", systemImage: "calendar")
            }

            NavigationStack {
                CaretakerDetailsView(connection: connection, batteryThreshold: profile.batteryThreshold)
            }
            .tabItem {
                Label("Details", systemImage: "person.text.rectangle")
            }

            NavigationStack {
                CaretakerSettingsView(profile: profile)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .onAppear {
            connection.connect(profile: profile)
        }
        .onChange(of: profile) { newProfile in
            connection.connect(profile: newProfile)
        }
        .onChange(of: connection.state) { state in
            if state == .connected {
                schedule.listen(pairingCode: profile.patientPairingCode)
            } else {
                schedule.stop()
            }
        }
    }

    @ViewBuilder
    private var mapTab: some View {
        if connection.state == .connected, let patient = connection.patient {
            MapScreen(
                home: patient.homeCoordinate,
                radiusMiles: patient.safeRadiusMiles,
                patient: patient.lastCoordinate,
                isOutside: patient.isOutsideZone,
                distanceMeters: patient.distanceFromHomeMeters,
                lastUpdate: patient.lastLocationAt,
                waitingMessage: "Waiting for \(patient.displayName)'s phone to share its location.",
                batteryPercent: patient.batteryPercent,
                batteryCharging: patient.batteryCharging,
                lowBatteryThreshold: profile.batteryThreshold
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "map")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                Text("Connect to a patient to see their location.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Text("Check the Details tab for the connection status.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

struct CaretakerDetailsView: View {
    @ObservedObject var connection: CaretakerConnection
    let batteryThreshold: Int

    var body: some View {
        List {
            Section {
                connectionStatus
            } header: {
                Text("Connection")
                    .font(.headline)
            }

            if connection.state == .connected, let patient = connection.patient {
                Section {
                    if patient.lastCoordinate == nil {
                        Label("Location not shared yet", systemImage: "location.slash")
                            .font(.title3.bold())
                    } else {
                        Label(
                            patient.isOutsideZone ? "Outside the safe zone" : "Inside the safe zone",
                            systemImage: patient.isOutsideZone ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
                        )
                        .font(.title3.bold())
                        .foregroundColor(patient.isOutsideZone ? .red : .green)

                        if let distance = patient.distanceFromHomeMeters {
                            SummaryRow(label: "Distance from home", value: Distance.milesText(meters: distance))
                        }
                        if let lastLocationAt = patient.lastLocationAt {
                            SummaryRow(
                                label: "Last location update",
                                value: lastLocationAt.formatted(date: .abbreviated, time: .shortened)
                            )
                        }
                    }

                    if let percent = patient.batteryPercent {
                        Label(
                            "Battery \(Battery.text(percent: percent, charging: patient.batteryCharging))",
                            systemImage: Battery.iconName(percent: percent, charging: patient.batteryCharging)
                        )
                        .font(.title3.bold())
                        .foregroundColor(percent <= batteryThreshold && !patient.batteryCharging ? .red : .primary)
                    } else {
                        Text("Battery level not shared yet")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Status")
                        .font(.headline)
                }

                Section {
                    BatteryTestControls(connection: connection, activeTestPercent: patient.testBatteryPercent)
                } header: {
                    Text("Test battery level")
                        .font(.headline)
                } footer: {
                    Text("For demos and the simulator: the patient's phone uses this level instead of its real battery.")
                        .font(.body)
                }

                Section {
                    SummaryRow(label: "Name", value: patient.name)
                    SummaryRow(label: "Home address", value: patient.homeAddress)
                    SummaryRow(label: "Alert distance", value: String(format: "%.1f miles", patient.safeRadiusMiles))
                    SummaryRow(label: "Dementia level", value: patient.dementiaLevel?.title ?? "Unknown")
                } header: {
                    Text("Patient")
                        .font(.headline)
                }
            }
        }
        .navigationTitle(connection.patient?.displayName ?? "Patient")
    }

    @ViewBuilder
    private var connectionStatus: some View {
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

        case .notFound:
            Label(
                "No patient found with this code. Check the code shown on the patient's phone, then change it in Settings.",
                systemImage: "xmark.circle.fill"
            )
            .font(.title3)
            .foregroundColor(.red)

        case .emailMismatch:
            Label(
                "This patient listed a different caretaker email. Your email in Settings must match the one entered on the patient's phone.",
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

/// Caretaker controls that set a test battery level on the patient's phone.
struct BatteryTestControls: View {
    @ObservedObject var connection: CaretakerConnection
    let activeTestPercent: Int?

    @State private var value: Double = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(Int(value))%")
                .font(.title2.bold())
            Slider(value: $value, in: 0...100, step: 1, onEditingChanged: { editing in
                // Send the level when the finger is lifted, not on every small move.
                if !editing {
                    connection.setTestBattery(Int(value))
                }
            })
            if let active = activeTestPercent {
                Text("Test level \(active)% is active on the patient's phone.")
                    .font(.body)
                    .foregroundColor(.orange)
                Button("Use the real battery again") {
                    connection.setTestBattery(nil)
                }
                .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }
}
