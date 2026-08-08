import Foundation

public struct PracticeItem: Codable, Sendable {
    public let type: String   // "translation", "fillBlank", "qa"
    public let prompt: String
    public let answer: String
}

public struct ExampleSentence: Codable, Sendable {
    public let target: String
    public let native: String
    public init(target: String, native: String) {
        self.target = target
        self.native = native
    }
}

public struct Phrase: Codable, Identifiable, Sendable {
    public let id: UUID
    public let target: String
    public let native: String
    public let phonetic: String
    public let vocabularyIntro: String?
    public let memoryHook: String?
    public let practiceItems: [PracticeItem]?
    public let exampleSentence: ExampleSentence?
    public let syllables: [String]?
    public let grammarNote: String?

    enum CodingKeys: String, CodingKey {
        case target, native, phonetic, vocabularyIntro, memoryHook, practiceItems, exampleSentence, syllables, grammarNote
    }

    public init(target: String, native: String, phonetic: String,
                vocabularyIntro: String? = nil, memoryHook: String? = nil,
                practiceItems: [PracticeItem]? = nil, exampleSentence: ExampleSentence? = nil,
                syllables: [String]? = nil, grammarNote: String? = nil) {
        self.id = UUID()
        self.target = target
        self.native = native
        self.phonetic = phonetic
        self.vocabularyIntro = vocabularyIntro
        self.memoryHook = memoryHook
        self.practiceItems = practiceItems
        self.exampleSentence = exampleSentence
        self.syllables = syllables
        self.grammarNote = grammarNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        native = try container.decode(String.self, forKey: .native)
        phonetic = try container.decode(String.self, forKey: .phonetic)
        vocabularyIntro = try container.decodeIfPresent(String.self, forKey: .vocabularyIntro)
        memoryHook = try container.decodeIfPresent(String.self, forKey: .memoryHook)
        practiceItems = try container.decodeIfPresent([PracticeItem].self, forKey: .practiceItems)
        exampleSentence = try container.decodeIfPresent(ExampleSentence.self, forKey: .exampleSentence)
        syllables = try container.decodeIfPresent([String].self, forKey: .syllables)
        grammarNote = try container.decodeIfPresent(String.self, forKey: .grammarNote)
        self.id = UUID()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(native, forKey: .native)
        try container.encode(phonetic, forKey: .phonetic)
        try container.encodeIfPresent(vocabularyIntro, forKey: .vocabularyIntro)
        try container.encodeIfPresent(memoryHook, forKey: .memoryHook)
        try container.encodeIfPresent(practiceItems, forKey: .practiceItems)
        try container.encodeIfPresent(exampleSentence, forKey: .exampleSentence)
        try container.encodeIfPresent(syllables, forKey: .syllables)
        try container.encodeIfPresent(grammarNote, forKey: .grammarNote)
    }
}
