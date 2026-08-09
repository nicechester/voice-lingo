import Foundation
import Combine
import SwiftData
import OSLog
import VoiceLingoCore

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceLingo", category: "Session")
private let tsFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

func sessionLog(_ message: String) {
    let ts = tsFormatter.string(from: Date())
    logger.info("[\(ts, privacy: .public)] \(message, privacy: .public)")
}

public enum SessionState: Equatable {
    case idle
    case explaining
    case speakingPrompt
    case awaitingResponse
    case evaluating
    case feedback
    case sessionComplete
}

public enum SessionPhase: Equatable {
    case warmup
    case newContent
    case dialogue
    case quiz
    case summary
}

#if os(iOS)
@MainActor
public final class SessionViewModel: ObservableObject {
    @Published public var currentState: SessionState = .idle
    @Published public var currentPhase: SessionPhase = .warmup
    @Published public var statusMessage: String = ""
    @Published public var attemptCount: Int = 0
    @Published public var phraseCount: String = "0/0"
    @Published public var sessionScore: Int = 0
    @Published public var isSessionActive: Bool = false

    private lazy var curriculumLoader = CurriculumLoader.shared
    private lazy var speechOutputService = SpeechOutputService.shared
    private lazy var speechRecognitionService = SpeechRecognitionService.shared
    private lazy var pronunciationEvaluator = PronunciationEvaluator.shared
    private lazy var voiceCommandRouter = VoiceCommandRouter.shared

    private var currentLesson: Lesson?
    private var currentLessonId: String = ""
    private var sessionStartedAt: Date?
    private var currentPhrasIndex: Int = 0
    private var currentPhrases: [Phrase] = []
    private var phraseScores: [UUID: (attempts: Int, correct: Bool)] = [:]
    private var modelContext: ModelContext?
    private var userProgress: UserProgress?

