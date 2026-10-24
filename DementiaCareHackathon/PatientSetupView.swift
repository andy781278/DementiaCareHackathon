//
//  PatientSetupView.swift
//  DementiaCareHackathon
//
//  Patient setup, one field per screen. The pairing code is shown on the final screen.
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Steps

enum PatientStep: Hashable, CaseIterable {
    case name
    case homeAddress
    case distance
    case hasCaretaker
    case caretakerEmail
    case dementiaLevel
    case lowBattery

    /// Steps used in the setup flow. The email step is skipped in independent mode.
    /// The battery alert level is only changed in Settings (default 10%).
    static func steps(for profile: PatientProfile) -> [PatientStep] {
        allCases.filter { step in
            if step == .lowBattery { return false }
            if step == .caretakerEmail { return profile.hasCaretaker }
            return true
        }
    }

    /// Rows shown in Settings. The email is edited together with the caretaker choice.
    static let homeRows: [PatientStep] = [.name, .homeAddress, .distance, .hasCaretaker, .dementiaLevel, .lowBattery]

    var title: String {
        switch self {
        case .name: return "Patient name"
        case .homeAddress: return "Home address"
        case .distance: return "How far is too far?"
        case .hasCaretaker: return "Is there a caretaker?"
        case .caretakerEmail: return "Caretaker's email"
        case .dementiaLevel: return "Dementia level"
        case .lowBattery: return "Low battery alert"
        }
    }

    var subtitle: String? {
        switch self {
        case .name: return nil
        case .homeAddress: return "Used to tell when the patient has gone too far from home."
        case .distance: return "An alert is sent when the patient goes farther than this from home."
        case .hasCaretaker: return nil
        case .caretakerEmail: return "Used to connect this phone with the caretaker's app."
        case .dementiaLevel: return "Sets how often reminders repeat."
        case .lowBattery: return "The patient is told to charge the phone when the battery drops to this level."
        }
    }

    var rowLabel: String {
        switch self {
        case .name: return "Name"
        case .homeAddress: return "Home address"
        case .distance: return "Alert distance"
        case .hasCaretaker: return "Caretaker"
        case .caretakerEmail: return "Caretaker email"
        case .dementiaLevel: return "Dementia level"
        case .lowBattery: return "Low battery alert"
        }
    }

    func value(for profile: PatientProfile) -> String {
        switch self {
        case .name: return profile.name
        case .homeAddress: return profile.displayHomeAddress
        case .distance: return String(format: "%.1f miles", profile.safeRadiusMiles)
        case .hasCaretaker: return profile.hasCaretaker ? profile.caretakerEmail : "None (independent mode)"
        case .caretakerEmail: return profile.caretakerEmail
        case .dementiaLevel: return profile.dementiaLevel.title
        case .lowBattery: return "At \(profile.batteryThreshold)%"
        }
    }

    func isComplete(_ profile: PatientProfile) -> Bool {
        switch self {
        case .name: return !profile.name.trimmed.isEmpty
        case .homeAddress: return profile.isHomeLocated
        case .distance: return true
        case .hasCaretaker: return true
        case .caretakerEmail: return AppStore.isValidEmail(profile.caretakerEmail)
        case .dementiaLevel: return true
        case .lowBattery: return true
        }
    }
}

// MARK: - Step content

/// The input for one patient step. Used by both the setup flow and the edit screens.
struct PatientStepContent: View {
    let step: PatientStep
    @Binding var profile: PatientProfile

    var body: some View {
        switch step {
        case .name:
            BigTextField(
                placeholder: "Full name",
                text: $profile.name,
                contentType: .name,
                capitalization: .words
            )

        case .homeAddress:
            HomeAddressInput(profile: $profile)

        case .distance:
            DistanceInput(miles: $profile.safeRadiusMiles)

        case .hasCaretaker:
            VStack(spacing: 16) {
                ChoiceCard(
                    title: "Yes",
                    detail: "A caretaker receives updates and alerts on their phone.",
                    systemImage: "person.2.fill",
                    isSelected: profile.hasCaretaker
                ) {
                    profile.hasCaretaker = true
                }
                ChoiceCard(
                    title: "No",
                    detail: "Independent mode. The app gives more spoken guidance, such as telling the patient to return to a familiar area.",
                    systemImage: "person.fill",
                    isSelected: !profile.hasCaretaker
                ) {
                    profile.hasCaretaker = false
                }
            }

        case .caretakerEmail:
            BigTextField(
                placeholder: "caretaker@email.com",
                text: $profile.caretakerEmail,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                capitalization: .never,
                autocorrect: false
            )

        case .dementiaLevel:
            VStack(spacing: 16) {
                ForEach(DementiaLevel.allCases) { level in
                    ChoiceCard(
                        title: level.title,
                        detail: level.reminderDescription,
                        isSelected: profile.dementiaLevel == level
                    ) {
                        profile.dementiaLevel = level
                    }
                }
            }

        case .lowBattery:
            BatteryThresholdInput(percent: Binding(
                get: { profile.batteryThreshold },
                set: { profile.lowBatteryPercent = $0 }
            ))
        }
    }
}

struct HomeAddressInput: View {
    @Binding var profile: PatientProfile

    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BigTextField(
                placeholder: "Street, city, state",
                text: $profile.homeAddress,
                multiline: true,
                contentType: .fullStreetAddress
            )

