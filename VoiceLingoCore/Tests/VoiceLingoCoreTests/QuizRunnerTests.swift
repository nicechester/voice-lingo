import XCTest
@testable import VoiceLingoCore

final class QuizRunnerTests: XCTestCase {

    // MARK: - Underscore Replacement Tests

    func testUnderscoreBlankIsReplacedForSpeech() {
        let source = PracticeItem(type: "fillBlank", prompt: "Buenos ___, señor.", answer: "días")
        let item = QuizRunner.makeItem(from: source, phraseKey: "k", phraseTarget: "Buenos días")
        XCTAssertFalse(item?.spokenPrompt.contains("_") ?? true,
                       "TTS would read underscores aloud")
        XCTAssertEqual(item?.promptLocale, .target)
    }

    // MARK: - Prompt Locale Tests

    func testTranslationPromptsAreSpokenInTheNativeLanguage() {
        let source = PracticeItem(type: "translation", prompt: "Translate: Good morning", answer: "Buenos días")
        let item = QuizRunner.makeItem(from: source, phraseKey: "k", phraseTarget: "Buenos días")
        XCTAssertEqual(item?.promptLocale, .native,
                       "Translation prompts should be in native language")
    }

    func testFillBlankPromptsAreSpokenInTargetLanguage() {
        let source = PracticeItem(type: "fillBlank", prompt: "Buenos ___, señor.", answer: "días")
        let item = QuizRunner.makeItem(from: source, phraseKey: "k", phraseTarget: "Buenos días")
        XCTAssertEqual(item?.promptLocale, .target,
                       "Fill-blank prompts should be in target language")
    }

    func testQAPromptsAreSpokenInTargetLanguage() {
        let source = PracticeItem(type: "qa", prompt: "¿Qué dices a las 8?", answer: "Buenos días")
        let item = QuizRunner.makeItem(from: source, phraseKey: "k", phraseTarget: "Buenos días")
        XCTAssertEqual(item?.promptLocale, .target,
                       "Q&A prompts should be in target language")
    }

    // MARK: - Type Handling Tests

    func testUnknownPracticeTypeIsSkipped() {
        let source = PracticeItem(type: "foo", prompt: "Test", answer: "Test")
        let item = QuizRunner.makeItem(from: source, phraseKey: "k", phraseTarget: "Test")
        XCTAssertNil(item, "Unknown type should return nil")
    }

    func testPhrasesWithoutPracticeItemsAreSkipped() {
        let phrase = Phrase(
            target: "Buenos días",
            native: "Good morning",
            phonetic: "BWEH-nos",
            practiceItems: nil
        )
        let quiz = QuizRunner.buildQuiz(phrases: [phrase], lessonId: "A1-L1", reviewStates: [:])
        XCTAssertTrue(quiz.isEmpty, "Phrases without practice items should be skipped")
    }

    func testPhrasesWithEmptyPracticeItemsAreSkipped() {
        let phrase = Phrase(
            target: "Buenos días",
            native: "Good morning",
            phonetic: "BWEH-nos",
            practiceItems: []
        )
        let quiz = QuizRunner.buildQuiz(phrases: [phrase], lessonId: "A1-L1", reviewStates: [:])
        XCTAssertTrue(quiz.isEmpty, "Phrases with empty practice items should be skipped")
    }

    // MARK: - Prioritization Tests

    func testStrugglingPhrasesAreAskedFirst() {
        let phrase1 = Phrase(
            target: "Buenos días",
            native: "Good morning",
            phonetic: "BWEH-nos",
            practiceItems: [PracticeItem(type: "translation", prompt: "Good morning", answer: "Buenos días")]
        )
        let phrase2 = Phrase(
            target: "Buenas noches",
            native: "Good night",
            phonetic: "BWEH-nas",
            practiceItems: [PracticeItem(type: "translation", prompt: "Good night", answer: "Buenas noches")]
        )

        // phrase1 is struggling (2 wrong, 1 right)
        // phrase2 is never tried (0 wrong, 0 right)
        let states = [
            "A1-L1#buenos dias": ReviewState(phraseKey: "A1-L1#buenos dias", correctCount: 1, incorrectCount: 2, isDue: false)
        ]

        let quiz = QuizRunner.buildQuiz(phrases: [phrase1, phrase2], lessonId: "A1-L1", reviewStates: states)
        XCTAssertEqual(quiz.first?.phraseKey, "A1-L1#buenos dias",
                       "Struggling phrases should be prioritized")
    }

