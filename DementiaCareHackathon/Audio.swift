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
        // "v2" so files made by the earlier speech code are not reused.
        return "tts-v2-\(hash).caf"
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

    /// Shared between the synthesizer's callback thread and the main thread.
    private final class WriteState {
        let lock = NSLock()
        var file: AVAudioFile?
        var frames: AVAudioFrameCount = 0
        var lastBufferAt: Date?
        var failed = false
        var ended = false
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [Job] = []
    private var currentJobID: UUID?

    /// Seconds without new audio after which the speech is treated as finished.
    private let idleSeconds: TimeInterval = 1.0

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

        let state = WriteState()

        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
            state.lock.lock()
            defer { state.lock.unlock() }
            if state.ended { return }

            // Some iOS versions send an empty buffer at the end of the speech.
            if pcmBuffer.frameLength == 0 {
                state.ended = true
                state.file = nil
                let success = state.frames > 0 && !state.failed
                DispatchQueue.main.async {
                    self?.finish(job: job, jobID: jobID, tempURL: tempURL, success: success)
                }
                return
            }

            do {
                if state.file == nil {
                    let settings: [String: Any] = [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: pcmBuffer.format.sampleRate,
                        AVNumberOfChannelsKey: pcmBuffer.format.channelCount,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false
                    ]
                    state.file = try AVAudioFile(
                        forWriting: tempURL,
                        settings: settings,
                        commonFormat: pcmBuffer.format.commonFormat,
                        interleaved: pcmBuffer.format.isInterleaved
                    )
                }
                try state.file?.write(from: pcmBuffer)
                state.frames += pcmBuffer.frameLength
                state.lastBufferAt = Date()
            } catch {
                print("Speech file write error: \(error)")
                state.failed = true
            }
        }

        // Other iOS versions never send the empty buffer, so also finish once no audio has arrived for a moment.
        checkIdle(job: job, jobID: jobID, tempURL: tempURL, state: state, startedAt: Date())
    }

    private func checkIdle(job: Job, jobID: UUID, tempURL: URL, state: WriteState, startedAt: Date) {
        guard currentJobID == jobID else { return }

        state.lock.lock()
        let now = Date()
        let idle = state.lastBufferAt.map { now.timeIntervalSince($0) > idleSeconds } ?? false
        let elapsed = now.timeIntervalSince(startedAt)
        // Give up if no audio arrived within 3 seconds, or the whole job takes over 10 seconds.
        let timedOut = (state.lastBufferAt == nil && elapsed > 3) || elapsed > 10
        let done = idle || timedOut || state.ended
        if done {
            state.ended = true
            state.file = nil
        }
        let success = state.frames > 0 && !state.failed
        state.lock.unlock()

        if done {
            if timedOut && !idle {
                synthesizer.stopSpeaking(at: .immediate)
            }
            finish(job: job, jobID: jobID, tempURL: tempURL, success: success)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.checkIdle(job: job, jobID: jobID, tempURL: tempURL, state: state, startedAt: startedAt)
            }
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
        print(ok ? "Spoken sound ready: \(job.url.lastPathComponent)" : "Spoken sound failed for: \(job.text)")

        job.completion(ok)
        startNext()
    }
}

/// Plays a notification's audio directly while the app is open: the sound file if there is one,
/// otherwise the text read aloud. This does not depend on iOS playing custom notification sounds.
final class ForegroundSpeaker: NSObject, AVAudioPlayerDelegate {
    static let shared = ForegroundSpeaker()
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    func play(soundFile: String?, spokenText: String?) {
        DispatchQueue.main.async {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)

            if let soundFile = soundFile, SoundFiles.exists(soundFile),
               let player = try? AVAudioPlayer(contentsOf: SoundFiles.url(soundFile)) {
                self.synthesizer.stopSpeaking(at: .immediate)
                self.player?.stop()
                player.delegate = self
                player.play()
                self.player = player
                return
            }

            if let spokenText = spokenText {
                let utterance = AVSpeechUtterance(string: spokenText)
                utterance.rate = 0.45
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                self.synthesizer.speak(utterance)
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.player = nil
        }
    }
}

// MARK: - Recordings in Firestore

enum RecordingCloud {
    static let wanderingID = "wandering"
    static let lowBatteryID = "lowBattery"

    static func collectionPath(pairingCode: String) -> String {
        "\(PatientCloud.path(pairingCode: pairingCode))/recordings"
    }

