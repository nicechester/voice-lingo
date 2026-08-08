import Foundation

/// Selects and slot-fills pre-authored tutor lines.
///
/// THIS IS NOT A LANGUAGE MODEL. It can only (a) pick one whole string out of a
/// human-authored array, and (b) substitute `{slot}` tokens with values from another
/// human-authored array. It never composes, conjugates, or inflects anything.
///
/// Not thread-safe by design — create one per session and use it from the main actor.
public final class SpeechComposer {

    private let bank: SpeechBank
    /// Injected so tests are deterministic. Returns an index in 0..<upperBound.
    private let randomIndex: (Int) -> Int
    /// Last index used per pool, so we never repeat a variant back-to-back.
    private var lastIndexByPool: [String: Int] = [:]

    public init(bank: SpeechBank, randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.bank = bank
        self.randomIndex = randomIndex
    }

    /// Returns a rendered line for `act`, or nil if the bank has no usable variant.
    ///
    /// Variants whose placeholders cannot all be filled from `slots` are excluded before
    /// selection, so a rendered line never contains a leftover `{token}`.
    public func line(for act: SpeechAct, slots: [String: String] = [:]) -> SpeechLine? {
        let key = act.rawValue
        guard let pool = bank.pools[key], !pool.isEmpty else { return nil }

        let usable = pool.filter { canFill($0.text, with: slots) }
        guard !usable.isEmpty else { return nil }

        let index = pickIndex(poolKey: key, count: usable.count)
        let variant = usable[index]
        return SpeechLine(text: fill(variant.text, with: slots), locale: variant.locale)
    }

    /// Picks one value from a pre-authored slot list, e.g. a city name for a roleplay variant.
    /// Uses the same no-immediate-repeat rule so consecutive roleplays differ.
    public func slotValue(_ slot: String) -> String? {
        guard let values = bank.slots[slot], !values.isEmpty else { return nil }
        return values[pickIndex(poolKey: "slot:\(slot)", count: values.count)]
    }

    /// Convenience: pick one value for each requested slot in one go.
    public func slotValues(_ names: [String]) -> [String: String] {
        names.reduce(into: [:]) { result, name in
            if let value = slotValue(name) { result[name] = value }
        }
    }

    // MARK: - Private

    /// Random selection with a no-immediate-repeat rule: if we'd repeat the previous choice
    /// and the pool has alternatives, step forward one slot instead.
    private func pickIndex(poolKey: String, count: Int) -> Int {
        guard count > 1 else {
            lastIndexByPool[poolKey] = 0
            return 0
        }
        var index = randomIndex(count)
        if index == lastIndexByPool[poolKey] {
            index = (index + 1) % count
        }
        lastIndexByPool[poolKey] = index
        return index
    }

    private func placeholders(in template: String) -> [String] {
        // Matches {name}, {city}, {recognized}, ... Deliberately restrictive: letters only.
        guard let regex = try? NSRegularExpression(pattern: "\\{([A-Za-z]+)\\}") else { return [] }
        let range = NSRange(template.startIndex..., in: template)
        return regex.matches(in: template, range: range).compactMap {
            Range($0.range(at: 1), in: template).map { String(template[$0]) }
        }
    }

    private func canFill(_ template: String, with slots: [String: String]) -> Bool {
        placeholders(in: template).allSatisfy { slots[$0] != nil }
    }

    private func fill(_ template: String, with slots: [String: String]) -> String {
        slots.reduce(template) { partial, pair in
            partial.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
        }
    }
}

public extension SpeechComposer {
    /// Echoes the learner's own recognized speech back inside a pre-authored carrier line.
    ///
    /// The ONLY place runtime text enters a spoken line. The recognized text is passed through
    /// byte-for-byte: never conjugated, corrected, or recombined. If the recognizer returned
    /// nothing usable, we return nil and the caller falls back to a non-echo line.
    func echo(recognized: String) -> SpeechLine? {
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard against echoing garbage or a whole paragraph back at the learner.
        guard (1...60).contains(trimmed.count) else { return nil }
        return line(for: .echoResponse, slots: ["recognized": trimmed])
    }
}