    public init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        setupVoiceCommandHandling()
    }

    // MARK: - Public Methods

    /// Attaches persistence dependencies once the view has access to the SwiftData
    /// environment. Must be called before `startSession` so progress can be recorded.
    public func attach(modelContext: ModelContext, userProgress: UserProgress?) {
        self.modelContext = modelContext
        self.userProgress = userProgress
    }

    public func startSession(language: String, levelId: String, lessonId: String) {
        isSessionActive = true
        voiceCommandRouter.suspend()
        currentState = .idle
        currentPhase = .newContent
        sessionScore = 0
        phraseScores.removeAll()
        statusMessage = "Loading lesson..."
        currentLessonId = lessonId
        sessionStartedAt = Date()

        Task {
            do {
                let manifest = try curriculumLoader.loadManifest(for: language)
                guard manifest.levels.contains(where: { $0.id == levelId }) else {
                    statusMessage = "Lesson not found"
                    isSessionActive = false
                    return
                }
                let lesson: Lesson
                do {
                    lesson = try curriculumLoader.loadLesson(language: language, levelId: levelId, lessonId: lessonId)
                } catch CurriculumLoader.CurriculumError.lessonNotFound {
                    statusMessage = "Lesson not found"
                    isSessionActive = false
                    return
                }

                self.currentLesson = lesson
                self.currentPhrases = lesson.phrases
                self.currentPhrasIndex = 0
                self.speechOutputService.setLocale(manifest.voiceLocale)
                self.speechRecognitionService.setLocale(manifest.recognizerLocale)

                await MainActor.run {
                    self.phraseCount = "1/\(self.currentPhrases.count)"
                    self.startNextPhrase()
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "Error loading lesson: \(error.localizedDescription)"
                    self.isSessionActive = false
                }
            }
        }
    }

    public func repeatPhrase() {
        guard currentPhrasIndex < currentPhrases.count else { return }
        let phrase = currentPhrases[currentPhrasIndex]
        statusMessage = "Listen carefully..."
        currentState = .speakingPrompt
        speechOutputService.speak(phrase.target)
    }

    public func stopSession() {
        isSessionActive = false
        currentState = .idle
        speechOutputService.stop()
        speechRecognitionService.stopRecognition()
        voiceCommandRouter.resume()
        statusMessage = "Session ended"
    }

    // MARK: - Private Methods

    private func startNextPhrase() {
        guard currentPhrasIndex < currentPhrases.count else {
            completeSession()
            return
        }

        let phrase = currentPhrases[currentPhrasIndex]
        attemptCount = 0
        phraseCount = "\(currentPhrasIndex + 1)/\(currentPhrases.count)"
        currentState = .speakingPrompt
        sessionLog("[SPEAK] Phrase \(currentPhrasIndex + 1)/\(currentPhrases.count): \"Phrase \(currentPhrasIndex + 1). Listen and repeat.\"")

        speechOutputService.speak("Phrase \(currentPhrasIndex + 1). Listen and repeat.", locale: "en-US") { [weak self] in
            Task { @MainActor [weak self] in self?.explainThenSpeak(phrase) }
        }
    }

    private func explainThenSpeak(_ phrase: Phrase) {
        guard let narrative = narrativeExplanationText(for: phrase) else {
            speakPronunciationBreakdown(phrase)
            return
        }

        currentState = .explaining
        statusMessage = "Let's learn this phrase"
        sessionLog("[SPEAK] [EXPLAIN] \"\(narrative)\"")
        speechOutputService.speak(narrative, locale: "en-US") { [weak self] in
            Task { @MainActor [weak self] in self?.speakPronunciationBreakdown(phrase) }
        }
    }

    private func narrativeExplanationText(for phrase: Phrase) -> String? {
        var parts: [String] = []
        if let intro = phrase.vocabularyIntro {
            parts.append(intro)
        }
        if let grammar = phrase.grammarNote {
            parts.append(grammar)
        }
        if let hook = phrase.memoryHook {
            parts.append("Memory tip: \(hook)")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    /// Speaks the actual target-language phrase slowly as the pronunciation breakdown,
    /// rather than reading `phrase.syllables`/`phonetic` aloud — those are romanized hints
    /// meant for on-screen display, and an en-US voice mangles them (e.g. "BWEH" gets spelled
    /// out letter-by-letter instead of pronounced).
    private func speakPronunciationBreakdown(_ phrase: Phrase) {
        guard let syllables = phrase.syllables, !syllables.isEmpty else {
            speakPhrase(phrase)
            return
        }

        currentState = .explaining
        statusMessage = "Let's break it down"
        sessionLog("[SPEAK] [BREAKDOWN] slow pronunciation of \"\(phrase.target)\"")
        speechOutputService.speak("Let's break it down.", locale: "en-US") { [weak self] in
            Task { @MainActor [weak self] in
                self?.speechOutputService.speakSlowly(phrase.target) { [weak self] in
                    Task { @MainActor [weak self] in self?.speakPhrase(phrase) }
                }
            }
        }
    }

    private func speakExampleThenAdvance(_ phrase: Phrase) {
        guard let example = phrase.exampleSentence else {
            currentPhrasIndex += 1
            startNextPhrase()
            return
        }

        sessionLog("[SPEAK] [EXAMPLE] \"\(example.target)\" (\(example.native))")
        speechOutputService.speak(example.target) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.speechOutputService.speak(example.native, locale: "en-US") { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.currentPhrasIndex += 1
                        self?.startNextPhrase()
                    }
                }
            }
        }
    }

    private func speakPhrase(_ phrase: Phrase) {
        statusMessage = phrase.native
        sessionLog("[SPEAK] Target: \"\(phrase.target)\" (\(phrase.native))")
        speechOutputService.speak(phrase.target) { [weak self] in
            Task { @MainActor [weak self] in self?.awaitUserResponse(for: phrase) }
        }
    }

    private func awaitUserResponse(for phrase: Phrase) {
        currentState = .awaitingResponse
        statusMessage = "Your turn"
        sessionLog("[SPEAK] \"Your turn.\"")
        speechOutputService.speak("Your turn.", locale: "en-US") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                sessionLog("[LISTEN] Waiting 1s before opening mic...")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                sessionLog("[LISTEN] Mic open, waiting for speech (timeout: 7s)")
                self.speechRecognitionService.recognize(timeout: 7.0) { [weak self] recognizedText in
                    Task { @MainActor in
                        sessionLog("[LISTEN] Recognized: \"\(recognizedText)\"")
                        self?.evaluateResponse(recognizedText, against: phrase)
                    }
                } onError: { [weak self] error in
                    Task { @MainActor in
                        sessionLog("[LISTEN] Error: \(error.localizedDescription)")
                        self?.handleRecognitionError(error, phrase: phrase)
                    }
                }
            }
        }
    }

    private func evaluateResponse(_ recognizedText: String, against phrase: Phrase) {
        speechRecognitionService.stopRecognition()
        currentState = .evaluating
        statusMessage = "Checking..."
        attemptCount += 1
        sessionLog("[EVAL] Attempt \(attemptCount): recognized=\"\(recognizedText)\" target=\"\(phrase.target)\"")

        let isCorrect = pronunciationEvaluator.evaluate(recognized: recognizedText, target: phrase.target)
        sessionLog("[EVAL] Result: \(isCorrect ? "CORRECT" : "WRONG")")
        phraseScores[phrase.id] = (attempts: attemptCount, correct: isCorrect)

        let key = phrase.progressKey(inLesson: currentLessonId)
        userProgress?.recordPhrase(key, correct: isCorrect)
        try? modelContext?.save()

        if isCorrect {
            provideFeedback(correct: true, phrase: phrase)
        } else if attemptCount < 3 {
            provideFeedback(correct: false, phrase: phrase, attempt: attemptCount)
        } else {
            revealAnswer(phrase: phrase)
        }
    }

    private func provideFeedback(correct: Bool, phrase: Phrase, attempt: Int = 0) {
        currentState = .feedback

        if correct {
            statusMessage = "Correct!"
            sessionScore += 10
            sessionLog("[SPEAK] \"Correct! Well done.\"")
            speechOutputService.speak("Correct! Well done.", locale: "en-US") { [weak self] in
                Task { @MainActor [weak self] in self?.speakExampleThenAdvance(phrase) }
            }
        } else {
            statusMessage = "Try again"
            sessionLog("[SPEAK] \"Not quite. Try again. \(phrase.target)\"")
            speechOutputService.speak("Not quite. Try again.", locale: "en-US") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.speechOutputService.speakSlowly(phrase.target) { [weak self] in
                        Task { @MainActor [weak self] in self?.awaitUserResponse(for: phrase) }
                    }
                }
            }
        }
    }

    private func revealAnswer(phrase: Phrase) {
        currentState = .feedback
        statusMessage = phrase.native
        speechOutputService.speak("The answer is.", locale: "en-US") { [weak self] in
            Task { @MainActor [weak self] in
                self?.speechOutputService.speak(phrase.target) { [weak self] in
                    Task { @MainActor [weak self] in self?.speakExampleThenAdvance(phrase) }
                }
            }
        }
    }

    private func handleRecognitionError(_ error: Error, phrase: Phrase) {
        speechRecognitionService.stopRecognition()
        attemptCount += 1
        statusMessage = "Didn't catch that"
        sessionLog("[SPEAK] \"Didn't catch that. Try again. \(phrase.target)\" (attempt \(attemptCount)/3)")
        speechOutputService.speak("Didn't catch that. Try again.", locale: "en-US") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.attemptCount < 3 {
                    self.speechOutputService.speakSlowly(phrase.target) { [weak self] in
                        Task { @MainActor [weak self] in self?.awaitUserResponse(for: phrase) }
                    }
                } else {
                    self.revealAnswer(phrase: phrase)
                }
            }
        }
    }

    private func completeSession() {
        currentState = .sessionComplete
        statusMessage = "Session complete! Score: \(sessionScore)"
        isSessionActive = false
        speechOutputService.speak("Session complete. Your score is \(sessionScore).")
    }

    private func setupVoiceCommandHandling() {
        voiceCommandRouter.startListening { [weak self] command in
            guard let self, self.isSessionActive else { return }
            switch command {
            case .repeat:
                self.repeatPhrase()
            case .skip:
                self.speechOutputService.stop()
                self.speechRecognitionService.stopRecognition()
                self.currentPhrasIndex += 1
                self.startNextPhrase()
            case .stop:
                self.speechOutputService.stop()
            case .help:
                self.speechOutputService.speak("Say the phrase you hear. You have 3 attempts.")
            default:
                break
            }
        }
    }
}
#endif
