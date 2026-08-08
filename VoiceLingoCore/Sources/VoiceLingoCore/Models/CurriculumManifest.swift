import Foundation

public struct LessonSummary: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct LevelSummary: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let lessons: [LessonSummary]
    public init(id: String, title: String, lessons: [LessonSummary]) {
        self.id = id
        self.title = title
        self.lessons = lessons
    }
}

public struct CurriculumManifest: Codable, Sendable {
    public let language: String
    public let voiceLocale: String
    public let recognizerLocale: String
    public let levels: [LevelSummary]
    public init(language: String, voiceLocale: String, recognizerLocale: String, levels: [LevelSummary]) {
        self.language = language
        self.voiceLocale = voiceLocale
        self.recognizerLocale = recognizerLocale
        self.levels = levels
    }
}
