# VoiceLingo Project Structure

## Directory Layout

```
voice-lingo/                          # GitHub repo root
├── VoiceLingo.xcodeproj/             # Xcode project (for Xcode Cloud)
├── VoiceLingo/                       # App source files
│   ├── VoiceLingoApp.swift           # Entry point with audio session setup
│   ├── Info.plist                    # Permissions & app configuration
│   ├── Models/                       # Data models
│   │   ├── Language.swift
│   │   ├── Lesson.swift
│   │   ├── Phrase.swift
│   │   └── UserProgress.swift
│   ├── Services/                     # Business logic & platform integrations
│   │   ├── SpeechOutputService.swift
│   │   ├── SpeechRecognitionService.swift
│   │   ├── PronunciationEvaluator.swift
│   │   ├── CurriculumLoader.swift
│   │   └── VoiceCommandRouter.swift
│   ├── ViewModels/                   # SwiftUI state & logic
│   │   └── SessionViewModel.swift
│   ├── Views/                        # SwiftUI views
│   │   ├── LanguagePickerView.swift
│   │   ├── HomeView.swift
│   │   ├── ContentView.swift
│   │   └── SessionView.swift
│   └── Content/                      # Static content bundles
│       └── es/                       # Spanish (MVP)
│           └── curriculum.json
├── DESIGN_DOC.md                     # Architecture & design
└── PROJECT_STRUCTURE.md              # This file
```

## Setup Completed (Issue #1)

- [x] Xcode project created at repo root (VoiceLingo.xcodeproj)
- [x] App source directory (VoiceLingo/)
- [x] Audio session configuration (AVAudioSession with .playAndRecord, .allowBluetooth)
- [x] Permissions in Info.plist (NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription)
- [x] App entry point (VoiceLingoApp.swift) with audio setup
- [x] Folder structure for Models, Services, Views, ViewModels, Content
- [ ] SwiftData initialization (next: issue #2)
- [ ] Model implementations (issue #2)
- [ ] Spanish curriculum.json (issue #3)
