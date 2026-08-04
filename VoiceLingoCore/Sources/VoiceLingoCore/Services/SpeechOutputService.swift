import AVFoundation

#if os(iOS)
public final class SpeechOutputService: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = SpeechOutputService()

    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    private var currentLocale: String = "es-MX"
    private var speechRate: Float = 0.5
    private var pitchMultiplier: Float = 1.0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func setLocale(_ locale: String) {
        self.currentLocale = locale
    }

    public func configure(locale: String, speechRate: Float = 0.5, pitch: Float = 1.0) {
        self.currentLocale = locale
        self.speechRate = max(0.1, min(2.0, speechRate))
        self.pitchMultiplier = max(0.5, min(2.0, pitch))
    }

    public func speak(_ text: String, completion: (@Sendable () -> Void)? = nil) {
        do {
            try audioSession.setCategory(
                .playAndRecord,
                options: [.defaultToSpeaker, .allowBluetoothA2DP]
            )
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
            completion()
        }
    }

    public func speakSlowly(_ text: String, completion: (@Sendable () -> Void)? = nil) {
        let slowRate = max(0.1, speechRate * 0.6)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: currentLocale)
        utterance.rate = slowRate
        utterance.pitchMultiplier = pitchMultiplier

        synthesizer.speak(utterance)

        if let completion = completion {
            completion()
        }
    }

    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    public func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    public func resume() {
        synthesizer.continueSpeaking()
    }

    public func isSpeaking() -> Bool {
        synthesizer.isSpeaking
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to deactivate audio session: \(error)")
            }
        }
    }
}
#endif
