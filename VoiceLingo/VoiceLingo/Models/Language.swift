import Foundation

struct Language: Codable, Identifiable {
    let id: String
    let code: String
    let name: String
    let nativeName: String
    let locale: String
    let voiceLocale: String
    let recognizerLocale: String
    let flag: String

    enum CodingKeys: String, CodingKey {
        case code, name, nativeName, locale, voiceLocale, recognizerLocale, flag
    }

    init(
        code: String,
        name: String,
        nativeName: String,
        locale: String,
        voiceLocale: String,
        recognizerLocale: String,
        flag: String
    ) {
        self.id = code
        self.code = code
        self.name = name
        self.nativeName = nativeName
        self.locale = locale
        self.voiceLocale = voiceLocale
        self.recognizerLocale = recognizerLocale
        self.flag = flag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        nativeName = try container.decode(String.self, forKey: .nativeName)
        locale = try container.decode(String.self, forKey: .locale)
        voiceLocale = try container.decode(String.self, forKey: .voiceLocale)
        recognizerLocale = try container.decode(String.self, forKey: .recognizerLocale)
        flag = try container.decode(String.self, forKey: .flag)
        self.id = code
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(name, forKey: .name)
        try container.encode(nativeName, forKey: .nativeName)
        try container.encode(locale, forKey: .locale)
        try container.encode(voiceLocale, forKey: .voiceLocale)
        try container.encode(recognizerLocale, forKey: .recognizerLocale)
        try container.encode(flag, forKey: .flag)
    }
}
