import Foundation

/// The three authored practice types. Values match the `type` strings in lesson JSON.
public enum PracticeItemType: String, Sendable {
    case translation
    case fillBlank
    case qa
}

/// Which language a prompt should be spoken in. Derived, not authored.
public enum PromptLocaleKind: Sendable, Equatable {
    case native   // English — speak with "en-US"
    case target   // Spanish — speak with the manifest voiceLocale
}

/// A quiz question, resolved and ready for the ViewModel to speak.
public struct QuizItem: Equatable, Sendable {
    public let phraseKey: String        // Phrase.progressKey(inLesson:)
    public let phraseTarget: String     // for the reveal
    public let type: PracticeItemType
    /// Prompt text with `___` already replaced by a spoken-friendly pause.
    public let spokenPrompt: String
    public let promptLocale: PromptLocaleKind
    public let answer: String
}

/// A read-only snapshot of one phrase's SRS state. Mapped from PhraseProgress by the caller
/// so this type stays free of SwiftData and testable on macOS.
public struct ReviewState: Sendable, Equatable {
    public let phraseKey: String
    public let correctCount: Int
    public let incorrectCount: Int
    public let isDue: Bool

    public init(phraseKey: String, correctCount: Int, incorrectCount: Int, isDue: Bool) {
        self.phraseKey = phraseKey
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.isDue = isDue
    }
}

public enum QuizRunner {

    /// Builds the quiz for a lesson from the phrases already introduced this session.
    ///
    /// Ordering is fully deterministic (no randomness) so the same inputs always produce the
    /// same quiz — required by the "fully deterministic" policy and needed for stable tests.
    ///
    /// Priority order:
    ///   1. Phrases the learner has previously got wrong more often than right ("struggling")
    ///   2. Phrases never quizzed before
    ///   3. Phrases due for review
    ///   4. Everything else
    /// Ties break on the phrase's position in the lesson, so ordering is stable.
    public static func buildQuiz(
        phrases: [Phrase],
        lessonId: String,
        reviewStates: [String: ReviewState],
        maxItems: Int = 5
    ) -> [QuizItem] {

        struct Ranked { let priority: Int; let order: Int; let item: QuizItem }

        var ranked: [Ranked] = []
        for (order, phrase) in phrases.enumerated() {
            guard let practiceItems = phrase.practiceItems, !practiceItems.isEmpty else { continue }
            let key = phrase.progressKey(inLesson: lessonId)
            let state = reviewStates[key]

            let priority: Int
            if let s = state, s.incorrectCount > s.correctCount { priority = 0 }
            else if state == nil                                 { priority = 1 }
            else if state?.isDue == true                          { priority = 2 }
            else                                                  { priority = 3 }

            // Rotate item type by how many times this phrase has been answered correctly,
            // so a repeat review gets a DIFFERENT question, not the same one again.
            let rotation = (state?.correctCount ?? 0) % practiceItems.count
            let source = practiceItems[rotation]
            guard let item = makeItem(from: source, phraseKey: key, phraseTarget: phrase.target)
            else { continue }

            ranked.append(Ranked(priority: priority, order: order, item: item))
        }

        return ranked
            .sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.order < $1.order }
            .prefix(maxItems)
            .map(\.item)
    }

    /// Converts an authored PracticeItem into something speakable.
    public static func makeItem(from source: PracticeItem,
                         phraseKey: String,
                         phraseTarget: String) -> QuizItem? {
        guard let type = PracticeItemType(rawValue: source.type) else { return nil }

        // "Buenos ___, señor." read literally by TTS becomes "underscore underscore underscore".
        // Replace the blank with an ellipsis, which AVSpeechSynthesizer renders as a pause.
        let spoken = source.prompt.replacingOccurrences(of: "___", with: "…")

        // Prompt language is derived from the authored type, not stored per item:
        //   translation -> English prompt ("Translate: Good morning")
        //   fillBlank   -> target-language prompt with a gap
        //   qa          -> target-language question
        let locale: PromptLocaleKind = (type == .translation) ? .native : .target

        return QuizItem(phraseKey: phraseKey,
                        phraseTarget: phraseTarget,
                        type: type,
                        spokenPrompt: spoken,
                        promptLocale: locale,
                        answer: source.answer)
    }

    /// Grades one answer. `allowSubstring` is on because a learner answering a question
    /// naturally wraps the answer in filler ("pues, buenos días").
    public static func grade(recognized: String,
                             item: QuizItem,
                             evaluator: PronunciationEvaluator = .shared) -> Bool {
        evaluator.evaluate(recognized: recognized,
                           candidates: [item.answer],
                           allowSubstring: true)
    }
}
