# VoiceLingo — Design Document

## Overview

A hands-free iOS app for learning conversational languages through voice interaction.
Designed for commuters, drivers, and anyone who can't look at their phone.
The entire UX is audio-driven: the app speaks, the user responds, the app evaluates.

> **MVP language: Spanish.** The architecture is language-agnostic from day one so adding
> French, Japanese, Mandarin, etc. requires only new content files — no code changes.

---

## Core Use Cases

- Commuting by car, bus, or train
- Walking or exercising
- Any eyes-free / hands-free scenario

---

## Key Features

### 1. Multi-Language Support
- Each language is a self-contained content bundle (`/Content/{lang-code}/manifest.json` + per-lesson files)
- Language selection on first launch (or from settings)
- AVSpeechSynthesizer locale and SFSpeechRecognizer locale are driven by the selected language
- MVP ships with Spanish (`es-MX`) only; additional languages are additive content drops

### 2. Level-Based Curriculum
| Level | Description |
|-------|-------------|
| A1 | Absolute beginner — greetings, numbers, colors |
| A2 | Basic conversations — shopping, directions, time |
| B1 | Intermediate — opinions, past/future tense |
| B2 | Upper-intermediate — nuanced conversation, idioms |

Each level unlocks after the previous one reaches a passing score threshold (≥ 80%).

### 3. Listen & Repeat Mode
- App reads a target-language phrase aloud via AVSpeechSynthesizer
- User repeats the phrase
- App evaluates pronunciation via SFSpeechRecognizer
- Feedback is spoken: "Correct!" or "Try again: [correct pronunciation phonetically]"

### 4. Pronunciation Correction
- Recognized text is compared against the target phrase (normalized, diacritics stripped)
- On mismatch, app speaks:
  - The correct phrase again (slower rate)
  - A phonetic hint (pre-authored per phrase, e.g. "BWEH-nos DEE-as")
- Up to 3 attempts before moving on with the answer revealed

### 5. Progressive Grammar & Vocabulary
- Each session introduces 3–5 new words/phrases
- New items are interleaved with review items (spaced repetition)
- Grammar notes are spoken briefly before relevant exercises

### 6. Session Structure (15–20 min)
```
[Warm-up]     Review 5 items from previous session
[New Content] 3–5 new vocabulary/phrases with listen & repeat
[Dialogue]    Short scripted conversation (2–4 turns)
[Quiz]        5 spoken questions, user answers verbally
[Summary]     Score + words to review next time
```

### 7. Zero-Tap Voice Launch
- The moment the app opens, the speech recognizer is already active and listening —
  no tap required to start using any function
- On launch the app speaks a short ready prompt ("Ready. Say 'start lesson' or 'review'.")
  while the listener is live
- Launch-time voice commands: "start lesson", "review", "continue", "change language", "repeat"
- Every screen keeps a live command listener; on-screen buttons are a fallback, not the primary path
- Exception: very first launch requires one-time taps (mic/speech permission dialogs and
  language selection) — iOS mandates user interaction for permission grants. All subsequent
  launches are zero-tap.

---

## Architecture

### Tech Stack
- Language: Swift
- UI: SwiftUI (minimal — mostly audio feedback)
- Speech Output: AVFoundation / AVSpeechSynthesizer
- Speech Input: Speech framework (SFSpeechRecognizer, SFSpeechAudioBufferRecognitionRequest)
- Persistence: SwiftData (progress, scores, unlocked levels per language)
- Audio Session: AVAudioSession (.playAndRecord, .allowBluetooth for CarPlay/AirPods)

### Module Breakdown

