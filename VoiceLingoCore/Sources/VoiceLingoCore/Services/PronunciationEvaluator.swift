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

    // MARK: - Multi-candidate evaluation

    /// The result of comparing recognized speech against a set of acceptable answers.
    public struct CandidateMatch: Equatable, Sendable {
        /// The acceptable answer that scored best (original, un-normalized text).
        public let candidate: String
        /// 0.0-1.0 similarity against that candidate.
        public let accuracy: Double
        /// Levenshtein distance against that candidate, after normalization.
        public let distance: Int
        /// True if the distance was within the threshold for that candidate's length.
        public let isAcceptable: Bool
    }

    /// Compares recognized speech against a finite, pre-authored set of acceptable answers
    /// and returns the best-scoring one.
    ///
    /// This is fuzzy string matching over a closed set — NOT comprehension. The app can only
    /// ever "accept" a string that a human already wrote into a content file.
    ///
    /// - Parameters:
    ///   - recognized: Raw text from SFSpeechRecognizer.
    ///   - candidates: The full set of acceptable answers (e.g. `DialogueTurn.hints`).
    ///   - allowSubstring: If true, a candidate contained anywhere inside the recognized text
    ///     counts as an exact match. Use for conversational turns where the learner may add
    ///     filler ("um, estoy bien, gracias profesora"). Leave false for pronunciation drills,
    ///     where we want the learner to produce the phrase and nothing else.
    /// - Returns: The best match, or nil if `candidates` is empty.
    public func bestMatch(
        recognized: String,
        candidates: [String],
        allowSubstring: Bool = false
    ) -> CandidateMatch? {
        guard !candidates.isEmpty else { return nil }
        let r = normalize(recognized)

        var best: CandidateMatch?
        for candidate in candidates {
            let c = normalize(candidate)

            if r == c || (allowSubstring && !c.isEmpty && r.contains(c)) {
                return CandidateMatch(candidate: candidate, accuracy: 1.0,
                                      distance: 0, isAcceptable: true)
            }

            let distance = levenshteinDistance(r, c)
            let maxLength = max(r.count, c.count)
            let accuracy = maxLength > 0 ? max(0.0, 1.0 - Double(distance) / Double(maxLength)) : 1.0
            let match = CandidateMatch(
                candidate: candidate,
                accuracy: accuracy,
                distance: distance,
                isAcceptable: distance <= threshold(forLength: c.count)
            )
            if best == nil || match.accuracy > best!.accuracy { best = match }
        }
        return best
    }

    /// Convenience: true if any candidate is an acceptable match.
    public func evaluate(
        recognized: String,
        candidates: [String],
        allowSubstring: Bool = false
    ) -> Bool {
        bestMatch(recognized: recognized,
                  candidates: candidates,
                  allowSubstring: allowSubstring)?.isAcceptable ?? false
    }

    /// Edit-distance budget scaled to the length of the expected answer.
    ///
    /// A fixed budget of 2 is right for short drill phrases ("Buenos días") but far too strict
    /// for full dialogue lines ("Cuando era niño, vivía en un pueblo pequeño", 43 chars), where
    /// two recognizer slips are near-certain. Threshold only departs from 2 above ~30 chars,
    /// so existing drill behaviour and existing tests are unchanged.
    private func threshold(forLength length: Int) -> Int {
        max(levenshteinThreshold, length / 10)
    }

    public func evaluate(recognized: String, target: String) -> Bool {
        evaluate(recognized: recognized, candidates: [target], allowSubstring: false)
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
        let folded = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let stripped = folded.unicodeScalars
            .filter { !CharacterSet.punctuationCharacters.contains($0) }
        return String(String.UnicodeScalarView(stripped))
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
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
