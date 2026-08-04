import Foundation

struct Curriculum: Codable {
    let language: String
    let voiceLocale: String
    let recognizerLocale: String
    let levels: [Level]

    enum CodingKeys: String, CodingKey {
        case language, voiceLocale, recognizerLocale, levels
    }

    init(
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
