import Foundation

public struct Curriculum: Codable {
    public let language: String
    public let voiceLocale: String
    public let recognizerLocale: String
    public let levels: [Level]

    enum CodingKeys: String, CodingKey {
        case language, voiceLocale, recognizerLocale, levels
    }

    public init(
        language: String,
        voiceLocale: String,
        recognizerLocale: String,
        levels: [Level]
    ) {
        self.language = language
        self.voiceLocale = voiceLocale
        self.recognizerLocale = recognizerLocale
        self.levels = levels
    }
}
