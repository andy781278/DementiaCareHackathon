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
        if store.role == .patient {
            if let profile = store.patientProfile {
                PatientMainView(profile: profile)
            } else {
                NavigationStack {
                    PatientSetupFlow()
                }
            }
        } else if store.role == .caretaker {
            if let profile = store.caretakerProfile {
                CaretakerMainView(profile: profile)
            } else {
                NavigationStack {
                    CaretakerSetupFlow()
                }
            }
        } else {
            NavigationStack {
                RoleSelectionView()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore())
    }
}
