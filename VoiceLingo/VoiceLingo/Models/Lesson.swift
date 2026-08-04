import Foundation

struct Lesson: Codable, Identifiable {
    let id: String
    let title: String
    let grammarNote: String?
    let phrases: [Phrase]

    enum CodingKeys: String, CodingKey {
        case id, title, grammarNote, phrases
    }

    init(
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

struct Level: Codable, Identifiable {
    let id: String
    let title: String
    let lessons: [Lesson]

    enum CodingKeys: String, CodingKey {
        case id, title, lessons
    }

    init(
        id: String,
        title: String,
        lessons: [Lesson]
    ) {
        self.id = id
        self.title = title
        self.lessons = lessons
    }
}
