//
//  PatientSetupView.swift
//  DementiaCareHackathon
//

import SwiftUI
import CoreLocation

private enum GeocodeStatus {
    case idle
    case searching
    case found(String)
    case failed(String)
}

struct PatientSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PatientProfile
    @State private var geocodeStatus: GeocodeStatus
    @State private var editingMedication: Medication?

    let isEditing: Bool

    init(profile: PatientProfile, isEditing: Bool) {
        _draft = State(initialValue: profile)
        if profile.isHomeLocated {
            let shown = profile.resolvedHomeAddress.isEmpty ? profile.homeAddress : profile.resolvedHomeAddress
            _geocodeStatus = State(initialValue: .found(shown))
        } else {
            _geocodeStatus = State(initialValue: .idle)
        }
        self.isEditing = isEditing
    }

    var body: some View {
        Form {
            patientSection
            homeSection
            caretakerSection
            dementiaSection
            medicationSection
            mealSection

            if let message = validationMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.circle")
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Patient Setup" : "Patient Setup")
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
        .onChange(of: draft.homeAddress) { _ in
            // The typed address changed, so the old coordinates no longer match it.
            draft.homeLatitude = nil
            draft.homeLongitude = nil
            draft.resolvedHomeAddress = ""
            geocodeStatus = .idle
        }
        .sheet(item: $editingMedication) { medication in
            MedicationEditView(medication: medication) { saved in
                if let index = draft.medications.firstIndex(where: { $0.id == saved.id }) {
                    draft.medications[index] = saved
                } else {
                    draft.medications.append(saved)
                }
            }
        }
    }

    // MARK: - Sections

    private var patientSection: some View {
        Section {
            TextField("Full name", text: $draft.name)
                .textContentType(.name)
        } header: {
            Text("Patient")
        }
    }

    private var homeSection: some View {
        Section {
            TextField("Home address", text: $draft.homeAddress, axis: .vertical)
                .textContentType(.fullStreetAddress)

            Button {
                findAddress()
            } label: {
                HStack {
                    Text("Find address")
                    if isSearching {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(draft.homeAddress.trimmed.isEmpty || isSearching)

            switch geocodeStatus {
            case .idle, .searching:
                EmptyView()
            case .found(let address):
                Label(address, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Alert if farther than \(draft.safeRadiusMiles, specifier: "%.1f") miles from home")
                Slider(value: $draft.safeRadiusMiles, in: 0.1...5, step: 0.1)
            }
        } header: {
            Text("Home")
        } footer: {
            Text("Used to check whether the patient has gone too far from home.")
        }
    }

    private var caretakerSection: some View {
        Section {
            Toggle("Patient has a caretaker", isOn: $draft.hasCaretaker)

            if draft.hasCaretaker {
                TextField("Caretaker email", text: $draft.caretakerEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                HStack {
                    Text("Pairing code")
                    Spacer()
                    Text(draft.pairingCode)
                        .font(.title3.monospacedDigit())
                        .bold()
                }
            }
        } header: {
            Text("Caretaker")
        } footer: {
            if draft.hasCaretaker {
                Text("The caretaker enters this pairing code in their app to sync with this phone.")
            } else {
                Text("Independent mode: the app uses more audio cues, such as telling the patient to return to a familiar area when they go too far.")
            }
        }
    }

    private var dementiaSection: some View {
        Section {
            Picker("Level", selection: $draft.dementiaLevel) {
                ForEach(DementiaLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Dementia level")
        } footer: {
            Text(draft.dementiaLevel.reminderDescription)
        }
    }

    private var medicationSection: some View {
        Section {
            ForEach(draft.medications) { medication in
                Button {
                    editingMedication = medication
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.name)
                            .foregroundColor(.primary)
                        Text(medication.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                draft.medications.remove(atOffsets: offsets)
            }

            Button {
                editingMedication = Medication()
            } label: {
                Label("Add medication", systemImage: "plus")
            }
        } header: {
            Text("Medications (optional)")
        } footer: {
            Text("Tap a medication to edit it. Swipe left to delete.")
        }
    }

    private var mealSection: some View {
        Section {
            ForEach($draft.meals) { $meal in
                Toggle(meal.name, isOn: $meal.enabled)
                if meal.enabled {
                    DatePicker("\(meal.name) time", selection: $meal.time, displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text("Meal reminders")
        }
    }

    // MARK: - Logic

    private var isSearching: Bool {
        if case .searching = geocodeStatus {
            return true
        }
        return false
    }

    private var validationMessage: String? {
        if draft.name.trimmed.isEmpty {
            return "Enter the patient's name."
        }
        if !draft.isHomeLocated {
            return "Enter the home address and tap Find address."
        }
        if draft.hasCaretaker && !AppStore.isValidEmail(draft.caretakerEmail) {
            return "Enter a valid caretaker email."
        }
        return nil
    }

    private func findAddress() {
        let address = draft.homeAddress.trimmed
        guard !address.isEmpty else { return }
        geocodeStatus = .searching

        CLGeocoder().geocodeAddressString(address) { placemarks, _ in
            DispatchQueue.main.async {
                guard let placemark = placemarks?.first, let location = placemark.location else {
                    geocodeStatus = .failed("Address not found. Check the spelling and try again.")
                    return
                }
                let formatted = PatientSetupView.format(placemark)
                draft.homeLatitude = location.coordinate.latitude
                draft.homeLongitude = location.coordinate.longitude
                draft.resolvedHomeAddress = formatted
                geocodeStatus = .found(formatted)
            }
        }
    }

    private static func format(_ placemark: CLPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let parts: [String?] = [street, placemark.locality, placemark.administrativeArea, placemark.postalCode]
        return parts
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func save() {
        var profile = draft
        profile.name = profile.name.trimmed
        profile.caretakerEmail = profile.caretakerEmail.trimmed
        store.patientProfile = profile
        if isEditing {
            dismiss()
        }
    }
}

// MARK: - Medication editor

struct MedicationEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var medication: Medication
    private let onSave: (Medication) -> Void

    init(medication: Medication, onSave: @escaping (Medication) -> Void) {
        _medication = State(initialValue: medication)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $medication.name)
                    TextField("Dose (e.g. 1 pill, 5 mg)", text: $medication.dosage)
                } header: {
                    Text("Medication")
                }

                Section {
                    ForEach($medication.doseTimes) { $dose in
                        DatePicker("Time", selection: $dose.time, displayedComponents: .hourAndMinute)
                    }
                    .onDelete { offsets in
                        medication.doseTimes.remove(atOffsets: offsets)
                    }

                    Button {
                        medication.doseTimes.append(DoseTime(time: TimeOfDay.date(hour: 12)))
                    } label: {
                        Label("Add time", systemImage: "plus")
                    }
                } header: {
                    Text("Times per day: \(medication.doseTimes.count)")
                }

                Section {
                    DatePicker("Start", selection: $medication.startDate, displayedComponents: .date)
                    Toggle("Has end date", isOn: $medication.hasEndDate)
                    if medication.hasEndDate {
                        DatePicker("End", selection: $medication.endDate, in: medication.startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Dates")
                }
            }
            .navigationTitle(medication.name.trimmed.isEmpty ? "New Medication" : medication.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = medication
                        saved.name = saved.name.trimmed
                        saved.dosage = saved.dosage.trimmed
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        if medication.name.trimmed.isEmpty { return false }
        if medication.doseTimes.isEmpty { return false }
        if medication.hasEndDate && medication.endDate < medication.startDate { return false }
        return true
    }
}