```
VoiceLingo/
├── App/
│   └── VoiceLingoApp.swift                # Entry point, audio session setup
├── Models/
│   ├── Language.swift                     # Language metadata (code, name, locale, flag)
│   ├── CurriculumManifest.swift           # Lightweight index: LevelSummary, LessonSummary (titles only)
│   ├── Lesson.swift                       # Full lesson: phrases, grammar note, dialogue, practice items
│   ├── Phrase.swift                       # Target/native/phonetic + explanation & practice fields
│   ├── DialogueScenario.swift             # Scripted conversation-practice turns for a lesson
│   └── UserProgress.swift                 # SwiftData: scores, unlocked levels, per language
├── Services/
│   ├── SpeechOutputService.swift          # AVSpeechSynthesizer wrapper (locale-aware)
│   ├── SpeechRecognitionService.swift     # SFSpeechRecognizer wrapper (locale-aware)
│   ├── PronunciationEvaluator.swift       # Compare recognized vs. target text
│   ├── VoiceCommandRouter.swift           # Always-on listener → app commands (start, review, …)
│   └── CurriculumLoader.swift            # Loads manifest.json (index) + per-lesson JSON on demand, cached
├── ViewModels/
│   └── SessionViewModel.swift             # Session state machine
├── Views/
│   ├── LanguagePickerView.swift           # First-launch language selector
│   ├── HomeView.swift                     # Level selector (large tap targets, minimal)
│   └── SessionView.swift                 # Active session — waveform + status text only
└── Content/
    └── es/                                # Spanish content bundle (MVP)
        ├── manifest.json                  # Language + level/lesson index (lightweight, no phrase content)
        └── A1/
            ├── A1-L1.json                 # Full lesson: phrases, explanations, practice items, dialogue
            └── A1-L2.json
    └── fr/                                # French (future)
    └── ja/                                # Japanese (future)
```

### App Launch Flow (Zero-Tap)

```
launch → activate audio session → start command listener → speak ready prompt
       → voice command recognized → route (start lesson / review / …)
```

The listener starts in `VoiceLingoApp` initialization, before any view interaction.
First launch only: permission dialogs + language picker precede this flow.

### Session State Machine

```
idle → speaking_prompt → awaiting_response → evaluating → feedback → [next_phrase | retry]
```

---

## Content Schema (`Content/{lang}/`)

Curriculum content is core to this app and is split into multiple files per language so that:
- The home screen (level/lesson list) can load a **lightweight manifest** without paying the
  cost of parsing every phrase's explanation, practice items, and dialogue script.
- An active session loads **exactly one lesson file** — the one the learner is doing right now.
- Content stays reviewable/authorable per lesson instead of one ever-growing JSON blob.

```
Content/{lang}/
  manifest.json          # language + level/lesson titles only — no phrase content
  {levelId}/
    {lessonId}.json       # full lesson: phrases, explanations, practice items, dialogue
```

### Manifest (`Content/es/manifest.json`)

```json
{
  "language": "es",
  "voiceLocale": "es-MX",
  "recognizerLocale": "es-MX",
  "levels": [
    {
      "id": "A1",
      "title": "Beginner",
      "lessons": [
        { "id": "A1-L1", "title": "Greetings" },
        { "id": "A1-L2", "title": "Basic Phrases" }
      ]
    }
  ]
}
```

### Lesson file (`Content/es/A1/A1-L1.json`)

Each phrase carries its listen-and-repeat fields plus optional pre-practice explanation and
practice-mode fields; a lesson may also carry a scripted conversation-practice `dialogue`. All
new fields are optional so lessons can be authored incrementally.

```json
{
  "id": "A1-L1",
  "title": "Greetings",
  "grammarNote": "Use 'buenos' for masculine/neutral, 'buenas' for feminine nouns.",
  "phrases": [
    {
      "target": "Buenos días",
      "native": "Good morning",
      "phonetic": "BWEH-nos DEE-as",
      "syllables": ["BWEH", "nos", "DEE", "as"],
      "vocabularyIntro": "'Buenos días' literally means 'good days' — used as a morning greeting until roughly noon.",
      "exampleSentence": {
        "target": "Buenos días, señora García.",
        "native": "Good morning, Mrs. García."
      },
      "grammarNote": "'Buenos' agrees with the plural masculine noun 'días'; never say 'buena día'.",
      "memoryHook": "Think 'BWAY-nos' like 'way' + 'nos' (us) — 'our good day begins'.",
      "practiceItems": [
        { "type": "translation", "prompt": "Translate: Good morning", "answer": "Buenos días" },
        { "type": "fillBlank", "prompt": "Buenos ___, señor.", "answer": "días" },
        { "type": "qa", "prompt": "¿Qué dices a las 8 de la mañana?", "answer": "Buenos días" }
      ]
    },
    {
      "target": "¿Cómo estás?",
      "native": "How are you?",
      "phonetic": "KOH-moh es-TAHS"
    }
  ],
  "dialogue": {
    "id": "A1-L1-D1",
    "scenario": "You run into a coworker in the morning at the office.",
    "turns": [
      { "speaker": "npc", "line": "Buenos días. ¿Cómo estás?", "native": "Good morning. How are you?" },
      { "speaker": "learner", "expectedIntent": "greeting_response", "hints": ["Estoy bien", "Estoy bien, gracias"] },
      { "speaker": "npc", "line": "Mucho gusto. ¿Cuál es tu nombre?", "native": "Nice to meet you. What is your name?" },
      { "speaker": "learner", "expectedIntent": "state_name", "hints": ["Me llamo Juan"] }
    ]
  }
}
```

