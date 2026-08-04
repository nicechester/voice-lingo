import AVFoundation

class SpeechOutputService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechOutputService()

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var currentLocale: String = "es-MX"
    private var speechRate: Float = 0.5
    private var pitchMultiplier: Float = 1.0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func configure(locale: String, speechRate: Float = 0.5, pitch: Float = 1.0) {
        self.currentLocale = locale
        self.speechRate = max(0.1, min(2.0, speechRate))
        self.pitchMultiplier = max(0.5, min(2.0, pitch))
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        do {
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to activate audio session: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: currentLocale)
        utterance.rate = speechRate
        utterance.pitchMultiplier = pitchMultiplier

        synthesizer.speak(utterance)

        if let completion = completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedSpeechDuration(text)) {
                completion()
            }
        }
    }

    func speakSlowly(_ text: String, completion: (() -> Void)? = nil) {
        let slowRate = max(0.1, speechRate * 0.6)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: currentLocale)
        utterance.rate = slowRate
        utterance.pitchMultiplier = pitchMultiplier

        synthesizer.speak(utterance)

        if let completion = completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedSpeechDuration(text, rate: slowRate)) {
                completion()
            }
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func isSpeaking() -> Bool {
        synthesizer.isSpeaking
    }

    private func estimatedSpeechDuration(_ text: String, rate: Float = -1) -> TimeInterval {
        let rate = rate >= 0 ? rate : self.speechRate
        let wordCount = text.split(separator: " ").count
        let averageWordsPerSecond = Double(rate) * 2.5
        let estimatedSeconds = Double(wordCount) / averageWordsPerSecond
        return max(0.5, estimatedSeconds)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
}
