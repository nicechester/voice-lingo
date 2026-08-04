import Foundation
import Combine
import SwiftData
import VoiceLingoCore

public enum SessionState: Equatable {
    case idle
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

    public func startSession(language: String, levelId: String, lessonId: String) {
        isSessionActive = true
        currentState = .idle
        currentPhase = .warmup
        sessionScore = 0
        phraseScores.removeAll()
        statusMessage = "Loading lesson..."

        Task {
            do {
                let curriculum = try curriculumLoader.loadCurriculum(for: language)
                guard let level = curriculum.levels.first(where: { $0.id == levelId }),
                      let lesson = level.lessons.first(where: { $0.id == lessonId }) else {
                    statusMessage = "Lesson not found"
                    isSessionActive = false
                    return
                }

                self.currentLesson = lesson
                self.currentPhrases = lesson.phrases
                self.currentPhrasIndex = 0
                self.speechOutputService.setLocale(curriculum.voiceLocale)
                self.speechRecognitionService.setLocale(curriculum.recognizerLocale)

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
        speechRecognitionService.stopRecognition()
        voiceCommandRouter.stopListening()
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

        statusMessage = "Get ready..."
        currentState = .speakingPrompt

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.speakPhrase(phrase)
        }
    }

    private func speakPhrase(_ phrase: Phrase) {
        statusMessage = "Listen..."
        speechOutputService.speak(phrase.target)

        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(phrase.target.count) * 0.05 + 1.0) { [weak self] in
            self?.awaitUserResponse(for: phrase)
        }
    }

    private func awaitUserResponse(for phrase: Phrase) {
        currentState = .awaitingResponse
        statusMessage = "Your turn... Speaking..."

        speechRecognitionService.recognize(timeout: 5.0) { [weak self] recognizedText in
            Task { @MainActor in
                self?.evaluateResponse(recognizedText, against: phrase)
            }
        } onError: { [weak self] error in
            Task { @MainActor in
                self?.handleRecognitionError(error, phrase: phrase)
            }
        }
    }

    private func evaluateResponse(_ recognizedText: String, against phrase: Phrase) {
        currentState = .evaluating
        statusMessage = "Checking..."
        attemptCount += 1

        let isCorrect = pronunciationEvaluator.evaluate(recognized: recognizedText, target: phrase.target)
        phraseScores[phrase.id] = (attempts: attemptCount, correct: isCorrect)

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
            speechOutputService.speak("Correct! Well done.")

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.currentPhrasIndex += 1
                self?.startNextPhrase()
            }
        } else {
            statusMessage = "Try again... Attempt \(attempt) of 3"
            speechOutputService.speak("Not quite. \(phrase.phonetic)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.awaitUserResponse(for: phrase)
            }
        }
    }

    private func revealAnswer(phrase: Phrase) {
        currentState = .feedback
        statusMessage = "Moving on..."
        speechOutputService.speak("The answer is: \(phrase.target)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.currentPhrasIndex += 1
            self?.startNextPhrase()
        }
    }

    private func handleRecognitionError(_ error: Error, phrase: Phrase) {
        attemptCount += 1
        statusMessage = "Didn't catch that. Try again."

        if attemptCount < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.awaitUserResponse(for: phrase)
            }
        } else {
            revealAnswer(phrase: phrase)
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
            switch command {
            case .repeat:
                self?.repeatPhrase()
            case .skip:
                self?.currentPhrasIndex += 1
                self?.startNextPhrase()
            case .help:
                self?.speechOutputService.speak("Say the phrase you hear. You have 3 attempts.")
            default:
                break
            }
        }
    }
}
#endif
