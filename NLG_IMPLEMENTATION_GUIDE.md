# VoiceLingo: Activating the Dialogue & Quiz Phases, and a Deterministic Speech-Variation Layer

## 1. Why this work matters

Every one of the 26 shipped Spanish lesson files carries a scripted `dialogue` block and dozens of per-phrase `practiceItems`. **None of it is ever read at runtime.** `SessionViewModel` loads a lesson, walks `lesson.phrases` front to back doing listen-and-repeat, and then ends the session. `SessionPhase` already declares `.dialogue` and `.quiz` cases (`SessionViewModel.swift:29-35`) that nothing ever assigns. Roughly half the authored content in the app is dead weight in the bundle.

The second problem is tone. The app says exactly one thing when you're right ("Correct! Well done.", `SessionViewModel.swift:281`) and exactly one thing when you're wrong ("Not quite. Try again.", `SessionViewModel.swift:287`). Over a 15-minute hands-free session that is 40+ identical utterances. Compare that to the target feel in `data/a1-day1-lesson.txt` and `data/a1-day2-lesson.txt`, where a human tutor varies praise, changes one variable in a repeated roleplay ("different time of day, different city, make up a name"), announces elapsed time out loud, and corrects by continuing the conversation rather than stopping to buzz you.

This document specifies how to close both gaps **without** adding any model, any network call, or any runtime language generation. Everything below is finite-state logic, string matching, and selection from pre-written human-reviewed lists.

---

## 2. Constraints — read this section before writing any code

### 2.1 The no-runtime-LLM policy

From `DESIGN_DOC.md`, "AI Usage Policy" (lines 240-254), verbatim:

> **No runtime LLM.** The app makes no AI/LLM API calls at runtime. All voice features are handled by on-device platform frameworks:
> - Text-to-speech: AVSpeechSynthesizer
> - Speech recognition: Speech framework (SFSpeechRecognizer)
>
> This keeps the app offline-capable, free of API costs and latency, and avoids sending user audio off-device.
>
> **AI at development time only.** AI is used during development to build foundation work and content data — vocabulary lists, example phrases, translations, phonetic hints, and curriculum structure. Generated content is reviewed and corrected before shipping, then baked into the static `curriculum.json` bundles. **The shipped app is fully deterministic.**

"Fully deterministic" is the operative phrase. Given the same lesson file, the same user input, and the same random seed, the app must produce the same audio output. The only runtime language technologies permitted are the two Apple frameworks named above.

**Not permitted, at all, in this work:** CoreML/`NaturalLanguage` sentence generation, on-device small language models, Foundation Models framework, embedding-based semantic similarity, any HTTP call that returns text, any library that "understands" free-form input.

**Permitted:** `if`/`switch`, array indexing, `String.replacingOccurrences`, Levenshtein distance, `Int.random(in:)` over a fixed array, `Date` arithmetic, JSON decoding.

### 2.2 The hard guardrail: NEVER generate Spanish at runtime

> **The app must never procedurally construct, conjugate, inflect, or otherwise compose novel Spanish at runtime. Every Spanish string the app is capable of speaking must be traceable, character for character, to a human-reviewed string sitting in a JSON file in `Content/`.**

Concretely, all of the following are **forbidden**:

- Conjugating a verb at runtime (`"hablar" + subject → "hablas"`).
- Applying gender/number agreement in code (`"bueno" + feminine → "buena"`).
- Assembling a sentence from a grammar rule (`subject + verb + object`).
- Building a Spanish sentence by concatenating Spanish *fragments* that were authored separately and never reviewed together as one sentence.
- Pluralizing, adding articles, or "fixing up" a learner's recognized Spanish before speaking it back.

What **is** allowed is *selecting* a complete, pre-written Spanish string from a list, and *slot-filling* a pre-written Spanish template with a value drawn from a pre-written list — where the template and every possible value were reviewed together by a human as a set. `"Soy de {city}"` with `city ∈ ["México", "Chicago", "Los Ángeles"]` is fine: a reviewer can enumerate all 3 resulting sentences and sign off. `"Soy de " + recognizedText` is not fine, because the value is unbounded.

**Why this line matters more than the repetitiveness we're fixing:** a language-learning app whose entire value proposition is correctness cannot afford to teach a wrong conjugation. Sounding a bit repetitive is a UX complaint. Speaking ungrammatical Spanish in a confident tutor voice is a product-integrity failure, and the learner — by definition — cannot detect it. When in doubt, ship the repetitive version.

One deliberate, bounded exception is described in §4.4 (STT echo). Read that section before implementing it.

---

## 3. Current state

### 3.1 What runs today

`VoiceLingo/VoiceLingo/ViewModels/SessionViewModel.swift` is the entire session engine. Its flow:

```
startSession()
  → loadManifest / loadLesson, set TTS + STT locales
  → startNextPhrase()                    // line 132
      guard index < phrases.count else { completeSession() }   // line 133-136  ← ends the session here
      speak "Phrase N. Listen and repeat."  (en-US)
  → explainThenSpeak()                   // line 149
      speaks narrativeExplanationText():  vocabularyIntro + grammarNote + "Memory tip: " + memoryHook
  → speakPronunciationBreakdown()        // line 182   speakSlowly(phrase.target)
  → speakPhrase()                        // line 221   speak(phrase.target)
  → awaitUserResponse()                  // line 229   speak "Your turn." → 1s delay → recognize(timeout: 7)
  → evaluateResponse()                   // line 254   evaluator.evaluate(recognized:target: phrase.target)
      correct   → provideFeedback(correct: true)  → "Correct! Well done."   → speakExampleThenAdvance()
      wrong <3  → provideFeedback(correct: false) → "Not quite. Try again." → speakSlowly(target) → retry
      wrong ==3 → revealAnswer()                                            → speakExampleThenAdvance()
  → index += 1, loop
```

Everything is callback-chained through `SpeechOutputService.speak(_:locale:suspendRouter:completion:)`.

### 3.2 What exists but is never used

| Thing | Where | Status |
|---|---|---|
| `SessionPhase.dialogue`, `.quiz` | `SessionViewModel.swift:32-33` | Declared, never assigned. `currentPhase` is set to `.warmup` at line 72 and never changes. |
| `Lesson.dialogue` | `Lesson.swift:8` | Decoded, populated in 25/26 lessons, never read by any ViewModel. |
| `Phrase.practiceItems` | `Phrase.swift:25` | Decoded, 119 phrases carry them, never read. |
| `Lesson.practiceItems` (lesson-level) | `Lesson.swift:9` | Decoded, **not present in any content file**. Ignore it; all real practice items are per-phrase. |
| `DialogueTurn.hints` | `DialogueScenario.swift:13` | 2-3 acceptable phrasings per learner turn, 100 occurrences across 25 files. Never read. |
| `DialogueTurn.expectedIntent` | `DialogueScenario.swift:12` | Machine tokens like `"greeting_response"`. Per `DESIGN_DOC.md:227-228` these are scripted data only, with no runtime intent matching. **We keep it that way** — this plan never interprets `expectedIntent`. |
| `SessionViewModel.modelContext` / `.userProgress` | `SessionViewModel.swift:58-59` | Declared. `modelContext` is assigned from an init parameter that no caller passes. `userProgress` is **never assigned at all** and never read. |
| `UserProgress.recordPhrase` / `.phraseProgress(for:)` / `PhraseProgress.isDue` | `UserProgress.swift:37-60, 89-91` | Fully implemented SRS (spaced-repetition system — a scheduler that shows an item again after a delay that grows each time you get it right). **Nothing in the app calls any of it.** |
| `PronunciationEvaluator.getFeedback` / `FeedbackResult` | `PronunciationEvaluator.swift:51-65, 106-142` | Implemented with 4 fixed strings. `SessionViewModel` calls the raw `evaluate` instead and ignores `getFeedback` entirely. |

### 3.3 Content inventory (verify this yourself before starting)

- 26 lesson files: `A1/A1-L1..L2`, `A2/A2-L1..L5`, `B1/B1-L1..L5`, `B2/B2-L1..L5`, `C1/C1-L1..L5`, `C2/C2-L1..L4`, plus `es/manifest.json`.
- **25 of 26 have a `dialogue` block. `A1/A1-L2.json` has none**, and has no `practiceItems`, no `vocabularyIntro`, no `syllables` — it's the bare-schema lesson (`CurriculumLoaderTests.testA1L2BackwardCompatibility` asserts exactly this). Every new code path must degrade gracefully to "skip this phase" when its data is absent. Do not assume 26/26.
- Dialogue shape is consistent: alternating `npc` / `learner` turns, 4 turns typical. `npc` turns have `line` + `native`; `learner` turns have `expectedIntent` + `hints` and **no spoken content of any kind**. See §5.2 — this is a real gap for an audio-only app.

### 3.4 Three latent bugs you will hit

Fix these as part of the work; they are prerequisites, not optional cleanup.

