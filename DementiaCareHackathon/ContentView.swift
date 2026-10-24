//
//  ContentView.swift
//  DementiaCareHackathon
//
//  Created by Andy Zhu on 10/24/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if store.role == .patient {
            if let profile = store.patientProfile {
                PatientHomeView(profile: profile)
            } else {
                PatientSetupView(profile: PatientProfile(), isEditing: false)
            }
        } else if store.role == .caretaker {
            if let profile = store.caretakerProfile {
                CaretakerHomeView(profile: profile)
            } else {
                CaretakerSetupView(profile: CaretakerProfile(), isEditing: false)
            }
        } else {
            RoleSelectionView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore())
    }
}
