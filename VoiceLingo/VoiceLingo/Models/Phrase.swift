import Foundation

struct Phrase: Codable, Identifiable {
    let id: UUID
    let target: String
    let native: String
    let phonetic: String

    enum CodingKeys: String, CodingKey {
        case target, native, phonetic
    }

    init(target: String, native: String, phonetic: String) {
        self.id = UUID()
        self.target = target
        self.native = native
        self.phonetic = phonetic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(String.self, forKey: .target)
        native = try container.decode(String.self, forKey: .native)
        phonetic = try container.decode(String.self, forKey: .phonetic)
        self.id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(native, forKey: .native)
        try container.encode(phonetic, forKey: .phonetic)
    }
}
