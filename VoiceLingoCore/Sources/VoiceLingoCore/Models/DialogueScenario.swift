import Foundation

public enum Speaker: String, Codable, Sendable {
    case npc
    case learner
}

public struct DialogueTurn: Codable, Sendable {
    public let speaker: Speaker
    public let line: String?
    public let native: String?
    public let expectedIntent: String?
    public let hints: [String]?

    /// Spoken English instruction for a learner turn, e.g. "Tell me you're doing well."
    /// Optional: falls back to a generic cue from the speech bank.
    public let cue: String?

    /// If true this turn has no single correct answer (e.g. "¿De dónde eres?").
    /// The app will NOT evaluate the response — it echoes it back verbatim inside a
    /// pre-authored carrier line. Defaults to false when absent.
    public let openResponse: Bool?

    public init(speaker: Speaker, line: String? = nil, native: String? = nil,
                expectedIntent: String? = nil, hints: [String]? = nil,
                cue: String? = nil, openResponse: Bool? = nil) {
        self.speaker = speaker
        self.line = line
        self.native = native
        self.expectedIntent = expectedIntent
        self.hints = hints
        self.cue = cue
        self.openResponse = openResponse
    }
}

public struct DialogueScenario: Codable, Identifiable, Sendable {
    public let id: String
    public let scenario: String
    public let turns: [DialogueTurn]

    public init(id: String, scenario: String, turns: [DialogueTurn]) {
        self.id = id
        self.scenario = scenario
        self.turns = turns
    }
}
