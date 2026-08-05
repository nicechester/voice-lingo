import Foundation

public struct Language: Codable, Identifiable, Sendable {
    public let id: String
    public let code: String
    public let name: String
    public let nativeName: String
    public let locale: String
    public let voiceLocale: String
    public let recognizerLocale: String
    public let flag: String

    enum CodingKeys: String, CodingKey {
        case code, name, nativeName, locale, voiceLocale, recognizerLocale, flag
    }

    public init(
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

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(name, forKey: .name)
        try container.encode(nativeName, forKey: .nativeName)
        try container.encode(locale, forKey: .locale)
        try container.encode(voiceLocale, forKey: .voiceLocale)
        try container.encode(recognizerLocale, forKey: .recognizerLocale)
        try container.encode(flag, forKey: .flag)
    }

    public static let supportedLanguages: [Language] = [
        .init(code: "es", name: "Spanish", nativeName: "Español", locale: "es-MX", voiceLocale: "es-MX", recognizerLocale: "es-MX", flag: "🇪🇸")
    ]
}
