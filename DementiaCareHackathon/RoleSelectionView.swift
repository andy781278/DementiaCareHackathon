//
//  RoleSelectionView.swift
//  DementiaCareHackathon
//

import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.text.square")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Who uses this phone?")
                .font(.title2)
                .bold()

            VStack(spacing: 16) {
                roleButton(
                    title: "Patient",
                    subtitle: "The person who receives reminders",
                    systemImage: "person.fill",
                    role: .patient
                )
                roleButton(
                    title: "Caretaker",
                    subtitle: "The person who looks after the patient",
                    systemImage: "person.2.fill",
                    role: .caretaker
                )
            }

            Spacer()
            Spacer()
        }
        .padding()
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roleButton(title: String, subtitle: String, systemImage: String, role: UserRole) -> some View {
        Button {
            store.role = role
        } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundColor(.accentColor)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
