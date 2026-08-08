import Foundation

/// A category of thing the tutor says. Each act maps to a pool of pre-written variants.
public enum SpeechAct: String, Codable, Sendable, CaseIterable {
    case sessionOpen        // "Alright, fifteen minutes. Let's go."
    case sessionClose       // "That's time. Same again tomorrow?"
    case praise             // said on a correct answer
    case gentleCorrection   // said on an incorrect answer
    case transition         // moving between phrases / phases
    case timeRemaining      // "We're about ten minutes in."
    case revealAnswer       // "Here's how it goes:"
    case dialogueIntro      // framing before the roleplay
    case learnerTurnCue     // generic "your turn" for a dialogue turn with no authored cue
    case echoResponse       // acknowledges an open answer; see §4.4
    case quizIntro          // framing before the recall check
}

/// One pre-written, human-reviewed line.
public struct SpeechVariant: Codable, Sendable, Equatable {
    /// The line. May contain `{slot}` placeholders.
    public let text: String
    /// BCP-47 locale for TTS, e.g. "en-US" or "es-MX". nil = the language's `voiceLocale`.
    public let locale: String?

    public init(text: String, locale: String? = nil) {
        self.text = text
        self.locale = locale
    }
}

/// A rendered, ready-to-speak line.
public struct SpeechLine: Equatable, Sendable {
    public let text: String
    public let locale: String?
}

/// The per-language bank of pre-authored tutor lines and slot values.
/// Loaded from `Content/{lang}/speech-bank.json`.
public struct SpeechBank: Codable, Sendable {
    public let language: String
    /// SpeechAct.rawValue -> variants.
    public let pools: [String: [SpeechVariant]]
    /// Slot name -> the complete set of allowed values, e.g. "city" -> ["México", "Chicago"].
    /// Every value here is human-reviewed content. Nothing else may ever fill a slot,
    /// with the single audited exception of `{recognized}` (see SpeechComposer.echo).
    public let slots: [String: [String]]

    public init(language: String,
                pools: [String: [SpeechVariant]],
                slots: [String: [String]] = [:]) {
        self.language = language
        self.pools = pools
        self.slots = slots
    }
}
