import Foundation

public final class PronunciationEvaluator: @unchecked Sendable {
    public static let shared = PronunciationEvaluator()

    private let levenshteinThreshold = 2
    private var phraseDatabase: [String: Phrase] = [:]

    public init() {}

    public func loadPhrases(_ phrases: [Phrase]) {
        for phrase in phrases {
            phraseDatabase[normalize(phrase.target)] = phrase
        }
    }

    public func evaluate(recognized: String, target: String) -> Bool {
        let normalizedRecognized = normalize(recognized)
        let normalizedTarget = normalize(target)

        if normalizedRecognized == normalizedTarget {
            return true
        }

        let distance = levenshteinDistance(normalizedRecognized, normalizedTarget)
        return distance <= levenshteinThreshold
    }

    public func getAccuracy(recognized: String, target: String) -> Double {
        let normalizedRecognized = normalize(recognized)
        let normalizedTarget = normalize(target)

        if normalizedRecognized == normalizedTarget {
            return 1.0
        }

        let distance = levenshteinDistance(normalizedRecognized, normalizedTarget)
        let maxLength = max(normalizedRecognized.count, normalizedTarget.count)

        guard maxLength > 0 else { return 1.0 }

        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        return max(0.0, similarity)
    }

    public func getPhoneticHint(for target: String) -> String? {
        let normalized = normalize(target)
        return phraseDatabase[normalized]?.phonetic
    }

    public func getFeedback(recognized: String, target: String) -> FeedbackResult {
        if evaluate(recognized: recognized, target: target) {
            return .correct
        }

        let accuracy = getAccuracy(recognized: recognized, target: target)

        if accuracy > 0.7 {
            return .closeAttempt(accuracy: accuracy)
        } else if accuracy > 0.4 {
            return .partialAttempt(accuracy: accuracy)
        } else {
            return .incorrect
        }
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespaces)
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)

        let m = s1.count
        let n = s2.count

        if m == 0 { return n }
        if n == 0 { return m }

        var previous = Array(0...n)

        for i in 1...m {
            var current = [i]

            for j in 1...n {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                let minValue = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                current.append(minValue)
            }

            previous = current
        }

        return previous[n]
    }
}

public enum FeedbackResult {
    case correct
    case closeAttempt(accuracy: Double)
    case partialAttempt(accuracy: Double)
    case incorrect

    public var isSuccessful: Bool {
        if case .correct = self {
            return true
        }
        return false
    }

    public var accuracyPercentage: Int? {
        switch self {
        case .correct:
            return 100
        case .closeAttempt(let accuracy), .partialAttempt(let accuracy):
            return Int(accuracy * 100)
        case .incorrect:
            return nil
        }
    }

    public var feedbackMessage: String {
        switch self {
        case .correct:
            return "Excelente! Correcto."
        case .closeAttempt(let accuracy):
            return "Casi correcto (\(Int(accuracy * 100))%)"
        case .partialAttempt(let accuracy):
            return "Intenta de nuevo (\(Int(accuracy * 100))%)"
        case .incorrect:
            return "Intenta de nuevo"
        }
    }
}
