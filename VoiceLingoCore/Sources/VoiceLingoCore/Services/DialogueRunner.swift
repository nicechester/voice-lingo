import Foundation

/// One instruction for the ViewModel to carry out. Pure data; no audio here.
public enum DialogueStep: Equatable, Sendable {
    /// Speak the English scenario framing, e.g. "You run into a coworker in the morning."
    case introduceScenario(String)
    /// Speak an NPC line in the target language, optionally followed by its native gloss.
    case npcLine(text: String, native: String?)
    /// Prompt the learner and open the mic.
    /// - candidates: the finite acceptable-answer set for this turn (may be empty for open turns).
    /// - cue: English instruction for what to say, if the content author supplied one.
    /// - isOpen: true => do not evaluate; echo the answer instead (see SpeechComposer.echo).
    case awaitLearner(turnIndex: Int, candidates: [String], cue: String?, isOpen: Bool)
    /// Script exhausted.
    case finished
}

/// What to do after the learner spoke on a `learner` turn.
public enum DialogueOutcome: Equatable, Sendable {
    /// Matched one of the authored hints.
    case matched(candidate: String)
    /// Open turn — nothing to validate; echo `recognized` back.
    case openAccepted(recognized: String)
    /// Didn't match; attempts remain. Speak `modelAnswer` slowly, then re-open the mic.
    case retry(attemptsRemaining: Int, modelAnswer: String)
    /// Out of attempts. Speak `modelAnswer` and CONTINUE — a dialogue never dead-ends.
    case movedOn(modelAnswer: String)
}

/// Walks a pre-authored dialogue script. Deterministic and side-effect free.
///
/// Scope note: this performs multi-candidate fuzzy string matching over a closed,
/// human-authored answer set. It does not understand language and cannot accept any
/// answer that an author did not write down.
public final class DialogueRunner {

    public let scenario: DialogueScenario
    private let maxAttemptsPerTurn: Int
    private let evaluator: PronunciationEvaluator

    private var cursor: Int = -1          // -1 = not started
    private var attemptsThisTurn: Int = 0

    public private(set) var learnerTurnsAttempted: Int = 0
    public private(set) var learnerTurnsMatched: Int = 0

    public init(scenario: DialogueScenario,
                evaluator: PronunciationEvaluator = .shared,
                maxAttemptsPerTurn: Int = 2) {
        self.scenario = scenario
        self.evaluator = evaluator
        self.maxAttemptsPerTurn = maxAttemptsPerTurn
    }

    /// First step: the scenario framing.
    public func start() -> DialogueStep {
        cursor = -1
        return .introduceScenario(scenario.scenario)
    }

    /// Advance to the next turn. Call after the previous step's audio has finished
    /// (and, for a learner turn, after `submit` returned `.matched` / `.openAccepted` / `.movedOn`).
    public func advance() -> DialogueStep {
        cursor += 1
        attemptsThisTurn = 0
        guard cursor < scenario.turns.count else { return .finished }

        let turn = scenario.turns[cursor]
        switch turn.speaker {
        case .npc:
            // A malformed npc turn with no line would stall the script — skip it.
            guard let line = turn.line, !line.isEmpty else { return advance() }
            return .npcLine(text: line, native: turn.native)
        case .learner:
            return .awaitLearner(
                turnIndex: cursor,
                candidates: turn.hints ?? [],
                cue: turn.cue,
                isOpen: turn.openResponse ?? false
            )
        }
    }

    /// Grade the learner's speech for the current turn.
    public func submit(recognized: String) -> DialogueOutcome {
        guard cursor >= 0, cursor < scenario.turns.count else {
            return .movedOn(modelAnswer: "")
        }
        let turn = scenario.turns[cursor]
        let candidates = turn.hints ?? []

        if turn.openResponse == true || candidates.isEmpty {
            learnerTurnsAttempted += 1
            learnerTurnsMatched += 1
            return .openAccepted(recognized: recognized)
        }

        attemptsThisTurn += 1
        // allowSubstring: conversational answers carry filler the drill path wouldn't tolerate.
        let matched = evaluator.evaluate(recognized: recognized,
                                         candidates: candidates,
                                         allowSubstring: true)
        if matched {
            learnerTurnsAttempted += 1
            learnerTurnsMatched += 1
            let best = evaluator.bestMatch(recognized: recognized,
                                           candidates: candidates,
                                           allowSubstring: true)
            return .matched(candidate: best?.candidate ?? candidates[0])
        }

        // First authored hint is the canonical model answer.
        let modelAnswer = candidates[0]
        if attemptsThisTurn < maxAttemptsPerTurn {
            return .retry(attemptsRemaining: maxAttemptsPerTurn - attemptsThisTurn,
                          modelAnswer: modelAnswer)
        }
        learnerTurnsAttempted += 1
        return .movedOn(modelAnswer: modelAnswer)
    }

    /// Re-emits the current learner turn without advancing the cursor. Used for retries.
    public func repeatCurrentTurn() -> DialogueStep {
        guard cursor >= 0, cursor < scenario.turns.count else { return .finished }
        let turn = scenario.turns[cursor]
        return .awaitLearner(turnIndex: cursor, candidates: turn.hints ?? [],
                             cue: turn.cue, isOpen: turn.openResponse ?? false)
    }

    /// 0.0-1.0. Used for the session summary; not for level unlocking.
    public var accuracy: Double {
        guard learnerTurnsAttempted > 0 else { return 0 }
        return Double(learnerTurnsMatched) / Double(learnerTurnsAttempted)
    }
}