            Button {
                findAddress()
            } label: {
                HStack(spacing: 8) {
                    if isSearching {
                        ProgressView()
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text("Find address")
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(14)
            }
            .disabled(profile.homeAddress.trimmed.isEmpty || isSearching)

            if profile.isHomeLocated {
                Label(
                    profile.resolvedHomeAddress.isEmpty ? "Address found" : profile.resolvedHomeAddress,
                    systemImage: "checkmark.circle.fill"
                )
                .font(.title3)
                .foregroundColor(.green)
            } else if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
            }
        }
        .onChange(of: profile.homeAddress) { _ in
            // The typed address changed, so the old coordinates no longer match it.
            profile.homeLatitude = nil
            profile.homeLongitude = nil
            profile.resolvedHomeAddress = ""
            errorMessage = nil
        }
    }

    private func findAddress() {
        let address = profile.homeAddress.trimmed
        guard !address.isEmpty else { return }
        isSearching = true
        errorMessage = nil

        // First try Apple's geocoder. If it finds nothing, try a MapKit search, which matches more loosely.
        CLGeocoder().geocodeAddressString(address) { placemarks, geocoderError in
            if let placemark = placemarks?.first, let location = placemark.location {
                DispatchQueue.main.async {
                    apply(placemark: placemark, location: location)
                }
                return
            }
            if let geocoderError = geocoderError {
                print("CLGeocoder error: \(geocoderError)")
            }
            DispatchQueue.main.async {
                searchWithMapKit(address, previousError: geocoderError)
            }
        }
    }

    private func searchWithMapKit(_ address: String, previousError: Error?) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        request.resultTypes = [.address, .pointOfInterest]

        MKLocalSearch(request: request).start { response, searchError in
            DispatchQueue.main.async {
                if let item = response?.mapItems.first, let location = item.placemark.location {
                    apply(placemark: item.placemark, location: location)
                    return
                }
                if let searchError = searchError {
                    print("MKLocalSearch error: \(searchError)")
                }
                isSearching = false
                errorMessage = HomeAddressInput.describe(searchError ?? previousError)
            }
        }
    }

    private func apply(placemark: CLPlacemark, location: CLLocation) {
        isSearching = false
        errorMessage = nil
        profile.homeLatitude = location.coordinate.latitude
        profile.homeLongitude = location.coordinate.longitude
        profile.resolvedHomeAddress = HomeAddressInput.format(placemark)
    }

    private static func describe(_ error: Error?) -> String {
        guard let error = error else {
            return "Address not found. Check the spelling and try again."
        }
        if let clError = error as? CLError {
            switch clError.code {
            case .network:
                return "Could not reach Apple's address service. Check that this phone or simulator is online."
            case .geocodeFoundNoResult, .geocodeFoundPartialResult:
                return "Address not found. Check the spelling and try again."
            default:
                break
            }
        }
        if let mkError = error as? MKError {
            switch mkError.code {
            case .serverFailure:
                return "Could not reach Apple's address service. Check that this phone or simulator is online."
            case .placemarkNotFound:
                return "Address not found. Check the spelling and try again."
            default:
                break
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "Could not reach Apple's address service. Check that this phone or simulator is online."
        }
        return "Address lookup failed: \(error.localizedDescription) (\(nsError.domain) \(nsError.code))"
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
}

struct DistanceInput: View {
    @Binding var miles: Double

    private let range: ClosedRange<Double> = 0.1...5

    var body: some View {
        VStack(spacing: 32) {
            Text(String(format: "%.1f miles", miles))
                .font(.system(size: 56, weight: .bold))
                .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                stepButton(systemImage: "minus") {
                    change(by: -0.1)
                }
                Slider(value: $miles, in: range, step: 0.1)
                stepButton(systemImage: "plus") {
                    change(by: 0.1)
                }
            }
        }
    }

    private func change(by amount: Double) {
        let rounded = ((miles + amount) * 10).rounded() / 10
        miles = min(max(rounded, range.lowerBound), range.upperBound)
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title.bold())
                .frame(width: 56, height: 56)
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
        }
    }
}

// MARK: - Setup flow

struct PatientSetupFlow: View {
    @EnvironmentObject private var store: AppStore

    @State private var profile = PatientProfile()
    @State private var index = 0

    private var steps: [PatientStep] {
        PatientStep.steps(for: profile)
    }

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
                    PatientStepContent(step: step, profile: $profile)
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
            subtitle: profile.hasCaretaker
                ? "Give this pairing code to the caretaker. They enter it in their app to connect."
                : "Independent mode is on. The app will give spoken guidance.",
            buttonTitle: "Done",
            action: finish
        ) {
            VStack(alignment: .leading, spacing: 24) {
                if profile.hasCaretaker {
                    Text(profile.formattedPairingCode)
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(20)
                }

                SummaryBox(rows: steps.map { (label: $0.rowLabel, value: $0.value(for: profile)) })
            }
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
        saved.caretakerEmail = saved.caretakerEmail.trimmed
        store.patientProfile = saved
    }
}

// MARK: - Editing one field later

struct PatientFieldEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let step: PatientStep
    @State private var profile: PatientProfile

    init(step: PatientStep, profile: PatientProfile) {
        self.step = step
        _profile = State(initialValue: profile)
    }

    var body: some View {
        SetupStepLayout(
            title: step.title,
            subtitle: step.subtitle,
            buttonTitle: "Save",
            buttonEnabled: isValid,
            action: save
        ) {
            VStack(alignment: .leading, spacing: 24) {
                PatientStepContent(step: step, profile: $profile)

                if step == .hasCaretaker && profile.hasCaretaker {
                    Text("Caretaker's email")
                        .font(.title2.bold())
                    PatientStepContent(step: .caretakerEmail, profile: $profile)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isValid: Bool {
        PatientStep.steps(for: profile).allSatisfy { $0.isComplete(profile) }
    }

    private func save() {
        var saved = profile
        saved.name = saved.name.trimmed
        saved.caretakerEmail = saved.caretakerEmail.trimmed
        store.patientProfile = saved
        dismiss()
    }
}
