import Foundation
import Combine
import SwiftData
import OSLog
import AVFoundation
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
    @Published public var lastResponseCorrect: Bool?

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
    private var composer: SpeechComposer?
    private var dialogueRunner: DialogueRunner?

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
                if let bank = self.curriculumLoader.loadSpeechBank(for: language) {
                    self.composer = SpeechComposer(bank: bank)
                } else {
                    self.composer = nil
                }

                await MainActor.run {
                    self.phraseCount = "1/\(self.currentPhrases.count)"
                    self.playSessionIntro()
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

    private func configureAudioForPlayback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            sessionLog("[AUDIO] Failed to configure audio session: \(error)")
        }
    }

    private func speakVaried(
        _ act: SpeechAct,
        fallback: String,
        fallbackLocale: String = "en-US",
        slots: [String: String] = [:],
        completion: (@Sendable () -> Void)? = nil,
        suspendRouter: Bool = true
    ) {
        if let line = composer?.line(for: act, slots: slots) {
            sessionLog("[SPEAK] [VARIED:\(act)] \"\(line.text)\"")
            speechOutputService.speak(line.text, locale: line.locale ?? fallbackLocale, suspendRouter: suspendRouter, completion: completion)
        } else {
            sessionLog("[SPEAK] [FALLBACK:\(act)] \"\(fallback)\"")
            speechOutputService.speak(fallback, locale: fallbackLocale, suspendRouter: suspendRouter, completion: completion)
        }
    }

    private func playSessionIntro() {
        currentState = .explaining
        statusMessage = "Let's begin"
        speechRecognitionService.stopRecognition()
        speechOutputService.stop()
        configureAudioForPlayback()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.speakVaried(.sessionOpen, fallback: "Let's get started.") { [weak self] in
                Task { @MainActor [weak self] in self?.startNextPhrase() }
            }
        }
    }

    private func startNextPhrase() {
        guard currentPhrasIndex < currentPhrases.count else {
            beginDialoguePhase()
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
        let key = phrase.progressKey(inLesson: currentLessonId)
        let alreadyLearned = (userProgress?.phraseProgress(for: key)?.correctCount ?? 0) > 0

        if alreadyLearned {
            speakPronunciationBreakdown(phrase)
            return
        }

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
        statusMessage = "Your turn"
        speakVaried(.learnerTurnCue, fallback: "Your turn.") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentState = .awaitingResponse
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
        currentState = .evaluating
        speechRecognitionService.stopRecognition()
        statusMessage = "Checking..."
        attemptCount += 1
        sessionLog("[EVAL] Attempt \(attemptCount): recognized=\"\(recognizedText)\" target=\"\(phrase.target)\"")

        let isCorrect = pronunciationEvaluator.evaluate(recognized: recognizedText, target: phrase.target)
        sessionLog("[EVAL] Result: \(isCorrect ? "CORRECT" : "WRONG")")
        phraseScores[phrase.id] = (attempts: attemptCount, correct: isCorrect)
        lastResponseCorrect = isCorrect

        let key = phrase.progressKey(inLesson: currentLessonId)
        userProgress?.recordPhrase(key, correct: isCorrect)
        try? modelContext?.save()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            if isCorrect {
                self.provideFeedback(correct: true, phrase: phrase)
            } else if self.attemptCount < 3 {
                self.provideFeedback(correct: false, phrase: phrase, attempt: self.attemptCount)
            } else {
                self.revealAnswer(phrase: phrase)
            }
        }
    }

    private func provideFeedback(correct: Bool, phrase: Phrase, attempt: Int = 0) {
        currentState = .speakingPrompt

        if correct {
            statusMessage = "Correct!"
            sessionScore += 10
            Task { @MainActor in
                self.speechOutputService.stop()
                self.configureAudioForPlayback()
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.speakVaried(.praise, fallback: "Correct! Well done.") { [weak self] in
                    Task { @MainActor [weak self] in self?.speakExampleThenAdvance(phrase) }
                }
            }
        } else {
            statusMessage = "Try again"
            Task { @MainActor in
                self.speechOutputService.stop()
                self.configureAudioForPlayback()
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.speakVaried(.gentleCorrection, fallback: "Not quite. Try again.") { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.speechOutputService.speakSlowly(phrase.target) { [weak self] in
                            Task { @MainActor [weak self] in self?.awaitUserResponse(for: phrase) }
                        }
                    }
                }
            }
        }
    }

    private func revealAnswer(phrase: Phrase) {
        currentState = .speakingPrompt
        statusMessage = phrase.native
        Task { @MainActor in
            self.speechOutputService.stop()
            self.configureAudioForPlayback()
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.speakVaried(.revealAnswer, fallback: "The answer is.") { [weak self] in
                Task { @MainActor [weak self] in
                    self?.speechOutputService.speak(phrase.target) { [weak self] in
                        Task { @MainActor [weak self] in self?.speakExampleThenAdvance(phrase) }
                    }
                }
            }
        }
    }

    private func handleRecognitionError(_ error: Error, phrase: Phrase) {
        speechRecognitionService.stopRecognition()
        currentState = .speakingPrompt
        attemptCount += 1
        statusMessage = "Didn't catch that"
        speechOutputService.stop()
        configureAudioForPlayback()
        speakVaried(.gentleCorrection, fallback: "Didn't catch that. Try again.") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.attemptCount < 3 {
                    self.speechOutputService.speakSlowly(phrase.target) { [weak self] in
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            self?.awaitUserResponse(for: phrase)
                        }
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

        let correctCount = phraseScores.values.filter { $0.correct }.count
        let levelScore = Double(correctCount) / Double(max(phraseScores.count, 1))
        userProgress?.updateLevelScore(currentLessonId.split(separator: "-").first.map(String.init) ?? "", score: levelScore)
        try? modelContext?.save()

        speakVaried(
            .sessionClose,
            fallback: "Session complete. Your score is \(sessionScore).",
            slots: ["score": String(sessionScore)]
        )
    }

    private func beginDialoguePhase() {
        guard let scenario = currentLesson?.dialogue else {
            beginQuizPhase()
            return
        }

        currentPhase = .dialogue
        dialogueRunner = DialogueRunner(scenario: scenario)
        guard let runner = dialogueRunner else { return }

        let step = runner.start()
        perform(step)
    }

    private func perform(_ step: DialogueStep) {
        switch step {
        case .introduceScenario(let text):
            statusMessage = "Scenario"
            currentState = .explaining
            sessionLog("[SPEAK] [DIALOGUE:scenario] \"\(text)\"")
            speakVaried(.dialogueIntro, fallback: text) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let runner = self.dialogueRunner else { return }
                    self.perform(runner.advance())
                }
            }

        case .npcLine(let text, let native):
            statusMessage = native ?? text
            currentState = .speakingPrompt
            sessionLog("[SPEAK] [DIALOGUE:npc] \"\(text)\" (\(native ?? ""))")
            speechOutputService.speak(text) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let runner = self.dialogueRunner else { return }
                    self.perform(runner.advance())
                }
            }

        case .awaitLearner(_, _, let cue, _):
            statusMessage = "Your turn"
            let cueFallback = cue ?? "Your turn."
            sessionLog("[SPEAK] [DIALOGUE:learner-cue] \"\(cueFallback)\"")
            speakVaried(.learnerTurnCue, fallback: cueFallback) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentState = .awaitingResponse
                    sessionLog("[LISTEN] Dialogue learner turn: mic open (7s)")
                    self.speechRecognitionService.recognize(timeout: 7.0) { [weak self] recognizedText in
                        Task { @MainActor in
                            sessionLog("[LISTEN] Dialogue: recognized=\"\(recognizedText)\"")
                            self?.handleDialogueSpeech(recognizedText)
                        }
                    } onError: { [weak self] error in
                        Task { @MainActor in
                            sessionLog("[LISTEN] Dialogue error: \(error.localizedDescription)")
                            self?.handleDialogueSpeech("")
                        }
                    }
                }
            }

        case .finished:
            currentPhase = .quiz
            beginQuizPhase()
        }
    }

    private func handleDialogueSpeech(_ recognized: String) {
        speechRecognitionService.stopRecognition()
        guard let runner = dialogueRunner else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            let outcome = runner.submit(recognized: recognized)
            sessionLog("[DIALOGUE] Submit: recognized=\"\(recognized)\" outcome=\(outcome)")

            switch outcome {
        case .matched(let candidate):
            sessionLog("[SPEAK] [DIALOGUE:praise] matched: \"\(candidate)\"")
            speakVaried(.praise, fallback: "Correct!") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let runner = self.dialogueRunner else { return }
                    self.perform(runner.advance())
                }
            }

        case .openAccepted(let recognized):
            if let echoLine = self.composer?.echo(recognized: recognized) {
                sessionLog("[SPEAK] [DIALOGUE:echo] \"\(echoLine.text)\"")
                speechOutputService.speak(echoLine.text, locale: echoLine.locale ?? "es-MX") { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, let runner = self.dialogueRunner else { return }
                        self.perform(runner.advance())
                    }
                }
            } else {
                sessionLog("[SPEAK] [DIALOGUE:echo-fallback] no echo available")
                Task { @MainActor [weak self] in
                    guard let self, let runner = self.dialogueRunner else { return }
                    self.perform(runner.advance())
                }
            }

        case .retry(_, let modelAnswer):
            statusMessage = "Try again"
            sessionLog("[SPEAK] [DIALOGUE:retry] model=\"\(modelAnswer)\"")
            speakVaried(.gentleCorrection, fallback: "Try again.") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.speechOutputService.speakSlowly(modelAnswer) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            sessionLog("[LISTEN] Dialogue retry: mic re-open (7s)")
                            self.speechRecognitionService.recognize(timeout: 7.0) { [weak self] recognizedText in
                                Task { @MainActor in
                                    sessionLog("[LISTEN] Dialogue retry: recognized=\"\(recognizedText)\"")
                                    self?.handleDialogueSpeech(recognizedText)
                                }
                            } onError: { [weak self] error in
                                Task { @MainActor in
                                    sessionLog("[LISTEN] Dialogue retry error: \(error.localizedDescription)")
                                    self?.handleDialogueSpeech("")
                                }
                            }
                        }
                    }
                }
            }

        case .movedOn(let modelAnswer):
            statusMessage = "Moving on"
            sessionLog("[SPEAK] [DIALOGUE:moved-on] model=\"\(modelAnswer)\"")
            speakVaried(.revealAnswer, fallback: "The answer is:") { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.speechOutputService.speak(modelAnswer) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, let runner = self.dialogueRunner else { return }
                            self.perform(runner.advance())
                        }
                    }
                }
            }
            }
        }
    }

    private func beginQuizPhase() {
        currentPhase = .quiz
        sessionLog("[PHASE] Beginning quiz phase")
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
                self.speakVaried(.learnerTurnCue, fallback: "Say the phrase you hear. You have 3 attempts.")
            default:
                break
            }
        }
    }
}
#endif
