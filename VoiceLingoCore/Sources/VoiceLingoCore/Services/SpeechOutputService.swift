import AVFoundation

#if os(iOS)
public final class SpeechOutputService: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = SpeechOutputService()

    private let synthesizer = AVSpeechSynthesizer()
    private var currentLocale: String = "es-MX"
    private var speechRate: Float = 0.5
    private var pitchMultiplier: Float = 1.0
    private var completionsByUtterance: [AVSpeechUtterance: @Sendable () -> Void] = [:]

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

    public func speak(_ text: String, locale: String? = nil, suspendRouter: Bool = true, completion: (@Sendable () -> Void)? = nil) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale ?? currentLocale)
        utterance.rate = speechRate
        utterance.pitchMultiplier = pitchMultiplier
        if suspendRouter { VoiceCommandRouter.shared.suspend() }
        if let completion { completionsByUtterance[utterance] = completion }
        synthesizer.speak(utterance)
    }

    public func speakSlowly(_ text: String, locale: String? = nil, suspendRouter: Bool = true, completion: (@Sendable () -> Void)? = nil) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale ?? currentLocale)
        utterance.rate = max(0.1, speechRate * 0.6)
        utterance.pitchMultiplier = pitchMultiplier
        if suspendRouter { VoiceCommandRouter.shared.suspend() }
        if let completion { completionsByUtterance[utterance] = completion }
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        completionsByUtterance.removeAll()
    }

    public func pause() {
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
    }

    public func resume() {
        synthesizer.continueSpeaking()
    }

    public func isSpeaking() -> Bool {
        synthesizer.isSpeaking
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let completion = completionsByUtterance.removeValue(forKey: utterance)
        let stillSpeaking = synthesizer.isSpeaking
        DispatchQueue.main.async {
            if !stillSpeaking {
                VoiceCommandRouter.shared.resume()
            }
            completion?()
        }
    }
}
#endif