    func testNeverQuizzedPhrasesComeBeforeAlreadyMasteredOnes() {
        let phrase1 = Phrase(
            target: "Buenos días",
            native: "Good morning",
            phonetic: "BWEH-nos",
            practiceItems: [PracticeItem(type: "translation", prompt: "Good morning", answer: "Buenos días")]
        )
        let phrase2 = Phrase(
            target: "Buenas noches",
            native: "Good night",
            phonetic: "BWEH-nas",
            practiceItems: [PracticeItem(type: "translation", prompt: "Good night", answer: "Buenas noches")]
        )

        let states = [
            "A1-L1#buenos dias": ReviewState(phraseKey: "A1-L1#buenos dias", correctCount: 5, incorrectCount: 0, isDue: false)
            // phrase2 is not in states at all
        ]

        let quiz = QuizRunner.buildQuiz(phrases: [phrase1, phrase2], lessonId: "A1-L1", reviewStates: states)
        XCTAssertEqual(quiz.first?.phraseKey, "A1-L1#buenas noches",
                       "Never-quizzed phrases should come before mastered ones")
    }

    // MARK: - Determinism Tests

    func testOrderingIsDeterministic() {
        let phrase1 = Phrase(
            target: "Buenos días",
            native: "Good morning",
            phonetic: "BWEH-nos",
            practiceItems: [PracticeItem(type: "translation", prompt: "Good morning", answer: "Buenos días")]
        )
        let phrase2 = Phrase(
            target: "Buenas noches",
            native: "Good night",
            phonetic: "BWEH-nas",
            practiceItems: [PracticeItem(type: "translation", prompt: "Good night", answer: "Buenas noches")]
        )

        let states: [String: ReviewState] = [:]

        let quiz1 = QuizRunner.buildQuiz(phrases: [phrase1, phrase2], lessonId: "A1-L1", reviewStates: states)
        let quiz2 = QuizRunner.buildQuiz(phrases: [phrase1, phrase2], lessonId: "A1-L1", reviewStates: states)

        XCTAssertEqual(quiz1, quiz2, "Same inputs should always produce the same quiz")
    }

    // MARK: - MaxItems Tests

    func testRespectsMaxItems() {
        let phrases = (1...10).map { i in
            Phrase(
                target: "Phrase \(i)",
                native: "Phrase \(i)",
                phonetic: "Phrase \(i)",
                practiceItems: [PracticeItem(type: "translation", prompt: "P\(i)", answer: "P\(i)")]
            )
        }

        let quiz = QuizRunner.buildQuiz(phrases: phrases, lessonId: "A1-L1", reviewStates: [:], maxItems: 3)
        XCTAssertEqual(quiz.count, 3, "Quiz should respect maxItems")
    }

    // MARK: - Type Rotation Tests

    func testItemTypeRotatesWithCorrectCount() {
        let items = [
            PracticeItem(type: "translation", prompt: "Good morning", answer: "Buenos días"),
            PracticeItem(type: "fillBlank", prompt: "Buenos ___", answer: "días"),
            PracticeItem(type: "qa", prompt: "¿Qué dices?", answer: "Buenos días")
        ]
        let phrase = Phrase(
            target: "Buenos días",
            native: "Good morning",
            phonetic: "BWEH-nos",
            practiceItems: items
        )

        // correctCount 0 -> items[0] (translation)
        let quiz1 = QuizRunner.buildQuiz(phrases: [phrase], lessonId: "A1-L1", reviewStates: [:])
        XCTAssertEqual(quiz1.first?.type, .translation)

        // correctCount 1 -> items[1] (fillBlank)
        let states1 = ["A1-L1#buenos dias": ReviewState(phraseKey: "A1-L1#buenos dias", correctCount: 1, incorrectCount: 0, isDue: false)]
        let quiz2 = QuizRunner.buildQuiz(phrases: [phrase], lessonId: "A1-L1", reviewStates: states1)
        XCTAssertEqual(quiz2.first?.type, .fillBlank)

        // correctCount 2 -> items[2] (qa)
        let states2 = ["A1-L1#buenos dias": ReviewState(phraseKey: "A1-L1#buenos dias", correctCount: 2, incorrectCount: 0, isDue: false)]
        let quiz3 = QuizRunner.buildQuiz(phrases: [phrase], lessonId: "A1-L1", reviewStates: states2)
        XCTAssertEqual(quiz3.first?.type, .qa)

        // correctCount 3 -> items[0] (translation, loops back)
        let states3 = ["A1-L1#buenos dias": ReviewState(phraseKey: "A1-L1#buenos dias", correctCount: 3, incorrectCount: 0, isDue: false)]
        let quiz4 = QuizRunner.buildQuiz(phrases: [phrase], lessonId: "A1-L1", reviewStates: states3)
        XCTAssertEqual(quiz4.first?.type, .translation)
    }

    // MARK: - Grading Tests

    func testGradeAcceptsAnswerInsideFiller() {
        let item = QuizItem(
            phraseKey: "A1-L1#buenos dias",
            phraseTarget: "Buenos días",
            type: .translation,
            spokenPrompt: "Good morning",
            promptLocale: .native,
            answer: "Buenos días"
        )
        XCTAssertTrue(QuizRunner.grade(recognized: "pues buenos dias", item: item),
                      "Should accept answer inside filler")
    }
}
