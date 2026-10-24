//
//  Audio.swift
//  DementiaCareHackathon
//
//  Spoken notification sounds and recorded voice messages.
//
//  iOS can play a custom sound file for a notification if the file is in the app's Library/Sounds
//  folder and is 30 seconds or shorter. Spoken text is turned into such a file with text-to-speech.
//  Recorded voice messages are stored in Firestore at patients/{pairingCode}/recordings/{id}
//  (id is an event id, or "wandering"), and the patient phone copies them into Library/Sounds.
//

import Foundation
import AVFoundation
import FirebaseFirestore

// MARK: - Sound file locations

enum SoundFiles {
    static var directory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let folder = library.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    /// The same text always gives the same file name, so a spoken file is only made once.
    static func ttsFileName(for text: String) -> String {
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return "tts-\(hash).caf"
    }

    /// The version changes on each new recording, so iOS does not play an older cached file with the same name.
    static func recordingFileName(id: String, version: String) -> String {
        "rec-\(id)-\(version).caf"
    }
}

// MARK: - Text-to-speech files

/// Turns text into a spoken audio file. Jobs run one at a time.
final class SpeechFileMaker {
    static let shared = SpeechFileMaker()

    private struct Job {
        let text: String
        let url: URL
        let completion: (Bool) -> Void
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [Job] = []
    private var currentJobID: UUID?

    /// Calls completion with true when the file exists at url. All calls and completions happen on the main thread.
    func make(text: String, url: URL, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            if FileManager.default.fileExists(atPath: url.path) {
                completion(true)
                return
            }
            self.queue.append(Job(text: text, url: url, completion: completion))
            self.startNext()
        }
    }

    private func startNext() {
        guard currentJobID == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        let jobID = UUID()
        currentJobID = jobID

        // Write to a temporary name first so a half-written file is never used as a sound.
        let tempURL = job.url.deletingLastPathComponent()
            .appendingPathComponent("writing-\(jobID.uuidString).caf")

        let utterance = AVSpeechUtterance(string: job.text)
        utterance.rate = 0.45
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        var file: AVAudioFile?
        var failed = false

        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

            if pcmBuffer.frameLength == 0 {
                // An empty buffer marks the end of the speech.
                let wroteAudio = file != nil
                file = nil
                DispatchQueue.main.async {
                    self?.finish(job: job, jobID: jobID, tempURL: tempURL, success: wroteAudio && !failed)
                }
                return
            }

            do {
                if file == nil {
                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: pcmBuffer.format.sampleRate,
                        AVNumberOfChannelsKey: pcmBuffer.format.channelCount,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false
                    ]
                    file = try AVAudioFile(
                        forWriting: tempURL,
                        settings: settings,
                        commonFormat: pcmBuffer.format.commonFormat,
                        interleaved: pcmBuffer.format.isInterleaved
                    )
                }
                try file?.write(from: pcmBuffer)
            } catch {
                print("Speech file error: \(error)")
                failed = true
            }
        }

        // If the synthesizer never signals the end, give up after 15 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.currentJobID == jobID else { return }
            self.synthesizer.stopSpeaking(at: .immediate)
            self.finish(job: job, jobID: jobID, tempURL: tempURL, success: false)
        }
    }

    private func finish(job: Job, jobID: UUID, tempURL: URL, success: Bool) {
        guard currentJobID == jobID else { return }
        currentJobID = nil

        let fileManager = FileManager.default
        var ok = false
        if success {
            try? fileManager.removeItem(at: job.url)
            ok = (try? fileManager.moveItem(at: tempURL, to: job.url)) != nil
        }
        if !ok {
            try? fileManager.removeItem(at: tempURL)
        }

        job.completion(ok)
        startNext()
    }
}

// MARK: - Recordings in Firestore

enum RecordingCloud {
    static let wanderingID = "wandering"

    static func collection(pairingCode: String) -> CollectionReference {
        PatientCloud.patients.document(pairingCode).collection("recordings")
    }

    static func upload(pairingCode: String, id: String, data: Data) {
        guard pairingCode.count == 6 else { return }
        collection(pairingCode: pairingCode).document(id).setData([
            "audio": data,
            "version": UUID().uuidString,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Recording upload error: \(error)")
            }
        }
    }