    static func upload(pairingCode: String, id: String, data: Data, completion: ((Error?) -> Void)? = nil) {
        guard pairingCode.count == 6 else { return }
        FirestoreREST.patch(
            "\(collectionPath(pairingCode: pairingCode))/\(id)",
            fields: [
                "audio": FirestoreREST.bytes(data),
                "version": FirestoreREST.string(UUID().uuidString),
                "updatedAt": FirestoreREST.timestamp(Date())
            ],
            completion: completion
        )
    }

    static func delete(pairingCode: String, id: String, completion: ((Error?) -> Void)? = nil) {
        guard pairingCode.count == 6 else { return }
        FirestoreREST.delete("\(collectionPath(pairingCode: pairingCode))/\(id)", completion: completion)
    }
}

/// Patient phone: copies every recording for this patient into Library/Sounds so notifications can play it.
/// Checks every few seconds which recordings exist and downloads only new versions.
final class RecordingSync: ObservableObject {
    static let pollSeconds: TimeInterval = 8

    /// Recording id (event id or "wandering") to sound file name.
    @Published var recordingFiles: [String: String] = [:]

    private let poller = Poller()
    private var pairingCode = ""
    private var isFetching = false

    func listen(pairingCode: String) {
        if pairingCode == self.pairingCode && !self.pairingCode.isEmpty {
            return
        }
        poller.stop()
        isFetching = false
        self.pairingCode = ""
        guard pairingCode.count == 6 else { return }
        self.pairingCode = pairingCode

        poller.start(every: RecordingSync.pollSeconds) { [weak self] in
            self?.fetch()
        }
    }

    private func fetch() {
        guard !isFetching, pairingCode.count == 6 else { return }
        isFetching = true
        let code = pairingCode

        // List only the version of each recording, not the audio.
        FirestoreREST.list(RecordingCloud.collectionPath(pairingCode: code), onlyFields: ["version"]) { [weak self] result in
            guard let self = self else { return }
            guard code == self.pairingCode, case .success(let documents) = result else {
                self.isFetching = false
                return
            }

            var wanted: [String: String] = [:]
            for document in documents {
                let version = document.fields["version"] as? String ?? "1"
                wanted[document.id] = SoundFiles.recordingFileName(id: document.id, version: version)
            }
            let missing = wanted.filter { !SoundFiles.exists($0.value) }

            self.download(Array(missing), pairingCode: code) {
                self.isFetching = false
                guard code == self.pairingCode else { return }
                let available = wanted.filter { SoundFiles.exists($0.value) }
                self.removeUnusedRecordingFiles(keeping: Set(available.values))
                if available != self.recordingFiles {
                    self.recordingFiles = available
                }
            }
        }
    }

    /// Downloads recordings one at a time and saves each to its sound file name.
    private func download(_ items: [(key: String, value: String)], pairingCode: String, completion: @escaping () -> Void) {
        guard let item = items.first else {
            completion()
            return
        }
        let path = "\(RecordingCloud.collectionPath(pairingCode: pairingCode))/\(item.key)"
        FirestoreREST.get(path) { [weak self] result in
            if case .success(let document?) = result, let audio = document.fields["audio"] as? Data {
                try? audio.write(to: SoundFiles.url(item.value), options: .atomic)
            }
            self?.download(Array(items.dropFirst()), pairingCode: pairingCode, completion: completion)
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
}

/// Loads one saved recording (for example the wandering message) so it can be played, replaced, or deleted.
final class SavedRecordingStore: ObservableObject {
    @Published var savedData: Data?
    @Published var errorMessage: String?

    let recordingID: String
    private var pairingCode = ""

    init(recordingID: String) {
        self.recordingID = recordingID
    }

    func load(pairingCode: String) {
        self.pairingCode = pairingCode
        guard pairingCode.count == 6 else { return }
        let path = "\(RecordingCloud.collectionPath(pairingCode: pairingCode))/\(recordingID)"
        FirestoreREST.get(path) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let document):
                self.savedData = document?.fields["audio"] as? Data
                self.errorMessage = nil
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func save(_ data: Data) {
        savedData = data
        RecordingCloud.upload(pairingCode: pairingCode, id: recordingID, data: data) { [weak self] error in
            self?.errorMessage = error?.localizedDescription
        }
    }

    func delete() {
        savedData = nil
        RecordingCloud.delete(pairingCode: pairingCode, id: recordingID) { [weak self] error in
            self?.errorMessage = error?.localizedDescription
        }
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
