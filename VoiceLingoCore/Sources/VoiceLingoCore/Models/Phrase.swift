import Foundation

public struct Phrase: Codable, Identifiable, Sendable {
    public let id: UUID
    public let target: String
    public let native: String
    public let phonetic: String

    enum CodingKeys: String, CodingKey {
        case target, native, phonetic
    }

    public init(target: String, native: String, phonetic: String) {
        self.id = UUID()
        self.target = target
        self.native = native
        self.phonetic = phonetic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        native = try container.decode(String.self, forKey: .native)
        phonetic = try container.decode(String.self, forKey: .phonetic)
        self.id = UUID()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(native, forKey: .native)
        try container.encode(phonetic, forKey: .phonetic)
    }
}