`dialogue.turns[].expectedIntent`/`hints` are scripted data only — per the AI Usage Policy below,
there is no runtime intent-matching; this data is a placeholder for future evaluation logic.

### Loading strategy

- `CurriculumLoader.loadManifest(for language:)` — loads and caches `manifest.json`; used by
  `HomeViewModel` to render the level/lesson list and unlock status.
- `CurriculumLoader.loadLesson(language:levelId:lessonId:)` — loads and caches exactly one lesson
  file; used by `SessionViewModel.startSession` when a lesson begins. `voiceLocale`/`recognizerLocale`
  are sourced from the manifest, not duplicated per lesson.

---

## AI Usage Policy

**No runtime LLM.** The app makes no AI/LLM API calls at runtime. All voice features are
handled by on-device platform frameworks:

- Text-to-speech: AVSpeechSynthesizer
- Speech recognition: Speech framework (SFSpeechRecognizer)

This keeps the app offline-capable, free of API costs and latency, and avoids sending
user audio off-device.

**AI at development time only.** AI is used during development to build foundation work
and content data — vocabulary lists, example phrases, translations, phonetic hints, and
curriculum structure. Generated content is reviewed and corrected before shipping, then
baked into the static `curriculum.json` bundles. The shipped app is fully deterministic.

---

## Pronunciation Evaluation Logic

```swift
func evaluate(recognized: String, target: String) -> Bool {
    let normalize: (String) -> String = {
        $0.lowercased().folding(options: .diacriticInsensitive, locale: .current)
    }
    let r = normalize(recognized)
    let t = normalize(target)
    return r.contains(t) || levenshteinDistance(r, t) <= 2
}
```

Levenshtein distance ≤ 2 tolerates minor accent/recognition variance without being too lenient.

---

## Audio Session Configuration

```swift
try AVAudioSession.sharedInstance().setCategory(
    .playAndRecord,
    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
)
```

Works with: AirPods, CarPlay, wired headsets, phone speaker (fallback).

---

## Permissions Required (`Info.plist`)

| Key | Reason |
|-----|--------|
| NSMicrophoneUsageDescription | Record user's spoken responses |
| NSSpeechRecognitionUsageDescription | Evaluate pronunciation |

---

## Spaced Repetition (Simple)

- Each phrase tracks `nextReviewDate` and `interval` (days), stored per language in SwiftData
- Correct answer: `interval *= 2`
- Wrong answer: `interval = 1`
- Items due today are prioritized in warm-up

---

## UI Design Principles

- Zero-tap: listener is active from app open — every function is reachable by voice alone
- Screen is glanceable — one large status label + waveform animation
- All navigation is voice-triggered; large tap targets exist only as fallback
- No small buttons, no reading required during a session
- Dark mode default (easier on eyes when glancing)

---

## MVP Scope (Spanish)

- [ ] Language: Spanish (`es-MX`) only
- [ ] A1 level (2 lessons, ~20 phrases)
- [ ] Listen & repeat with pronunciation check
- [ ] Spoken feedback (correct / retry with phonetic hint)
- [ ] Zero-tap launch: command listener active on app open ("start lesson", "review")
- [ ] Progress saved locally (SwiftData)
- [ ] Works with AirPods / Bluetooth

## Future Scope

- [ ] Additional languages (French, Japanese, Mandarin, etc.) — content only, no code changes
- [ ] A2–B2 levels per language
- [ ] Dialogue mode (back-and-forth conversation simulation)
- [ ] Siri Shortcuts ("Hey Siri, start my French lesson")
- [ ] CarPlay app extension
- [ ] iCloud sync across devices
