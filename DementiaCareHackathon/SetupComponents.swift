//
//  SetupComponents.swift
//  DementiaCareHackathon
//
//  Shared large-text building blocks for the one-field-per-screen setup.
//

import SwiftUI

/// One setup screen: step label, large title, subtitle, the input, and a large button at the bottom.
struct SetupStepLayout<Content: View>: View {
    let stepLabel: String?
    let title: String
    let subtitle: String?
    let buttonTitle: String
    let buttonEnabled: Bool
    let action: () -> Void
    let content: Content

    init(
        stepLabel: String? = nil,
        title: String,
        subtitle: String? = nil,
        buttonTitle: String,
        buttonEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.stepLabel = stepLabel
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.buttonEnabled = buttonEnabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let stepLabel = stepLabel {
                        Text(stepLabel)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    content
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: buttonTitle, enabled: buttonEnabled, action: action)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(enabled ? Color.accentColor : Color.gray.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(16)
        }
        .disabled(!enabled)
    }
}

struct BigTextField: View {
    let placeholder: String
    @Binding var text: String
    var multiline: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true

    var body: some View {
        Group {
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2...4)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(.title2)
        .keyboardType(keyboard)
        .textContentType(contentType)
        .textInputAutocapitalization(capitalization)
        .disableAutocorrection(!autocorrect)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

/// A large tappable card used for choosing between options or turning a setting on and off.
struct ChoiceCard: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.title)
                        .foregroundColor(.accentColor)
                        .frame(width: 40)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    if let detail = detail {
                        Text(detail)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A label above a value, in large text. Used in summaries and on the home screens.
struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rounded box listing several summary rows.
struct SummaryBox: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows.indices, id: \.self) { index in
                SummaryRow(label: rows[index].label, value: rows[index].value)
                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct BackToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .font(.title3)
        }
    }
}