**Bug A — `Phrase.id` is not stable.** `Phrase.init(from:)` assigns `self.id = UUID()` (`Phrase.swift:61`), a *fresh* UUID on every decode. `id` is excluded from `CodingKeys` and is not persisted. It is fine as an in-session dictionary key (that's how `phraseScores` uses it, `SessionViewModel.swift:57`) but it is **useless as an SRS key** — restart the app and every phrase looks brand new. We need a stable string key. See §4.1.

**Bug B — `recordPhrase` never advances `nextReviewDate`.** `UserProgress.recordPhrase` (`UserProgress.swift:37-56`) duplicates the interval math inline instead of calling `PhraseProgress.updateInterval(correct:)` (`UserProgress.swift:93-100`), which is the only place `nextReviewDate` is assigned. Result: `nextReviewDate` stays at its `init` value of `Date()`, so `isDue` (`UserProgress.swift:89-91`) is permanently `true` for everything. Any scheduling built on top of this is a no-op until it's fixed.

**Bug C — `SessionViewModel` never receives a `ModelContext`.** `SessionView.swift:26` constructs `SessionViewModel()` with no arguments even though the view has `@Environment(\.modelContext)` at line 13. Without this wiring, nothing can be persisted.

---

## 4. Target architecture

### Design rule for everything below

> **Pure decision logic goes in `VoiceLingoCore`. Audio side effects stay in `SessionViewModel`.**

This isn't stylistic. `SpeechOutputService` and `SpeechRecognitionService` are both wrapped in `#if os(iOS)` and the SwiftPM test target builds for macOS — so anything in Core that imports `AVFoundation` or `Speech` cannot be unit-tested. The new runners are therefore **pure state machines that return "what should happen next" as data**, and `SessionViewModel` is the dumb executor that turns that data into `speak()` and `recognize()` calls. That gives us full test coverage of the interesting logic with zero audio hardware.

### 4.1 Stable phrase keys

**File: `VoiceLingoCore/Sources/VoiceLingoCore/Models/Phrase.swift`** (append an extension; do not touch the existing `id`).

```swift
public extension Phrase {
    /// A stable, persistence-safe identifier for this phrase.
    ///
    /// `Phrase.id` is a fresh UUID generated at decode time and is NOT stable across app
    /// launches — it must never be used as an SRS key. This key is derived from the lesson
    /// it belongs to plus the normalized target text, both of which are stable content.
    func progressKey(inLesson lessonId: String) -> String {
        let normalizedTarget = target
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(lessonId)#\(normalizedTarget)"
    }
}
```

Note `Locale(identifier: "en_US_POSIX")` rather than `.current`: diacritic folding under `.current` is device-locale dependent, which would make persisted keys differ between users. (The existing `PronunciationEvaluator.normalize` uses `.current` — §4.2 changes that too.)

### 4.2 Generalizing `PronunciationEvaluator` to multiple candidates

**File: `VoiceLingoCore/Sources/VoiceLingoCore/Services/PronunciationEvaluator.swift`** (modify).

Today `evaluate` compares recognized speech against exactly one `target` (`PronunciationEvaluator.swift:17-27`). Dialogue turns carry a `hints` array of 2-3 acceptable phrasings, so we need "does the recognized text match *any* of these?".

Levenshtein distance = edit-distance string similarity: the minimum number of single-character insertions, deletions, or substitutions needed to turn one string into the other. `"dias"` → `"días"` is distance 1.

Add to the class:

```swift
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
```

Then rewrite the existing single-target method to delegate, so there is exactly one matching implementation:

```swift
    public func evaluate(recognized: String, target: String) -> Bool {
        evaluate(recognized: recognized, candidates: [target], allowSubstring: false)
    }
```

Also update `normalize` (currently `PronunciationEvaluator.swift:67-72`) to strip punctuation and collapse internal whitespace:

```swift
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
```

Why: Spanish content is full of `¿ ¡ ? , .` which the recognizer never emits. Today `"¿Cómo estás?"` normalizes to `"¿como estas?"`, so a perfect answer already burns 2 of its 2-edit budget on punctuation. Verify after this change that all existing `PronunciationEvaluatorTests` still pass — they should; the false-assertions in that file ("Hello world", "Adiós", "Bueno") are far outside any threshold, and `testSpecialCharactersHandling` (line 167) only gets safer.

**Do not change** `getAccuracy`, `getFeedback`, `FeedbackResult`, `loadPhrases`, or `getPhoneticHint`. `FeedbackResult.feedbackMessage`'s 4 fixed strings are superseded by §4.3 but are still referenced by tests — leave them alone.

### 4.3 The deterministic speech-variation layer (`SpeechComposer`)

NLG = natural-language generation. This is "NLG" only in the 1970s sense: **template selection and slot filling.** There is no model. The composer can only emit strings that already exist in a JSON file, optionally with `{placeholder}` tokens replaced by values from other lists in the same JSON file.

**New file: `VoiceLingoCore/Sources/VoiceLingoCore/Models/SpeechBank.swift`**

```swift
import Foundation

/// A category of thing the tutor says. Each act maps to a pool of pre-written variants.
public enum SpeechAct: String, Codable, Sendable, CaseIterable {
    case sessionOpen        // "Alright, fifteen minutes. Let's go."
    case sessionClose       // "That's time. Same again tomorrow?"
    case praise             // said on a correct answer
    case gentleCorrection   // said on an incorrect answer
    case transition         // moving between phrases / phases
    case timeRemaining      // "We're about ten minutes in."
    case revealAnswer       // "Here's how it goes:"
    case dialogueIntro      // framing before the roleplay
    case learnerTurnCue     // generic "your turn" for a dialogue turn with no authored cue
    case echoResponse       // acknowledges an open answer; see §4.4
    case quizIntro          // framing before the recall check
}

/// One pre-written, human-reviewed line.
public struct SpeechVariant: Codable, Sendable, Equatable {
    /// The line. May contain `{slot}` placeholders.
    public let text: String
    /// BCP-47 locale for TTS, e.g. "en-US" or "es-MX". nil = the language's `voiceLocale`.
    public let locale: String?

    public init(text: String, locale: String? = nil) {
        self.text = text
        self.locale = locale
    }
}

/// A rendered, ready-to-speak line.
public struct SpeechLine: Equatable, Sendable {
    public let text: String
    public let locale: String?
}

/// The per-language bank of pre-authored tutor lines and slot values.
/// Loaded from `Content/{lang}/speech-bank.json`.
public struct SpeechBank: Codable, Sendable {
    public let language: String
    /// SpeechAct.rawValue -> variants.
    public let pools: [String: [SpeechVariant]]
    /// Slot name -> the complete set of allowed values, e.g. "city" -> ["México", "Chicago"].
    /// Every value here is human-reviewed content. Nothing else may ever fill a slot,
    /// with the single audited exception of `{recognized}` (see SpeechComposer.echo).
    public let slots: [String: [String]]

    public init(language: String,
                pools: [String: [SpeechVariant]],
                slots: [String: [String]] = [:]) {
        self.language = language
        self.pools = pools
        self.slots = slots
    }
}
```

**New file: `VoiceLingoCore/Sources/VoiceLingoCore/Services/SpeechComposer.swift`**

```swift
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
```

**Where it lives at runtime:** `SessionViewModel` owns one `SpeechComposer` per session, built from the bank loaded by `CurriculumLoader` (§4.6). If the bank file is missing or fails to decode, `line(for:)` returns nil everywhere and every call site falls back to today's hardcoded string. **No call site may crash or go silent when the composer returns nil.**

### 4.4 STT echo — the one audited exception, and its trade-off

For open questions with no single correct answer ("¿De dónde eres?"), validation is meaningless — there are ~200 countries and unlimited cities. The manuscript's tutor just responds warmly and moves on.

The mechanism: take the recognizer's output verbatim and splice it into a pre-authored carrier via the `{recognized}` slot. Nothing is validated, parsed, corrected, or conjugated.

```swift
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
```

**The trade-off, stated plainly.** If the learner says something ungrammatical, the app repeats it. A carrier like `"¡Qué bien, {recognized}!"` arguably frames the learner's words as endorsed. Two mitigations, both required:

1. **Author echo carriers as acknowledgements, not models.** `"¡Qué bien! {recognized}. Muy bien."` re-states the learner as *their* utterance. Avoid carriers that grammatically absorb the echo into a tutor sentence (`"Ah, eres de {recognized}"`), because then the tutor is speaking a sentence whose grammar depends on unreviewed input.
2. **Only use echo on turns explicitly flagged `openResponse: true`** (§5.2). Never on a drill, never as a fallback for a failed match.

This does not violate §2.2: the app is not *generating* Spanish, it is quoting the user. But it's the one place worth a second reviewer's eyes.

### 4.5 `DialogueRunner` — the dialogue phase as a finite-state script

**New file: `VoiceLingoCore/Sources/VoiceLingoCore/Services/DialogueRunner.swift`**

This is a scripted branch-free walk through `DialogueScenario.turns`. `npc` turns are TTS playback of the authored `line`. `learner` turns are multi-candidate fuzzy matching against the authored `hints` set. There is **no dialogue state, no intent classification, no branching on what the learner said** — the script is linear and always completes.

```swift
import Foundation

/// One instruction for the ViewModel to carry out. Pure data; no audio here.
public enum DialogueStep: Equatable, Sendable {
    /// Speak the English scenario framing, e.g. "You run into a coworker in the morning."
    case introduceScenario(String)
    /// Speak an NPC line in the target language, optionally followed by its native gloss.
    case npcLine(text: String, native: String?)
    /// Prompt the learner and open the mic.
    /// - candidates: the finite acceptable-answer set for this turn (may be empty for open turns).
    /// - cue: English instruction for what to say, if the content author supplied one.
    /// - isOpen: true => do not evaluate; echo the answer instead (see SpeechComposer.echo).
    case awaitLearner(turnIndex: Int, candidates: [String], cue: String?, isOpen: Bool)
    /// Script exhausted.
    case finished
}

/// What to do after the learner spoke on a `learner` turn.
public enum DialogueOutcome: Equatable, Sendable {
    /// Matched one of the authored hints.
    case matched(candidate: String)
    /// Open turn — nothing to validate; echo `recognized` back.
    case openAccepted(recognized: String)
    /// Didn't match; attempts remain. Speak `modelAnswer` slowly, then re-open the mic.
    case retry(attemptsRemaining: Int, modelAnswer: String)
    /// Out of attempts. Speak `modelAnswer` and CONTINUE — a dialogue never dead-ends.
    case movedOn(modelAnswer: String)
}

/// Walks a pre-authored dialogue script. Deterministic and side-effect free.
///
/// Scope note: this performs multi-candidate fuzzy string matching over a closed,
/// human-authored answer set. It does not understand language and cannot accept any
/// answer that an author did not write down.
public final class DialogueRunner {

    public let scenario: DialogueScenario
    private let maxAttemptsPerTurn: Int
    private let evaluator: PronunciationEvaluator

    private var cursor: Int = -1          // -1 = not started
    private var attemptsThisTurn: Int = 0

    public private(set) var learnerTurnsAttempted: Int = 0
    public private(set) var learnerTurnsMatched: Int = 0

    public init(scenario: DialogueScenario,
                evaluator: PronunciationEvaluator = .shared,
                maxAttemptsPerTurn: Int = 2) {
        self.scenario = scenario
        self.evaluator = evaluator
        self.maxAttemptsPerTurn = maxAttemptsPerTurn
    }

    /// First step: the scenario framing.
    public func start() -> DialogueStep {
        cursor = -1
        return .introduceScenario(scenario.scenario)
    }

    /// Advance to the next turn. Call after the previous step's audio has finished
    /// (and, for a learner turn, after `submit` returned `.matched` / `.openAccepted` / `.movedOn`).
    public func advance() -> DialogueStep {
        cursor += 1
        attemptsThisTurn = 0
        guard cursor < scenario.turns.count else { return .finished }

        let turn = scenario.turns[cursor]
        switch turn.speaker {
        case .npc:
            // A malformed npc turn with no line would stall the script — skip it.
            guard let line = turn.line, !line.isEmpty else { return advance() }
            return .npcLine(text: line, native: turn.native)
        case .learner:
            return .awaitLearner(
                turnIndex: cursor,
                candidates: turn.hints ?? [],
                cue: turn.cue,
                isOpen: turn.openResponse ?? false
            )
        }
    }

    /// Grade the learner's speech for the current turn.
    public func submit(recognized: String) -> DialogueOutcome {
        guard cursor >= 0, cursor < scenario.turns.count else {
            return .movedOn(modelAnswer: "")
        }
        let turn = scenario.turns[cursor]
        let candidates = turn.hints ?? []

        if turn.openResponse == true || candidates.isEmpty {
            learnerTurnsAttempted += 1
            learnerTurnsMatched += 1
            return .openAccepted(recognized: recognized)
        }

        attemptsThisTurn += 1
        // allowSubstring: conversational answers carry filler the drill path wouldn't tolerate.
        let matched = evaluator.evaluate(recognized: recognized,
                                         candidates: candidates,
                                         allowSubstring: true)
        if matched {
            learnerTurnsAttempted += 1
            learnerTurnsMatched += 1
            let best = evaluator.bestMatch(recognized: recognized,
                                           candidates: candidates,
                                           allowSubstring: true)
            return .matched(candidate: best?.candidate ?? candidates[0])
        }

        // First authored hint is the canonical model answer.
        let modelAnswer = candidates[0]
        if attemptsThisTurn < maxAttemptsPerTurn {
            return .retry(attemptsRemaining: maxAttemptsPerTurn - attemptsThisTurn,
                          modelAnswer: modelAnswer)
        }
        learnerTurnsAttempted += 1
        return .movedOn(modelAnswer: modelAnswer)
    }

    /// 0.0-1.0. Used for the session summary; not for level unlocking.
    public var accuracy: Double {
        guard learnerTurnsAttempted > 0 else { return 0 }
        return Double(learnerTurnsMatched) / Double(learnerTurnsAttempted)
    }
}
```

Two deliberate behaviours, both drawn from `data/a1-day2-lesson.txt`'s design notes:

- **`maxAttemptsPerTurn` is 2, not 3.** Drills are for accuracy; a conversation that stops twice on the same line stops being a conversation.
- **`.movedOn` always continues.** "Correction happens by continuing the conversation and letting the correct form resurface naturally, not by stopping to say 'wrong, try again.'" The script never dead-ends.

### 4.6 `QuizRunner` — retrieval practice on top of the existing SRS

**New file: `VoiceLingoCore/Sources/VoiceLingoCore/Services/QuizRunner.swift`**

The quiz phase is a *recall* check, not more echoing: the app poses `practiceItem.prompt` and the learner must produce `practiceItem.answer` from memory, with no model utterance beforehand. It runs after the phrase has already been introduced in the new-content phase.

Ordering is driven by the **existing** `UserProgress`/`PhraseProgress` SRS (`UserProgress.swift`). We are not inventing a scheduler. To keep the runner testable without a SwiftData container, it takes a plain snapshot struct rather than the `@Model` types; `SessionViewModel` does the mapping.

```swift
import Foundation

/// The three authored practice types. Values match the `type` strings in lesson JSON.
public enum PracticeItemType: String, Sendable {
    case translation
    case fillBlank
    case qa
}

/// Which language a prompt should be spoken in. Derived, not authored.
public enum PromptLocaleKind: Sendable, Equatable {
    case native   // English — speak with "en-US"
    case target   // Spanish — speak with the manifest voiceLocale
}

/// A quiz question, resolved and ready for the ViewModel to speak.
public struct QuizItem: Equatable, Sendable {
    public let phraseKey: String        // Phrase.progressKey(inLesson:)
    public let phraseTarget: String     // for the reveal
    public let type: PracticeItemType
    /// Prompt text with `___` already replaced by a spoken-friendly pause.
    public let spokenPrompt: String
    public let promptLocale: PromptLocaleKind
    public let answer: String
}

/// A read-only snapshot of one phrase's SRS state. Mapped from PhraseProgress by the caller
/// so this type stays free of SwiftData and testable on macOS.
public struct ReviewState: Sendable, Equatable {
    public let phraseKey: String
    public let correctCount: Int
    public let incorrectCount: Int
    public let isDue: Bool

    public init(phraseKey: String, correctCount: Int, incorrectCount: Int, isDue: Bool) {
        self.phraseKey = phraseKey
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.isDue = isDue
    }
}

public enum QuizRunner {

    /// Builds the quiz for a lesson from the phrases already introduced this session.
    ///
    /// Ordering is fully deterministic (no randomness) so the same inputs always produce the
    /// same quiz — required by the "fully deterministic" policy and needed for stable tests.
    ///
    /// Priority order:
    ///   1. Phrases the learner has previously got wrong more often than right ("struggling")
    ///   2. Phrases never quizzed before
    ///   3. Phrases due for review
    ///   4. Everything else
    /// Ties break on the phrase's position in the lesson, so ordering is stable.
    public static func buildQuiz(
        phrases: [Phrase],
        lessonId: String,
        reviewStates: [String: ReviewState],
        maxItems: Int = 5
    ) -> [QuizItem] {

        struct Ranked { let priority: Int; let order: Int; let item: QuizItem }

        var ranked: [Ranked] = []
        for (order, phrase) in phrases.enumerated() {
            guard let practiceItems = phrase.practiceItems, !practiceItems.isEmpty else { continue }
            let key = phrase.progressKey(inLesson: lessonId)
            let state = reviewStates[key]

            let priority: Int
            if let s = state, s.incorrectCount > s.correctCount { priority = 0 }
            else if state == nil                                 { priority = 1 }
            else if state?.isDue == true                          { priority = 2 }
            else                                                  { priority = 3 }

            // Rotate item type by how many times this phrase has been answered correctly,
            // so a repeat review gets a DIFFERENT question, not the same one again.
            let rotation = (state?.correctCount ?? 0) % practiceItems.count
            let source = practiceItems[rotation]
            guard let item = makeItem(from: source, phraseKey: key, phraseTarget: phrase.target)
            else { continue }

            ranked.append(Ranked(priority: priority, order: order, item: item))
        }

        return ranked
            .sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.order < $1.order }
            .prefix(maxItems)
            .map(\.item)
    }

    /// Converts an authored PracticeItem into something speakable.
    static func makeItem(from source: PracticeItem,
                         phraseKey: String,
                         phraseTarget: String) -> QuizItem? {
        guard let type = PracticeItemType(rawValue: source.type) else { return nil }

        // "Buenos ___, señor." read literally by TTS becomes "underscore underscore underscore".
        // Replace the blank with an ellipsis, which AVSpeechSynthesizer renders as a pause.
        let spoken = source.prompt.replacingOccurrences(of: "___", with: "…")

        // Prompt language is derived from the authored type, not stored per item:
        //   translation -> English prompt ("Translate: Good morning")
        //   fillBlank   -> target-language prompt with a gap
        //   qa          -> target-language question
        let locale: PromptLocaleKind = (type == .translation) ? .native : .target

        return QuizItem(phraseKey: phraseKey,
                        phraseTarget: phraseTarget,
                        type: type,
                        spokenPrompt: spoken,
                        promptLocale: locale,
                        answer: source.answer)
    }

    /// Grades one answer. `allowSubstring` is on because a learner answering a question
    /// naturally wraps the answer in filler ("pues, buenos días").
    public static func grade(recognized: String,
                             item: QuizItem,
                             evaluator: PronunciationEvaluator = .shared) -> Bool {
        evaluator.evaluate(recognized: recognized,
                           candidates: [item.answer],
                           allowSubstring: true)
    }
}
```

Verify the `promptLocale` mapping against real content before trusting it: in `A1-L1.json` the `translation` prompt is `"Translate: Good morning"` (English), while `fillBlank` is `"Buenos ___, señor."` and `qa` is `"¿Qué dices a las 8 de la mañana?"` (both Spanish). If you find a lesson that breaks the pattern, fix the content file — do not add a heuristic that guesses the language of a string.

### 4.7 Loading the speech bank

**File: `VoiceLingoCore/Sources/VoiceLingoCore/Services/CurriculumLoader.swift`** (modify).

Add the bank to the existing loader rather than writing a new one — the SwiftPM resource-flattening fallback at lines 136-155 is fiddly and shouldn't be duplicated. Mirror `loadManifestFromFile` exactly, including the "decode then verify `language` matches" trick, because `speech-bank.json` is language-scoped but flattens to the bundle root.

```swift
    private var speechBankCache: [String: SpeechBank] = [:]

    /// Loads `Content/{language}/speech-bank.json`, or nil if the language has no bank.
    ///
    /// Returns nil rather than throwing: the bank is a presentation nicety, and a missing or
    /// malformed bank must degrade to the app's built-in fallback strings, never to a crash
    /// or a silent session.
    public func loadSpeechBank(for language: String) -> SpeechBank? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = speechBankCache[language] { return cached }
        guard let bank = try? loadSpeechBankFromFile(language: language) else { return nil }
        speechBankCache[language] = bank
        return bank
    }
```

Remember to clear `speechBankCache` in both `clearCache()` (line 96) and `clearCache(for:)` (line 105).

### 4.8 `SessionViewModel` state-machine changes

**File: `VoiceLingo/VoiceLingo/ViewModels/SessionViewModel.swift`** (modify).

`SessionState` (line 19-27) needs **no new cases** — dialogue and quiz reuse `.speakingPrompt` / `.awaitingResponse` / `.evaluating` / `.feedback`. Only `currentPhase` changes.

New target flow:

```
startSession
  → currentPhase = .newContent      (currently hardcoded to .warmup and never updated)
  → existing phrase loop
  → beginDialoguePhase()            ← replaces completeSession() at line 135
      no lesson.dialogue?  → beginQuizPhase()
  → beginQuizPhase()
      quiz items empty?    → beginSummary()
  → beginSummary() → completeSession()
```

New stored properties:

```swift
    private var composer: SpeechComposer?
    private var dialogueRunner: DialogueRunner?
    private var quizItems: [QuizItem] = []
    private var quizIndex: Int = 0
    private var quizAttempts: Int = 0
    private var sessionStartedAt: Date = Date()
    private var currentLessonId: String = ""
    private var didAnnounceTimeRemaining = false
```

**Speaking through the composer.** Add one helper and route every canned utterance through it:

```swift
    /// Speaks a varied line for `act`, falling back to `fallback` if the bank has nothing usable.
    /// Every call site MUST supply a fallback — a missing speech-bank must never mute the app.
    private func speakVaried(_ act: SpeechAct,
                             fallback: String,
                             fallbackLocale: String? = "en-US",
                             slots: [String: String] = [:],
                             completion: (@Sendable () -> Void)? = nil) {
        if let line = composer?.line(for: act, slots: slots) {
            sessionLog("[SPEAK] [\(act.rawValue)] \"\(line.text)\"")
            speechOutputService.speak(line.text, locale: line.locale ?? fallbackLocale,
                                      completion: completion)
        } else {
            sessionLog("[SPEAK] [\(act.rawValue)] (fallback) \"\(fallback)\"")
            speechOutputService.speak(fallback, locale: fallbackLocale, completion: completion)
        }
    }
```

Then replace the two hardcoded lines. In `provideFeedback` (line 274-296):

```swift
        if correct {
            statusMessage = "Correct!"
            sessionScore += 10
            speakVaried(.praise, fallback: "Correct! Well done.") { [weak self] in
                Task { @MainActor [weak self] in self?.speakExampleThenAdvance(phrase) }
            }
        } else {
            statusMessage = "Try again"
            speakVaried(.gentleCorrection, fallback: "Not quite. Try again.") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.speechOutputService.speakSlowly(phrase.target) { [weak self] in
                        Task { @MainActor [weak self] in self?.awaitUserResponse(for: phrase) }
                    }
                }
            }
        }
```

Same treatment for `revealAnswer` ("The answer is.", line 301) and `completeSession` (line 333).

**State-aware assembly.** In `explainThenSpeak` (line 149), skip the full lecture for a phrase the learner has already got right before — same fragments, different assembly decision, driven entirely by existing tracked state:

```swift
    private func explainThenSpeak(_ phrase: Phrase) {
        let key = phrase.progressKey(inLesson: currentLessonId)
        let timesCorrect = userProgress?.phraseProgress(for: key)?.correctCount ?? 0

        // Reviewing something you've already produced correctly? Skip the lecture, go to the drill.
        // Same content, different assembly — no new text is generated.
        guard timesCorrect == 0, let narrative = narrativeExplanationText(for: phrase) else {
            speakPronunciationBreakdown(phrase)
            return
        }
        currentState = .explaining
        statusMessage = "Let's learn this phrase"
        speechOutputService.speak(narrative, locale: "en-US") { [weak self] in
            Task { @MainActor [weak self] in self?.speakPronunciationBreakdown(phrase) }
        }
    }
```

**Recording progress.** In `evaluateResponse` (line 254), after computing `isCorrect`:

```swift
        let key = phrase.progressKey(inLesson: currentLessonId)
        userProgress?.recordPhrase(key, correct: isCorrect)
        try? modelContext?.save()
```

**The dialogue phase.** A step pump that translates `DialogueStep` values into audio:

```swift
    private func beginDialoguePhase() {
        guard let dialogue = currentLesson?.dialogue else {
            beginQuizPhase()
            return
        }
        currentPhase = .dialogue
        let runner = DialogueRunner(scenario: dialogue, evaluator: pronunciationEvaluator)
        dialogueRunner = runner
        statusMessage = "Conversation practice"

        speakVaried(.dialogueIntro, fallback: "Now let's put it together in a conversation.") {
            [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let runner = self.dialogueRunner else { return }
                self.perform(runner.start())
            }
        }
    }

    private func perform(_ step: DialogueStep) {
        guard let runner = dialogueRunner else { return }
        switch step {
        case .introduceScenario(let text):
            currentState = .speakingPrompt
            statusMessage = text
            speechOutputService.speak(text, locale: "en-US") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let r = self.dialogueRunner else { return }
                    self.perform(r.advance())
                }
            }

        case .npcLine(let text, let native):
            currentState = .speakingPrompt
            statusMessage = native ?? text
            speechOutputService.speak(text) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let r = self.dialogueRunner else { return }
                    self.perform(r.advance())
                }
            }

        case .awaitLearner(_, _, let cue, _):
            currentState = .awaitingResponse
            statusMessage = cue ?? "Your turn"
            let fallbackCue = cue ?? "Your turn. Respond in Spanish."
            speakVaried(.learnerTurnCue, fallback: fallbackCue) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    self.speechRecognitionService.recognize(timeout: 8.0) { text in
                        Task { @MainActor [weak self] in self?.handleDialogueSpeech(text) }
                    } onError: { _ in
                        Task { @MainActor [weak self] in self?.handleDialogueSpeech("") }
                    }
                }
            }

        case .finished:
            _ = runner   // silence unused warning in the empty branch
            beginQuizPhase()
        }
    }

    private func handleDialogueSpeech(_ recognized: String) {
        speechRecognitionService.stopRecognition()
        guard let runner = dialogueRunner else { return }
        currentState = .evaluating

        switch runner.submit(recognized: recognized) {
        case .matched:
            sessionScore += 10
            speakVaried(.praise, fallback: "Good.") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let r = self.dialogueRunner else { return }
                    self.perform(r.advance())
                }
            }

        case .openAccepted(let text):
            // No validation: splice the learner's own words into a pre-authored carrier.
            if let echo = composer?.echo(recognized: text) {
                speechOutputService.speak(echo.text, locale: echo.locale) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, let r = self.dialogueRunner else { return }
                        self.perform(r.advance())
                    }
                }
            } else {
                speakVaried(.praise, fallback: "Good.") { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, let r = self.dialogueRunner else { return }
                        self.perform(r.advance())
                    }
                }
            }

        case .retry(_, let modelAnswer):
            speakVaried(.gentleCorrection, fallback: "Try it like this.") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.speechOutputService.speakSlowly(modelAnswer) { [weak self] in
                        Task { @MainActor [weak self] in
                            // Re-open the mic on the SAME turn — do not advance.
                            guard let self, let r = self.dialogueRunner else { return }
                            self.perform(.awaitLearner(turnIndex: r.currentTurnIndexForRetry,
                                                       candidates: [], cue: nil, isOpen: false))
                        }
                    }
                }
            }

        case .movedOn(let modelAnswer):
            // Never dead-end: model the answer once and keep the conversation moving.
            speechOutputService.speakSlowly(modelAnswer) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let r = self.dialogueRunner else { return }
                    self.perform(r.advance())
                }
            }
        }
    }
```

> Note the `.retry` branch needs the runner to re-emit the current turn. Add a tiny accessor to `DialogueRunner` rather than reconstructing the step in the ViewModel:
> ```swift
> /// Re-emits the current learner turn without advancing the cursor. Used for retries.
> public func repeatCurrentTurn() -> DialogueStep {
>     guard cursor >= 0, cursor < scenario.turns.count else { return .finished }
>     let turn = scenario.turns[cursor]
>     return .awaitLearner(turnIndex: cursor, candidates: turn.hints ?? [],
>                          cue: turn.cue, isOpen: turn.openResponse ?? false)
> }
> ```
> and call `self.perform(r.repeatCurrentTurn())` in the `.retry` branch. Drop the `currentTurnIndexForRetry` sketch above.

**The quiz phase:**

```swift
    private func beginQuizPhase() {
        currentPhase = .quiz
        dialogueRunner = nil

        let states = (userProgress?.phraseHistory ?? []).reduce(into: [String: ReviewState]()) {
            dict, p in
            dict[p.phraseId] = ReviewState(phraseKey: p.phraseId,
                                           correctCount: p.correctCount,
                                           incorrectCount: p.incorrectCount,
                                           isDue: p.isDue)
        }
        quizItems = QuizRunner.buildQuiz(phrases: currentPhrases,
                                         lessonId: currentLessonId,
                                         reviewStates: states)
        quizIndex = 0
        guard !quizItems.isEmpty else { beginSummary(); return }

        announceTimeIfNeeded { [weak self] in
            Task { @MainActor [weak self] in
                self?.speakVaried(.quizIntro, fallback: "Quick check before we finish.") {
                    Task { @MainActor [weak self] in self?.askNextQuizItem() }
                }
            }
        }
    }

    private func askNextQuizItem() {
        guard quizIndex < quizItems.count else { beginSummary(); return }
        let item = quizItems[quizIndex]
        quizAttempts = 0
        currentState = .speakingPrompt
        statusMessage = item.spokenPrompt

        let locale: String? = (item.promptLocale == .native) ? "en-US" : nil
        speechOutputService.speak(item.spokenPrompt, locale: locale) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentState = .awaitingResponse
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.speechRecognitionService.recognize(timeout: 8.0) { text in
                    Task { @MainActor [weak self] in self?.gradeQuizAnswer(text) }
                } onError: { _ in
                    Task { @MainActor [weak self] in self?.gradeQuizAnswer("") }
                }
            }
        }
    }

    private func gradeQuizAnswer(_ recognized: String) {
        speechRecognitionService.stopRecognition()
        guard quizIndex < quizItems.count else { beginSummary(); return }
        let item = quizItems[quizIndex]
        quizAttempts += 1
        currentState = .evaluating

        let correct = QuizRunner.grade(recognized: recognized, item: item,
                                       evaluator: pronunciationEvaluator)
        if correct {
            sessionScore += 10
            userProgress?.recordPhrase(item.phraseKey, correct: true)
            try? modelContext?.save()
            speakVaried(.praise, fallback: "Correct.") { [weak self] in
                Task { @MainActor [weak self] in
                    self?.quizIndex += 1
                    self?.askNextQuizItem()
                }
            }
        } else if quizAttempts < 2 {
            speakVaried(.gentleCorrection, fallback: "Not quite — once more.") { [weak self] in
                Task { @MainActor [weak self] in self?.askNextQuizItem2ndAttempt() }
            }
        } else {
            userProgress?.recordPhrase(item.phraseKey, correct: false)
            try? modelContext?.save()
            speakVaried(.revealAnswer, fallback: "The answer is:") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.speechOutputService.speakSlowly(item.answer) { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.quizIndex += 1
                            self?.askNextQuizItem()
                        }
                    }
                }
            }
        }
    }
```

(`askNextQuizItem2ndAttempt` is `askNextQuizItem` without resetting `quizAttempts` — factor the shared body into `askQuizItem(resettingAttempts:)`.)

**Time-remaining announcement** — the manuscript's "we're at about ten minutes":

```swift
    private func announceTimeIfNeeded(_ completion: @escaping @Sendable () -> Void) {
        let elapsedMinutes = Int(Date().timeIntervalSince(sessionStartedAt) / 60)
        guard !didAnnounceTimeRemaining, elapsedMinutes >= 10 else { completion(); return }
        didAnnounceTimeRemaining = true
        speakVaried(.timeRemaining,
                    fallback: "We're about \(elapsedMinutes) minutes in.",
                    slots: ["minutes": "\(elapsedMinutes)"],
                    completion: completion)
    }
```

**Summary + progress wiring:**

```swift
    private func beginSummary() {
        currentPhase = .summary
        completeSession()
    }

    /// Called by SessionView once SwiftData is available.
    public func attach(modelContext: ModelContext, userProgress: UserProgress?) {
        self.modelContext = modelContext
        self.userProgress = userProgress
    }
```

**File: `VoiceLingo/VoiceLingo/Views/SessionView.swift`** (modify) — currently constructs `SessionViewModel()` at line 26, so `modelContext` is always nil:

```swift
    @Query private var progressRecords: [UserProgress]
    // ...
    .onAppear {
        viewModel.attach(modelContext: modelContext,
                         userProgress: progressRecords.first { $0.languageCode == languageCode })
        viewModel.startSession(language: languageCode, levelId: levelId, lessonId: lessonId)
    }
```

Check the existing `.onAppear`/`.task` in `SessionView` and fold this in rather than adding a second one.

---

## 5. Content schema additions

Every addition here is **optional and additive**. The 26 existing lesson files must continue to decode unchanged, and `CurriculumLoaderTests.testAllManifestLessonsLoadAndAreUnique` must still pass without touching a single content file.

### 5.1 New file: `Content/es/speech-bank.json`

Sits next to `manifest.json`. Picked up automatically by `.process("Content/")` in `Package.swift` — no build-file change needed.

```json
{
  "language": "es",
  "pools": {
    "sessionOpen": [
      { "text": "Alright — fifteen minutes, let's build on what you've got.", "locale": "en-US" },
      { "text": "Good to see you. Short one today, same as always.", "locale": "en-US" },
      { "text": "Let's get into it. Fifteen minutes, one small piece at a time.", "locale": "en-US" },
      { "text": "Ready when you are. We'll keep it short.", "locale": "en-US" }
    ],
    "praise": [
      { "text": "Exacto.", "locale": "es-MX" },
      { "text": "Muy bien.", "locale": "es-MX" },
      { "text": "Perfecto.", "locale": "es-MX" },
      { "text": "That's it — clean.", "locale": "en-US" },
      { "text": "Yep, that's the one.", "locale": "en-US" },
      { "text": "Bien. No hesitation on that.", "locale": "en-US" }
    ],
    "gentleCorrection": [
      { "text": "Close — listen once more.", "locale": "en-US" },
      { "text": "Almost. Here it is again.", "locale": "en-US" },
      { "text": "Not quite — let's hear it one more time.", "locale": "en-US" },
      { "text": "You're near it. Try again after me.", "locale": "en-US" },
      { "text": "Casi. Otra vez.", "locale": "es-MX" }
    ],
    "transition": [
      { "text": "Okay, next piece.", "locale": "en-US" },
      { "text": "Good. Moving on.", "locale": "en-US" },
      { "text": "One more thing and then we put it together.", "locale": "en-US" },
      { "text": "Bueno — siguiente.", "locale": "es-MX" }
    ],
    "timeRemaining": [
      { "text": "We're about {minutes} minutes in.", "locale": "en-US" },
      { "text": "About {minutes} minutes down — let's do a quick check.", "locale": "en-US" },
      { "text": "Casi se acaba el tiempo. Around {minutes} minutes.", "locale": "en-US" }
    ],
    "revealAnswer": [
      { "text": "Here's how it goes:", "locale": "en-US" },
      { "text": "The answer is:", "locale": "en-US" },
      { "text": "Listen — this is the one:", "locale": "en-US" }
    ],
    "dialogueIntro": [
      { "text": "Let's put it together. Pretend we've never met.", "locale": "en-US" },
      { "text": "Full conversation now, start to finish.", "locale": "en-US" },
      { "text": "Okay — real exchange. I'll go first.", "locale": "en-US" }
    ],
    "learnerTurnCue": [
      { "text": "Your turn.", "locale": "en-US" },
      { "text": "Go ahead — answer me.", "locale": "en-US" },
      { "text": "You respond.", "locale": "en-US" }
    ],
    "echoResponse": [
      { "text": "¡Qué bien! {recognized}.", "locale": "es-MX" },
      { "text": "Bien — {recognized}.", "locale": "es-MX" },
      { "text": "Got it. {recognized}.", "locale": "en-US" }
    ],
    "quizIntro": [
      { "text": "Quick check before we finish.", "locale": "en-US" },
      { "text": "Let's see what stuck.", "locale": "en-US" },
      { "text": "Fast recap — no repeating after me this time.", "locale": "en-US" }
    ],
    "sessionClose": [
      { "text": "Bien hecho. Same time tomorrow?", "locale": "en-US" },
      { "text": "That's time. Say one of these to a real person this week.", "locale": "en-US" },
      { "text": "Perfecto. Tomorrow we build on this.", "locale": "en-US" }
    ]
  },
  "slots": {
    "name": ["Marisol", "Roberto", "Alejandra", "Diego", "Lucía"],
    "city": ["México", "Chicago", "Los Ángeles", "Madrid", "Bogotá"],
    "timeOfDay": ["Buenos días", "Buenas tardes", "Buenas noches"]
  }
}
```

**Authoring rules for this file, to be enforced in code review:**

1. 4-6 variants per pool. Fewer than 3 defeats the purpose; more than ~8 is unmaintainable.
2. Every Spanish variant must be reviewed by a Spanish speaker as a complete sentence. Fragments that only make sense when concatenated with something else are forbidden.
3. Slot values in `slots` are exhaustive whitelists. A reviewer must be able to read the template and the list side by side and confirm every one of the N resulting sentences is correct.
4. `{recognized}` is the only slot filled from runtime data, and it may only appear in the `echoResponse` pool.

### 5.2 Optional additive fields on `DialogueTurn`

**File: `VoiceLingoCore/Sources/VoiceLingoCore/Models/DialogueScenario.swift`** (modify).

Today a `learner` turn carries only `expectedIntent` (a machine token like `"greeting_response"` — unspeakable) and `hints`. **In an audio-only app the learner has no idea what they're supposed to say.** Two additive fields close that:

```swift
public struct DialogueTurn: Codable, Sendable {
    public let speaker: Speaker
    public let line: String?
    public let native: String?
    public let expectedIntent: String?
    public let hints: [String]?

    /// Spoken English instruction for a learner turn, e.g. "Tell me you're doing well."
    /// Optional: falls back to a generic cue from the speech bank.
    public let cue: String?

    /// If true this turn has no single correct answer (e.g. "¿De dónde eres?").
    /// The app will NOT evaluate the response — it echoes it back verbatim inside a
    /// pre-authored carrier line. Defaults to false when absent.
    public let openResponse: Bool?

    public init(speaker: Speaker, line: String? = nil, native: String? = nil,
                expectedIntent: String? = nil, hints: [String]? = nil,
                cue: String? = nil, openResponse: Bool? = nil) {
        self.speaker = speaker
        self.line = line
        self.native = native
        self.expectedIntent = expectedIntent
        self.hints = hints
        self.cue = cue
        self.openResponse = openResponse
    }
}
```

`DialogueTurn` uses the synthesized `Codable` conformance, so optional properties decode as `nil` when absent — the 25 existing dialogue blocks keep working untouched. **Do not add a custom `init(from:)`.**

Content authoring (separate, parallelizable task) then upgrades lesson files like this — note this file still decodes fine before the content change lands:

```json
{
  "speaker": "learner",
  "expectedIntent": "greeting_response",
  "cue": "Tell me you're doing well, and ask me back.",
  "hints": ["Estoy bien", "Estoy bien, gracias", "Estoy bien, gracias. ¿Y tú?"]
},
{
  "speaker": "npc",
  "line": "¿De dónde eres?",
  "native": "Where are you from?"
},
{
  "speaker": "learner",
  "expectedIntent": "state_origin",
  "cue": "Say where you're from — 'soy de', then your city.",
  "openResponse": true,
  "hints": ["Soy de Chicago"]
}
```

### 5.3 Explicitly NOT changing

- `manifest.json` — untouched.
- Any of the 26 lesson files — untouched by the code work. Content enrichment (`cue`, `openResponse`) is a follow-on task with its own review.
- `Package.swift` — `.process("Content/")` already globs new files.
- `Lesson.practiceItems` (lesson-level) — remains unread. Don't build on it.

---

## 6. Step-by-step implementation plan

Each step is independently buildable and testable. **Do not start step N+1 until step N's verification passes.** Run `swift test` from `/Users/chester.kim/workspace/trashcan/voice-lingo/VoiceLingoCore` after every Core step; build the iOS app in Xcode after every app-target step.

Tier tags route the work: `[junior]` = mechanical, 1-2 files; `[senior]` = multi-file or risk-bearing.

---

**Step 1 — Fix the SRS scheduling bug.** `[junior]`
File: `VoiceLingoCore/Sources/VoiceLingoCore/Models/UserProgress.swift`.
In `recordPhrase` (lines 37-56), delete the inline `progress.interval *= 2` / `progress.interval = 1` lines and call `progress.updateInterval(correct: correct)` instead. Keep the `correctCount` / `incorrectCount` / `totalXP` / `lastAttempt` updates exactly as they are.
**Verify:** new test — record a correct answer, assert `phraseProgress(for:)?.nextReviewDate` is at least 1 day in the future and `isDue == false`. This test fails before the change and passes after.

**Step 2 — Add the stable phrase key.** `[junior]`
File: `VoiceLingoCore/Sources/VoiceLingoCore/Models/Phrase.swift`. Add the `progressKey(inLesson:)` extension from §4.1. Do not modify the existing `id`, `CodingKeys`, `init(from:)`, or `encode(to:)`.
**Verify:** new test — decode `A1-L1` twice via `CurriculumLoader` (calling `clearCache()` between) and assert the first phrase's `progressKey(inLesson: "A1-L1")` is identical both times, while its `id` is not.

**Step 3 — Generalize `PronunciationEvaluator`.** `[senior]`
File: `VoiceLingoCore/Sources/VoiceLingoCore/Services/PronunciationEvaluator.swift`. Add `CandidateMatch`, `bestMatch(recognized:candidates:allowSubstring:)`, `evaluate(recognized:candidates:allowSubstring:)`, `threshold(forLength:)`; rewrite the single-target `evaluate` to delegate; update `normalize` to strip punctuation, collapse whitespace, and use `en_US_POSIX`.
**Verify:** the entire existing `PronunciationEvaluatorTests` suite must still pass **with no edits to that file** — that's the regression gate. Then add the new tests from §7.1.

**Step 4 — Add the speech-bank models.** `[junior]`
New file: `VoiceLingoCore/Sources/VoiceLingoCore/Models/SpeechBank.swift` (§4.3). Types only, no logic.
**Verify:** `swift build` succeeds; a round-trip test encodes a hand-built `SpeechBank` and decodes it back to an equal value.

**Step 5 — Author the speech bank JSON.** `[junior]`
New file: `VoiceLingoCore/Sources/VoiceLingoCore/Content/es/speech-bank.json`. Use §5.1 verbatim as the starting point. Have the Spanish lines reviewed before merging.
**Verify:** `python3 -m json.tool` on the file parses; a test decodes it via `JSONDecoder` into `SpeechBank` and asserts every `SpeechAct` case has a non-empty pool.

**Step 6 — Load the speech bank.** `[senior]`
File: `VoiceLingoCore/Sources/VoiceLingoCore/Services/CurriculumLoader.swift`. Add `speechBankCache`, `loadSpeechBank(for:)`, and a private `loadSpeechBankFromFile` that mirrors `loadManifestFromFile` (lines 116-158) **including the flattened-bundle fallback and the `bank.language == language` verification**. Clear the new cache in both `clearCache()` and `clearCache(for:)`.
**Verify:** `loadSpeechBank(for: "es")` returns non-nil with populated pools; `loadSpeechBank(for: "xyz")` returns nil without throwing; caching and cache-clearing behave like the manifest equivalents.

**Step 7 — Build `SpeechComposer`.** `[senior]`
New file: `VoiceLingoCore/Sources/VoiceLingoCore/Services/SpeechComposer.swift` (§4.3 + §4.4). Pure Foundation — no `AVFoundation`, no `import Speech`, no `#if os(iOS)`.
**Verify:** the §7.2 tests, especially no-immediate-repeat and placeholder filtering.

**Step 8 — Add the optional `DialogueTurn` fields.** `[junior]`
File: `VoiceLingoCore/Sources/VoiceLingoCore/Models/DialogueScenario.swift`. Add `cue` and `openResponse` per §5.2, plus the two new `init` parameters with `nil` defaults.
**Verify:** `CurriculumLoaderTests.testLessonDialogue` and `testAllManifestLessonsLoadAndAreUnique` still pass with zero content edits, and a new test asserts `A1-L1`'s learner turn decodes with `cue == nil` and `openResponse == nil`.

**Step 9 — Build `DialogueRunner`.** `[senior]`
New file: `VoiceLingoCore/Sources/VoiceLingoCore/Services/DialogueRunner.swift` (§4.5), including `repeatCurrentTurn()`.
**Verify:** the §7.3 tests. Drive a full 4-turn `A1-L1` script end to end in a test with no audio at all.

**Step 10 — Build `QuizRunner`.** `[senior]`
New file: `VoiceLingoCore/Sources/VoiceLingoCore/Services/QuizRunner.swift` (§4.6).
**Verify:** the §7.4 tests — deterministic ordering, `___` replacement, type rotation, `maxItems` cap, and that a phrase with no `practiceItems` is skipped rather than crashing.

**Stop here and confirm all of `swift test` is green before touching the app target.** Everything above is testable headlessly; everything below needs a simulator.

**Step 11 — Wire `ModelContext` into `SessionViewModel`.** `[junior]`
Files: `VoiceLingo/VoiceLingo/ViewModels/SessionViewModel.swift` (add `attach(modelContext:userProgress:)`), `VoiceLingo/VoiceLingo/Views/SessionView.swift` (add `@Query private var progressRecords: [UserProgress]`, call `attach` before `startSession`).
**Verify:** run in the simulator, add a temporary `sessionLog("[PROGRESS] attached: \(userProgress != nil)")` in `startSession`, confirm it logs `true`. Remove the temporary log.

**Step 12 — Record phrase progress during the drill phase.** `[junior]`
File: `SessionViewModel.swift`. Store `currentLessonId` and `sessionStartedAt` in `startSession`; set `currentPhase = .newContent` there instead of `.warmup`. In `evaluateResponse` (line 254) call `userProgress?.recordPhrase(...)` + `modelContext?.save()` per §4.8.
**Verify:** complete a lesson in the simulator, force-quit, relaunch, start the same lesson — `phraseProgress(for:)?.correctCount` is non-zero. Log it to confirm.

**Step 13 — Route canned lines through `SpeechComposer`.** `[senior]`
File: `SessionViewModel.swift`. Build the composer in `startSession` from `curriculumLoader.loadSpeechBank(for: language)`; add `speakVaried`; replace the hardcoded strings at lines 281, 287, 301, 315, 333. Add the state-aware skip in `explainThenSpeak` per §4.8.
**Verify:** run a lesson twice in the simulator and read the `[SPEAK]` log lines — praise strings must vary and must never repeat back-to-back. Then temporarily rename `speech-bank.json` and re-run: the session must complete normally on fallback strings. Restore the filename.

**Step 14 — Activate the dialogue phase.** `[senior]`
File: `SessionViewModel.swift`. Change the guard at line 133-136 to call `beginDialoguePhase()` instead of `completeSession()`. Add `beginDialoguePhase`, `perform(_:)`, `handleDialogueSpeech(_:)` per §4.8.
**Verify:** run `A1-L1` in the simulator: after the last phrase, the scenario framing plays, NPC lines play in Spanish, the mic opens on learner turns, and the script always reaches `.finished` — including if you stay completely silent through every learner turn. Then run **`A1-L2`** (no dialogue block) and confirm it skips straight to the quiz phase without a crash or a hang. This second check is the one people forget.

**Step 15 — Activate the quiz phase.** `[senior]`
File: `SessionViewModel.swift`. Add `beginQuizPhase`, `askQuizItem(resettingAttempts:)`, `gradeQuizAnswer`, `announceTimeIfNeeded`, `beginSummary`. Point `.finished` in `perform(_:)` at `beginQuizPhase()`.
**Verify:** run `A1-L1`: after dialogue you get up to 5 recall questions, `fillBlank` prompts pause rather than saying "underscore", `translation` prompts are spoken in an English voice and the others in Spanish, and the session reaches `.sessionComplete`. Run `A1-L2` (no practice items) and confirm it skips straight to the summary.

**Step 16 — Update `DESIGN_DOC.md`.** `[junior]`
Document the speech bank under "Content Schema", the new `cue` / `openResponse` fields, and replace the now-false note at lines 227-228 ("there is no runtime intent-matching; this data is a placeholder for future evaluation logic") with an accurate description: `hints` is now the finite acceptable-answer set for multi-candidate fuzzy matching; `expectedIntent` remains unread by any code path. Move "Dialogue mode" out of "Future Scope" (line 330).
**Verify:** a reader who only has `DESIGN_DOC.md` can correctly predict what the app does.

---

## 7. Testing guidance

House style, from `CurriculumLoaderTests.swift` / `PronunciationEvaluatorTests.swift`: `import XCTest` + `@testable import VoiceLingoCore`, one `final class …Tests: XCTestCase`, `setUp`/`tearDown` for shared fixtures, `// MARK: -` section headers, and a descriptive message string on every assertion. Match it.

All new Core types must be testable on macOS: **no `AVFoundation`, no `Speech`, no `#if os(iOS)`** in `SpeechComposer`, `DialogueRunner`, or `QuizRunner`.

### 7.1 `PronunciationEvaluatorTests` (extend the existing file)

```swift
    // MARK: - Multi-Candidate Evaluation

    func testMatchesAnyCandidate() {
        let hints = ["Estoy bien", "Estoy bien, gracias"]
        XCTAssertTrue(evaluator.evaluate(recognized: "estoy bien gracias", candidates: hints),
                      "Should match the second candidate")
        XCTAssertTrue(evaluator.evaluate(recognized: "Estoy bien", candidates: hints),
                      "Should match the first candidate")
    }

    func testRejectsWhenNoCandidateMatches() {
        XCTAssertFalse(
            evaluator.evaluate(recognized: "buenas noches", candidates: ["Estoy bien", "Muy bien"]),
            "An answer unrelated to every candidate must be rejected")
    }

    func testEmptyCandidateListIsNeverAMatch() {
        XCTAssertFalse(evaluator.evaluate(recognized: "cualquier cosa", candidates: []),
                       "No candidates means nothing can be accepted")
        XCTAssertNil(evaluator.bestMatch(recognized: "hola", candidates: []),
                     "bestMatch must be nil for an empty candidate set")
    }

    func testBestMatchReturnsHighestScoringCandidate() {
        let match = evaluator.bestMatch(recognized: "estoy bien gracias",
                                        candidates: ["Muy bien", "Estoy bien, gracias"])
        XCTAssertEqual(match?.candidate, "Estoy bien, gracias",
                       "Should report the closest candidate, not the first")
        XCTAssertTrue(match?.isAcceptable ?? false)
    }

    func testAllowSubstringAcceptsConversationalFiller() {
        let hints = ["Estoy bien"]
        XCTAssertFalse(evaluator.evaluate(recognized: "pues estoy bien gracias profesora",
                                          candidates: hints, allowSubstring: false),
                       "Drill mode must not accept a padded answer")
        XCTAssertTrue(evaluator.evaluate(recognized: "pues estoy bien gracias profesora",
                                         candidates: hints, allowSubstring: true),
                      "Dialogue mode should accept the phrase inside natural filler")
    }

    func testLongAnswersGetAProportionalThreshold() {
        let hint = "Cuando era niño, vivía en un pueblo pequeño"
        XCTAssertTrue(evaluator.evaluate(recognized: "cuando era nino vivia en un publo pequeno",
                                         candidates: [hint]),
                      "A long dialogue line should tolerate more than two recognizer slips")
    }

    func testPunctuationIsIgnored() {
        XCTAssertTrue(evaluator.evaluate(recognized: "como estas", candidates: ["¿Cómo estás?"]),
                      "Spanish punctuation the recognizer never emits must not cost edit budget")
    }
```

### 7.2 New file: `VoiceLingoCore/Tests/VoiceLingoCoreTests/SpeechComposerTests.swift`

Inject a deterministic `randomIndex` so nothing is flaky.

```swift
import XCTest
@testable import VoiceLingoCore

final class SpeechComposerTests: XCTestCase {

    private func makeBank() -> SpeechBank {
        SpeechBank(
            language: "es",
            pools: [
                SpeechAct.praise.rawValue: [
                    SpeechVariant(text: "A", locale: "en-US"),
                    SpeechVariant(text: "B", locale: "en-US"),
                    SpeechVariant(text: "C", locale: "es-MX")
                ],
                SpeechAct.echoResponse.rawValue: [
                    SpeechVariant(text: "¡Qué bien, {recognized}!", locale: "es-MX")
                ],
                SpeechAct.timeRemaining.rawValue: [
                    SpeechVariant(text: "About {minutes} minutes in.", locale: "en-US"),
                    SpeechVariant(text: "Halfway there.", locale: "en-US")
                ]
            ],
            slots: ["city": ["México", "Chicago"]]
        )
    }

    // MARK: - Selection

    func testReturnsNilForAnEmptyOrMissingPool() {
        let composer = SpeechComposer(bank: SpeechBank(language: "es", pools: [:]))
        XCTAssertNil(composer.line(for: .praise),
                     "A missing pool must return nil so the caller can fall back")
    }

    func testNeverRepeatsTheSameVariantTwiceInARow() {
        // Force the RNG to always pick index 0; the no-repeat rule must break the tie.
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        let first = composer.line(for: .praise)?.text
        let second = composer.line(for: .praise)?.text
        XCTAssertEqual(first, "A")
        XCTAssertNotEqual(first, second, "Consecutive praise lines must differ")
    }

    func testSingleVariantPoolIsAllowedToRepeat() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertEqual(composer.line(for: .echoResponse, slots: ["recognized": "x"])?.text,
                       composer.line(for: .echoResponse, slots: ["recognized": "x"])?.text,
                       "A one-variant pool has no alternative and may repeat")
    }

    func testLocaleIsCarriedThrough() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 2 })
        XCTAssertEqual(composer.line(for: .praise)?.locale, "es-MX")
    }

    // MARK: - Slot filling

    func testSlotsAreFilled() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertEqual(composer.line(for: .timeRemaining, slots: ["minutes": "10"])?.text,
                       "About 10 minutes in.")
    }

    func testVariantsWithUnfillableSlotsAreExcluded() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        let line = composer.line(for: .timeRemaining)   // no "minutes" supplied
        XCTAssertEqual(line?.text, "Halfway there.",
                       "Should fall back to the variant that needs no slots")
        XCTAssertFalse(line?.text.contains("{") ?? true,
                       "A rendered line must never contain a leftover placeholder")
    }

    func testSlotValuesComeOnlyFromTheBank() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertTrue(["México", "Chicago"].contains(composer.slotValue("city") ?? ""))
        XCTAssertNil(composer.slotValue("undefinedSlot"),
                     "An unauthored slot must yield nothing, never an invented value")
    }

    // MARK: - STT echo

    func testEchoSplicesRecognizedTextVerbatim() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertEqual(composer.echo(recognized: "Soy de Chicago")?.text,
                       "¡Qué bien, Soy de Chicago!",
                       "Recognized text must be passed through unmodified")
    }

    func testEchoRejectsEmptyOrOverlongInput() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertNil(composer.echo(recognized: "   "))
        XCTAssertNil(composer.echo(recognized: String(repeating: "a", count: 200)))
    }
}
```

### 7.3 New file: `VoiceLingoCore/Tests/VoiceLingoCoreTests/DialogueRunnerTests.swift`

Cover: `start()` yields `.introduceScenario`; `advance()` yields `.npcLine` for npc turns and `.awaitLearner` with the authored `hints` for learner turns; `submit` with a matching hint returns `.matched`; a mismatch returns `.retry` first and `.movedOn` on the second attempt; `openResponse: true` returns `.openAccepted` regardless of input (including gibberish); the script always reaches `.finished`. Then an integration test over real content:

```swift
    func testWalksTheRealA1L1ScriptToCompletion() throws {
        let lesson = try CurriculumLoader.shared.loadLesson(language: "es",
                                                           levelId: "A1", lessonId: "A1-L1")
        let scenario = try XCTUnwrap(lesson.dialogue)
        let runner = DialogueRunner(scenario: scenario)

        XCTAssertEqual(runner.start(), .introduceScenario(scenario.scenario))

        var step = runner.advance()
        var guardCounter = 0
        while step != .finished, guardCounter < 50 {
            guardCounter += 1
            if case .awaitLearner(_, let candidates, _, _) = step {
                // Answer with the canonical hint every time.
                XCTAssertFalse(candidates.isEmpty, "Learner turns must carry hints")
                XCTAssertEqual(runner.submit(recognized: candidates[0]),
                               .matched(candidate: candidates[0]))
            }
            step = runner.advance()
        }
        XCTAssertEqual(step, .finished, "The script must terminate")
        XCTAssertEqual(runner.accuracy, 1.0, accuracy: 0.0001)
    }

    func testSilentLearnerStillReachesTheEnd() throws {
        // A learner who says nothing must never strand the session.
        // Same loop as above, submitting "" every time; assert .finished is reached.
    }
```

Also add a content-integrity test in `CurriculumLoaderTests`: for every lesson in the manifest that has a `dialogue`, assert every `learner` turn has a non-empty `hints` array and every `npc` turn has a non-empty `line`. This catches bad authoring before it reaches a user's ears.

### 7.4 New file: `VoiceLingoCore/Tests/VoiceLingoCoreTests/QuizRunnerTests.swift`

```swift
    func testUnderscoreBlankIsReplacedForSpeech() {
        let source = PracticeItem(type: "fillBlank", prompt: "Buenos ___, señor.", answer: "días")
        let item = QuizRunner.makeItem(from: source, phraseKey: "k", phraseTarget: "Buenos días")
        XCTAssertFalse(item?.spokenPrompt.contains("_") ?? true,
                       "TTS would read underscores aloud")
        XCTAssertEqual(item?.promptLocale, .target)
    }

    func testTranslationPromptsAreSpokenInTheNativeLanguage() { /* .native */ }
    func testUnknownPracticeTypeIsSkipped() { /* makeItem returns nil for type "foo" */ }
    func testPhrasesWithoutPracticeItemsAreSkipped() { /* no crash, no item */ }
    func testStrugglingPhrasesAreAskedFirst() { /* incorrectCount > correctCount => priority 0 */ }
    func testNeverQuizzedPhrasesComeBeforeAlreadyMasteredOnes() { }
    func testOrderingIsDeterministic() {
        // Build the same quiz twice from identical inputs and assert exact equality.
    }
    func testRespectsMaxItems() { }
    func testItemTypeRotatesWithCorrectCount() {
        // correctCount 0 -> practiceItems[0]; 1 -> [1]; 2 -> [2]; 3 -> [0]
    }
    func testGradeAcceptsAnswerInsideFiller() {
        // "pues buenos días" grades correct against answer "Buenos días"
    }
```

### 7.5 New file: `VoiceLingoCore/Tests/VoiceLingoCoreTests/UserProgressSRSTests.swift`

`UserProgress` is a SwiftData `@Model`, so build an in-memory container in `setUp`:

```swift
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: UserProgress.self, PhraseProgress.self,
                                       configurations: config)
        context = ModelContext(container)
    }

    func testCorrectAnswerPushesNextReviewIntoTheFuture() throws {
        let progress = UserProgress(languageCode: "es")
        context.insert(progress)
        progress.recordPhrase("A1-L1#buenos dias", correct: true)

        let phrase = try XCTUnwrap(progress.phraseProgress(for: "A1-L1#buenos dias"))
        XCTAssertEqual(phrase.correctCount, 1)
        XCTAssertGreaterThan(phrase.nextReviewDate, Date(),
                             "recordPhrase must schedule the next review, not leave it at now")
        XCTAssertFalse(phrase.isDue, "A just-answered item must not be immediately due")
    }

    func testIncorrectAnswerResetsTheInterval() throws { /* interval back to 1 */ }
    func testIntervalDoublesAcrossConsecutiveCorrectAnswers() throws { /* 2, 4, 8 */ }
```

### 7.6 Manual QA checklist (simulator, headphones in)

1. `A1-L1` start to finish. Praise lines vary and never repeat back-to-back.
2. `A1-L1` dialogue: answer every turn correctly; then re-run answering nothing at all. Both must reach the quiz.
3. `A1-L2` (no dialogue, no practice items): the session must run drills and finish cleanly, skipping both new phases.
4. Rename `speech-bank.json` away: the whole session still runs on fallback strings.
5. Airplane mode: everything works (this is the offline-capability guarantee from `DESIGN_DOC.md`).
6. Read the full `[SPEAK]` log for one session and confirm **every Spanish string in it appears verbatim in a file under `Content/`.** This is the §2.2 audit, and it should be done every time this area is touched.

---

---

## 8. Example: an A1-L1 session transcript after this implementation

This is a walkthrough of `A1-L1.json` ("Greetings," 12 phrases, phrase 1 fully enriched, one 4-turn `dialogue`) running through the architecture in §4, so you can see exactly what each piece produces before you build it. Teacher lines are tagged with the `SpeechAct`/component that generated them. Nothing here is aspirational prose — every line traces to a concrete call described above.

### 8.1 New Content phase — phrase 1 ("Buenos días," first exposure)

| Line | Source |
|---|---|
| "Alright, let's get started." | `speakVaried(.sessionOpen)` — one of several pre-authored variants, picked pseudo-randomly |
| "Buenos días." *(normal speed)* | `speakPhrase` — unchanged from today |
| "That's 'good morning.'" | New: native gloss spoken immediately, before the explanation — see §6 step ordering |
| "'Buenos días' literally means 'good days'... Memory tip: think 'way' plus 'nos'..." | `explainThenSpeak` — unchanged logic, but now gated: this is the phrase's **first** exposure (no `PhraseProgress` yet), so the full explanation fires |
| "Buenos días." *(slow)* | `speakPronunciationBreakdown` — unchanged |
| "Your turn." | `learnerTurnCue` |
| *(student)* "Buenos días." | — |
| "¡Muy bien!" | `speakVaried(.praise)` — **variant #2** of the praise pool, not the same "Correct! Well done." every time |
| "Buenos días, señora García." / "Good morning, Mrs. García." | `speakExampleThenAdvance` — unchanged |

### 8.2 New Content phase — phrase 2 ("Buenas tardes," no enrichment fields)

| Line | Source |
|---|---|
| "Buenas tardes." | `speakPhrase` |
| "Your turn." | `learnerTurnCue` — no explanation step fires; `phrase.vocabularyIntro`/`grammarNote`/`memoryHook` are all nil, same as today |
| *(student)* "no sé" *(recognizer catches this clearly, but it's nowhere near the target)* | — |
| "No es eso — escucha otra vez." | `speakVaried(.gentleCorrection)` — a **different** variant from whatever phrase 1 would have used on a miss, by the no-immediate-repeat rule in `SpeechComposer` |
| "Buenas tardes." *(slow)* → "Your turn." *(retry loop, same as today, attempts 2/3)* | |

> **Honest caveat worth knowing before you ship this:** the generalized evaluator in §4.2 is still edit-distance on the surface string. If the student had said "**Buenos** tardes" instead of "no sé" — a real gender-agreement mistake, not a mispronunciation — the Levenshtein distance from "buenas tardes" is 1, comfortably inside the matching threshold. It would be marked **correct**. The matcher cannot tell "close because you said it slightly wrong" apart from "close because you made a grammar error." That's a pre-existing limitation of today's `PronunciationEvaluator` too, not something this implementation introduces — but activating the dialogue phase (§8.3) makes it more visible, because dialogue answers are shorter and small edits are more likely to cross a meaningful grammar line. Worth a product decision at some point (tighter threshold for known minimal-pair mistakes?), but out of scope for this doc — flagging it so it isn't a surprise later.

### 8.3 Dialogue phase — `A1-L1-D1` ("You run into a coworker in the morning at the office.")

| Line | Source |
|---|---|
| "Here's a little scene. You run into a coworker in the morning at the office." | `DialogueStep.introduceScenario` |
| *(NPC)* "Buenos días. ¿Cómo estás?" | `DialogueStep.npcLine` — plain TTS of the authored `line` |
| "Your turn." | `DialogueStep.awaitLearner` → `learnerTurnCue` (this turn has no authored cue text, so the generic filler fires, per §4.5) |
| *(student)* "Estoy bien, gracias." | matched against `candidates: ["Estoy bien", "Estoy bien, gracias"]` |
| → `DialogueOutcome.matched(candidate: "Estoy bien, gracias")` | `DialogueRunner.submit` |
| *(NPC)* "Mucho gusto. ¿Cuál es tu nombre?" | `DialogueStep.npcLine` |
| "Your turn." | `learnerTurnCue` |
| *(student)* "Me llamo Alex." | matched against `candidates: ["Me llamo Juan"]` — **no match**, distance too large |
| → `DialogueOutcome.retry(attemptsRemaining: 1, modelAnswer: "Me llamo Juan")` | |
| "Casi — la línea es: Me llamo Juan." | `speakVaried(.gentleCorrection)`, then TTS of `modelAnswer` |
| *(student, 2nd attempt)* "Me llamo Juan." | matches |
| → `DialogueOutcome.matched(candidate: "Me llamo Juan")` | |
| "¡Perfecto! Fin de la escena." | `speakVaried(.praise)` |

> **This is the honest limitation from the "what's doable without an LLM" discussion, made concrete.** The dialogue phase is **scripted-role practice** — the student is reading a part, not introducing themselves. `candidates` is a fixed, pre-authored list (here, literally just `"Me llamo Juan"`); saying your own real name is a miss unless it happens to already be one of the authored candidates. Don't market this as "have a conversation" in the product copy — it's closer to a cold-read of a two-line scene. If real self-introduction matters later, the fix is a content change (add the student's own name as one more pre-authored candidate — the app already knows the display name from onboarding, no NLU required to splice it in), not a smarter matcher.

### 8.4 Quiz phase — retrieval on phrase 1's `practiceItems`

Phrase 1 is the only phrase in this lesson with `practiceItems`, so it's the only one `QuizRunner.buildQuiz` surfaces. `PhraseProgress.isDue` for the other 11 phrases is irrelevant here since they have nothing to quiz — they simply don't appear in this phase.

| Line | Source |
|---|---|
| "Un par de preguntas rápidas." | `speakVaried(.quizIntro)` |
| "Buenos ___, señor." | `QuizItem` built from the `fillBlank` practice item |
| *(student)* "días" | `QuizRunner.grade` — exact match on `answer: "días"` |
| "¿Qué dices a las 8 de la mañana?" | `qa` practice item, `PromptLocaleKind.target` → spoken in Spanish |
| *(student)* "Buenos días" | matches `answer: "Buenos días"` |
| "Translate: Good morning" | `translation` practice item, `PromptLocaleKind.native` → spoken in English |
| *(student)* "Buenos días" | matches |
| "¡Tres de tres!" | `speakVaried(.praise)`, slot-filled with the count |

Each correct answer here calls `PhraseProgress.updateInterval(correct: true)` for phrase 1's stable key (§4.1) exactly the way a correct phrase-drill answer already does — the quiz phase feeds the *same* SRS record, it doesn't create a second one.

### 8.5 Session close

| Line | Source |
|---|---|
| "Eso es todo por hoy. Score: 96." | `speakVaried(.sessionClose)`, `score` slot filled from `sessionScore` |

---

Nothing above required understanding anything the student said beyond "is it one of these known strings, and how close." That's the ceiling — and per §8.3 and the caveat in §8.2, it's worth being upfront with yourself about where that ceiling actually sits before you promise more than the architecture can deliver.

---

## 9. Non-goals and guardrails recap

This system must never do any of the following. If a future ticket asks for one of them, it is a design change requiring sign-off against `DESIGN_DOC.md`'s AI Usage Policy — not an implementation detail.

1. **Never generate Spanish.** No runtime conjugation, inflection, agreement, pluralization, or sentence assembly from grammar rules. Every Spanish utterance traces to a reviewed string in `Content/`. Selecting and slot-filling from an enumerable whitelist is allowed; composing is not.
2. **Never claim to understand unscripted speech.** `DialogueRunner` does multi-candidate fuzzy string matching over a closed, human-authored answer set. It cannot accept an answer nobody wrote down. Do not describe it as intent recognition, and do not start interpreting `DialogueTurn.expectedIntent` — that field stays unread.
3. **Never add a model.** No LLM API, no on-device language model, no CoreML text generation, no embeddings, no semantic-similarity scoring. Levenshtein distance over normalized strings is the whole matching stack, permanently.
4. **Never branch the dialogue on meaning.** The script is linear. A wrong answer models the correct line and moves forward; it never routes to a different NPC reply based on what was said.
5. **Never let `{recognized}` reach anything but an `echoResponse` carrier.** Runtime text is quoted back verbatim on explicitly-flagged open turns, and is never parsed, corrected, or absorbed into a tutor sentence whose grammar depends on it.
6. **Never invent a second SRS.** Scheduling lives in `UserProgress` / `PhraseProgress`. `QuizRunner` reads a snapshot and orders items; it does not compute intervals.
7. **Never make a new phase mandatory.** `A1-L2` has no `dialogue` and no `practiceItems`, and future lessons may not either. Every phase must be skippable on missing data, silently and without a stall.
8. **Never let a missing `speech-bank.json` break a session.** The bank is presentation polish layered over hardcoded fallbacks. If `SpeechComposer` returns nil, the app says the old fixed line — it does not go quiet and it does not crash.