    static func delete(pairingCode: String, id: String) {
        guard pairingCode.count == 6 else { return }
        collection(pairingCode: pairingCode).document(id).delete { error in
            if let error = error {
                print("Recording delete error: \(error)")
            }
        }
    }
}

/// Patient phone: copies every recording for this patient into Library/Sounds so notifications can play it.
final class RecordingSync: ObservableObject {
    /// Recording id (event id or "wandering") to sound file name.
    @Published var recordingFiles: [String: String] = [:]

    private var listener: ListenerRegistration?
    private var pairingCode = ""

    func listen(pairingCode: String) {
        if listener != nil && pairingCode == self.pairingCode {
            return
        }
        listener?.remove()
        listener = nil
        self.pairingCode = pairingCode
        guard pairingCode.count == 6 else { return }

        listener = RecordingCloud.collection(pairingCode: pairingCode)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Recording sync error: \(error)")
                    return
                }
                guard let documents = snapshot?.documents else { return }

                var files: [String: String] = [:]
                for document in documents {
                    let fields = document.data()
                    guard let audio = fields["audio"] as? Data else { continue }
                    let version = fields["version"] as? String ?? "1"
                    let name = SoundFiles.recordingFileName(id: document.documentID, version: version)
                    if !SoundFiles.exists(name) {
                        try? audio.write(to: SoundFiles.url(name), options: .atomic)
                    }
                    files[document.documentID] = name
                }
                self.removeUnusedRecordingFiles(keeping: Set(files.values))
                self.recordingFiles = files
            }
    }

    private func removeUnusedRecordingFiles(keeping names: Set<String>) {
        let fileManager = FileManager.default
        let folder = SoundFiles.directory
        guard let contents = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return }
        for name in contents where name.hasPrefix("rec-") && !names.contains(name) {
            try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    deinit {
        listener?.remove()
    }
}

/// Watches one saved recording (for example the wandering message) so it can be played or deleted.
final class SavedRecordingStore: ObservableObject {
    @Published var savedData: Data?

    let recordingID: String
    private var listener: ListenerRegistration?
    private var pairingCode = ""

    init(recordingID: String) {
        self.recordingID = recordingID
    }

    func listen(pairingCode: String) {
        if listener != nil && pairingCode == self.pairingCode {
            return
        }
        listener?.remove()
        listener = nil
        self.pairingCode = pairingCode
        guard pairingCode.count == 6 else { return }

        listener = RecordingCloud.collection(pairingCode: pairingCode)
            .document(recordingID)
            .addSnapshotListener { [weak self] snapshot, _ in
                self?.savedData = snapshot?.data()?["audio"] as? Data
            }
    }

    func save(_ data: Data) {
        RecordingCloud.upload(pairingCode: pairingCode, id: recordingID, data: data)
    }

    func delete() {
        RecordingCloud.delete(pairingCode: pairingCode, id: recordingID)
    }

    deinit {
        listener?.remove()
    }
}

// MARK: - Recording and playback

final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    /// Notification sounds must be 30 seconds or shorter.
    static let maxSeconds: TimeInterval = 25

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var recordedData: Data?
    @Published var secondsRecorded = 0
    @Published var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("recording-\(UUID().uuidString).caf")

    func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.permissionDenied = false
                    self.beginRecording()
                } else {
                    self.permissionDenied = true
                }
            }
        }
    }

    private func beginRecording() {
        stopPlaying()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            // IMA4 in a .caf file is a format iOS can play as a notification sound.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatAppleIMA4,
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1
            ]
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: VoiceRecorder.maxSeconds)
            self.recorder = recorder

            isRecording = true
            secondsRecorded = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.secondsRecorded += 1
            }
        } catch {
            print("Recording error: \(error)")
        }
    }

    func stopRecording() {
        recorder?.stop()
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
            self.isRecording = false
            if flag, let data = try? Data(contentsOf: self.fileURL), !data.isEmpty {
                self.recordedData = data
            }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func play(_ data: Data) {
        stopPlaying()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.play()
            self.player = player
            isPlaying = true
        } catch {
            print("Playback error: \(error)")
        }
    }

    func stopPlaying() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    func clear() {
        stopPlaying()
        recordedData = nil
        secondsRecorded = 0
    }
}
