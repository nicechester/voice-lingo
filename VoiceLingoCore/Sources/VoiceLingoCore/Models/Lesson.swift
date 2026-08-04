import Foundation

public struct Lesson: Codable, Identifiable {
    public let id: String
    public let title: String
    public let grammarNote: String?
    public let phrases: [Phrase]

    enum CodingKeys: String, CodingKey {
        case id, title, grammarNote, phrases
    }

    public init(
        id: String,
        title: String,
        grammarNote: String? = nil,
        phrases: [Phrase]
    ) {
        self.id = id
        self.title = title
        self.grammarNote = grammarNote
        self.phrases = phrases
    }
}

public struct Level: Codable, Identifiable {
    public let id: String
    public let title: String
    public let lessons: [Lesson]

    enum CodingKeys: String, CodingKey {
        case id, title, lessons
    }

    public init(
        id: String,
        title: String,
        lessons: [Lesson]
    ) {
        self.id = id
        self.title = title
        self.lessons = lessons
    }
}
