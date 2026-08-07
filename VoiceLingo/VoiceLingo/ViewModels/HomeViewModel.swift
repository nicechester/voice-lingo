import Foundation
import Combine
import SwiftData
import VoiceLingoCore

struct LevelDisplayItem: Identifiable {
    let id: String
    let title: String
    let isUnlocked: Bool
    let isContentAvailable: Bool
    let scorePercent: Int
    let firstLessonId: String?

    var isTappable: Bool {
        isUnlocked && isContentAvailable
    }
}

struct SessionLaunchParams: Hashable {
    let languageCode: String
    let levelId: String
    let lessonId: String
}

@MainActor
final class HomeViewModel: ObservableObject {
    static let cefrOrder: [(id: String, title: String)] = [
        ("A1", "Beginner"),
        ("A2", "Elementary"),
        ("B1", "Intermediate"),
        ("B2", "Upper Intermediate")
    ]

    @Published var levelItems: [LevelDisplayItem] = []
    @Published var activeSession: SessionLaunchParams?
    @Published var shouldShowLanguagePicker = false
    @Published var errorMessage: String?

    private var isActive = false
    private var isListeningActive = false
    private var currentProgress: UserProgress?
    private var currentLanguageCode: String?
    private lazy var curriculumLoader = CurriculumLoader.shared
    private lazy var speechOutputService = SpeechOutputService.shared
    private lazy var voiceCommandRouter = VoiceCommandRouter.shared
    private var voiceCommandCallbackId: ((VoiceCommand) -> Void)?

    func loadLevels(progress: UserProgress?, languageCode: String) {
        self.currentProgress = progress
        self.currentLanguageCode = languageCode

        do {
            let curriculum = try curriculumLoader.loadCurriculum(for: languageCode)
            var items: [LevelDisplayItem] = []

            for (levelId, levelTitle) in Self.cefrOrder {
                if let level = curriculum.levels.first(where: { $0.id == levelId }) {
                    let firstLessonId = level.lessons.first?.id
                    let isUnlocked = progress?.unlockedLevels.contains(levelId) ?? false
                    let scorePercent = Int((progress?.levelScores[levelId] ?? 0) * 100)

                    let item = LevelDisplayItem(
                        id: levelId,
                        title: levelTitle,
                        isUnlocked: isUnlocked,
                        isContentAvailable: true,
                        scorePercent: scorePercent,
                        firstLessonId: firstLessonId
                    )
                    items.append(item)
                } else {
                    let item = LevelDisplayItem(
                        id: levelId,
                        title: levelTitle,
                        isUnlocked: false,
                        isContentAvailable: false,
                        scorePercent: 0,
                        firstLessonId: nil
                    )
                    items.append(item)
                }
            }

            self.levelItems = items
            self.errorMessage = nil
        } catch {
            errorMessage = "Failed to load curriculum: \(error.localizedDescription)"
            var items: [LevelDisplayItem] = []
            for (levelId, levelTitle) in Self.cefrOrder {
                let item = LevelDisplayItem(
                    id: levelId,
                    title: levelTitle,
                    isUnlocked: false,
                    isContentAvailable: false,
                    scorePercent: 0,
                    firstLessonId: nil
                )
                items.append(item)
            }
            self.levelItems = items
        }
    }

    func startVoiceCommands(languageCode: String) {
        guard !isListeningActive else { return }

        voiceCommandRouter.setLocale(
            Language.supportedLanguages.first(where: { $0.code == languageCode })?.recognizerLocale ?? "es-MX"
        )

        let callback: (VoiceCommand) -> Void = { [weak self] command in
            guard let self = self, self.isActive else { return }

            switch command {
            case .startLesson, .review:
                self.handleStartLessonOrReview()
            case .changeLanguage:
                self.shouldShowLanguagePicker = true
                self.speechOutputService.speak("Choose your language")
            case .continue, .repeat, .help, .skip, .stop:
                break
            }
        }

        self.voiceCommandCallbackId = callback
        isListeningActive = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.speechOutputService.speak(self.greeting(), locale: "en-US", suspendRouter: false) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.speechOutputService.speak("What would you like to do today? Say start lesson to begin.", locale: "en-US", suspendRouter: false) { [weak self] in
                        guard let self else { return }
                        Task { @MainActor in
                            self.voiceCommandRouter.startListening(onCommand: callback)
                        }
                    }
                }
            }
        }
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning! Welcome to your Spanish lesson!"
        case 12..<17: return "Good afternoon! Welcome to your Spanish lesson!"
        default: return "Good evening! Welcome to your Spanish lesson!"
        }
    }

    func stopVoiceCommands() {
        isListeningActive = false
        voiceCommandRouter.stopListening()
    }

    func selectLevel(_ item: LevelDisplayItem) {
        guard item.isTappable, let firstLessonId = item.firstLessonId else { return }

        let languageCode = currentLanguageCode ?? "es"
        activeSession = SessionLaunchParams(
            languageCode: languageCode,
            levelId: item.id,
            lessonId: firstLessonId
        )

        speechOutputService.speak("Starting \(item.title)")
    }

    private func handleStartLessonOrReview() {
        // Try to use progress.currentLevel if it's tappable, else first tappable
        if let currentLevel = currentProgress?.currentLevel,
           let currentItem = levelItems.first(where: { $0.id == currentLevel && $0.isTappable }) {
            selectLevel(currentItem)
        } else if let firstTappable = levelItems.first(where: { $0.isTappable }) {
            selectLevel(firstTappable)
        }
    }

    func setActive(_ active: Bool) {
        isActive = active
    }
}
