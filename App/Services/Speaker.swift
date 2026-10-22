import AVFoundation

/// German text-to-speech for hearing the correct pronunciation.
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    /// `slow` is for numbers heard in listening exercises.
    func speak(_ text: String, slow: Bool = false) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slow ? 0.6 : 0.9)
        synthesizer.speak(utterance)
    }
}
