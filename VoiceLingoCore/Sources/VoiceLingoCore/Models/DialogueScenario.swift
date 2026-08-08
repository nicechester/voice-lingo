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

    public init(speaker: Speaker, line: String? = nil, native: String? = nil,
                expectedIntent: String? = nil, hints: [String]? = nil) {
        self.speaker = speaker
        self.line = line
        self.native = native
        self.expectedIntent = expectedIntent
        self.hints = hints
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
