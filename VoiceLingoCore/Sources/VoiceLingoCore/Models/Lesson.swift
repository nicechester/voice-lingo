import Foundation

public struct Lesson: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let grammarNote: String?
    public let phrases: [Phrase]
    public let dialogue: DialogueScenario?
    public let practiceItems: [PracticeItem]?

    enum CodingKeys: String, CodingKey {
        case id, title, grammarNote, phrases, dialogue, practiceItems
    }

    public init(
        id: String,
        title: String,
        grammarNote: String? = nil,
        phrases: [Phrase],
        dialogue: DialogueScenario? = nil,
        practiceItems: [PracticeItem]? = nil
    ) {
        self.id = id
        self.title = title
        self.grammarNote = grammarNote
        self.phrases = phrases
        self.dialogue = dialogue
        self.practiceItems = practiceItems
    }
}
