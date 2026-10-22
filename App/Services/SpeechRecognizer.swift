import AVFoundation
import Speech

/// German speech recognition, on-device when the phone supports it.
@MainActor
final class SpeechRecognizer: ObservableObject {
    /// Candidate transcriptions, best first.
    @Published private(set) var transcripts: [String] = []
    @Published private(set) var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isFinished = false

    static let permissionDeniedMessage =
        "Per gli esercizi di pronuncia consenti microfono e riconoscimento vocale in Impostazioni > LearnCards."

    static func requestPermissions() async -> Bool {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start() {
        cancel()
        errorMessage = nil
        transcripts = []
        isFinished = false

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Riconoscimento vocale tedesco non disponibile."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .search
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            let engine = AVAudioEngine()
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()

            self.request = request
            audioEngine = engine
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let texts = result?.transcriptions.map(\.formattedString)
                let done = error != nil || (result?.isFinal ?? false)
                Task { @MainActor in
                    self?.handle(texts: texts, done: done)
                }
            }
            isRecording = true
        } catch {
            errorMessage = "Impossibile usare il microfono: \(error.localizedDescription)"
            cancel()
        }
    }

    /// Stops listening and waits briefly for the final transcription.
    func stop() async -> [String] {
        guard isRecording else { return transcripts }
        request?.endAudio()
        stopAudio()
        var waited = 0
        while !isFinished && waited < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        task = nil
        request = nil
        return transcripts
    }

    func cancel() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        stopAudio()
    }

    private func handle(texts: [String]?, done: Bool) {
        if let texts, !texts.isEmpty {
            transcripts = texts
        }
        if done {
            isFinished = true
            stopAudio()
        }
    }

    private func stopAudio() {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        isRecording = false
    }
}
