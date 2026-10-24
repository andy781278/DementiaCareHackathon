//
//  VoiceViews.swift
//  DementiaCareHackathon
//
//  Large buttons for recording, playing, and deleting voice messages.
//

import SwiftUI

struct AudioActionButton: View {
    let title: String
    let systemImage: String
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}

/// Record, play back, re-record, or delete a voice message.
/// savedData is an already saved message, shown when nothing new has been recorded.
struct VoiceMessageControls: View {
    @ObservedObject var recorder: VoiceRecorder
    var savedData: Data? = nil
    var onDeleteSaved: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recorder.isRecording {
                AudioActionButton(
                    title: "Stop recording (\(recorder.secondsRecorded)s of \(Int(VoiceRecorder.maxSeconds))s)",
                    systemImage: "stop.circle.fill",
                    color: .red
                ) {
                    recorder.stopRecording()
                }
            } else if let recorded = recorder.recordedData {
                Label("New message recorded", systemImage: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
                playButton(for: recorded)
                AudioActionButton(title: "Record again", systemImage: "mic.fill") {
                    recorder.startRecording()
                }
                AudioActionButton(title: "Remove new recording", systemImage: "trash", color: .red) {
                    recorder.clear()
                }
            } else if let saved = savedData {
                playButton(for: saved)
                AudioActionButton(title: "Record a new message", systemImage: "mic.fill") {
                    recorder.startRecording()
                }
                if let onDeleteSaved = onDeleteSaved {
                    AudioActionButton(title: "Delete saved message", systemImage: "trash", color: .red) {
                        recorder.stopPlaying()
                        onDeleteSaved()
                    }
                }
            } else {
                AudioActionButton(title: "Record message", systemImage: "mic.fill") {
                    recorder.startRecording()
                }
            }

            if recorder.permissionDenied {
                Text("Microphone access is off. Turn it on in Settings to record a message.")
                    .font(.body)
                    .foregroundColor(.orange)
            }
        }
    }

    private func playButton(for data: Data) -> some View {
        AudioActionButton(
            title: recorder.isPlaying ? "Stop playing" : "Play message",
            systemImage: recorder.isPlaying ? "stop.fill" : "play.fill"
        ) {
            if recorder.isPlaying {
                recorder.stopPlaying()
            } else {
                recorder.play(data)
            }
        }
    }
}

/// Record a message the patient hears for one kind of alert (wandering or low battery).
/// Either phone can record it; it is stored on the server and the patient phone downloads it.
struct VoiceMessageSettingView: View {
    let pairingCode: String
    let recordingID: String
    let title: String
    let explanation: String
    let defaultMessage: String

    @StateObject private var saved: SavedRecordingStore
    @StateObject private var recorder = VoiceRecorder()

    init(pairingCode: String, recordingID: String, title: String, explanation: String, defaultMessage: String) {
        self.pairingCode = pairingCode
        self.recordingID = recordingID
        self.title = title
        self.explanation = explanation
        self.defaultMessage = defaultMessage
        _saved = StateObject(wrappedValue: SavedRecordingStore(recordingID: recordingID))
    }

    var body: some View {
        SetupStepLayout(
            title: title,
            subtitle: "\(explanation) Without a recording, the phone says: \"\(defaultMessage)\"",
            buttonTitle: "Save recording",
            buttonEnabled: recorder.recordedData != nil && !recorder.isRecording,
            action: save
        ) {
            VStack(alignment: .leading, spacing: 20) {
                if recorder.recordedData == nil && !recorder.isRecording {
                    if saved.savedData != nil {
                        Label("A custom message is saved.", systemImage: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                    } else {
                        Text("No custom message yet. The default message is spoken.")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }

                VoiceMessageControls(
                    recorder: recorder,
                    savedData: saved.savedData,
                    onDeleteSaved: { saved.delete() }
                )

                if let errorMessage = saved.errorMessage {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .font(.body)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            saved.load(pairingCode: pairingCode)
        }
        .onDisappear {
            recorder.stopPlaying()
        }
    }

    private func save() {
        guard let data = recorder.recordedData else { return }
        saved.save(data)
        recorder.clear()
    }
}

/// Settings rows that open the voice message screens.
struct VoiceMessageLinks: View {
    let pairingCode: String

    var body: some View {
        NavigationLink(destination: VoiceMessageSettingView(
            pairingCode: pairingCode,
            recordingID: RecordingCloud.wanderingID,
            title: "Wandering message",
            explanation: "Plays on the patient's phone when they leave the safe zone.",
            defaultMessage: LocationTracker.wanderingMessage
        )) {
            SummaryRow(
                label: "Wandering voice message",
                value: "What the patient hears when they leave the safe zone"
            )
        }

        NavigationLink(destination: VoiceMessageSettingView(
            pairingCode: pairingCode,
            recordingID: RecordingCloud.lowBatteryID,
            title: "Low battery message",
            explanation: "Plays on the patient's phone when the battery is low.",
            defaultMessage: BatteryMonitor.defaultMessage
        )) {
            SummaryRow(
                label: "Low battery voice message",
                value: "What the patient hears when the battery is low"
            )
        }
    }
}
