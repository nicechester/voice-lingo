import XCTest
@testable import VoiceLingoCore

class PronunciationEvaluatorTests: XCTestCase {
    var evaluator: PronunciationEvaluator!
    var testPhrases: [Phrase]!

    override func setUp() {
        super.setUp()
        evaluator = PronunciationEvaluator()

        testPhrases = [
            Phrase(target: "Buenos días", native: "Good morning", phonetic: "BWEH-nos DEE-as"),
            Phrase(target: "¿Cómo estás?", native: "How are you?", phonetic: "KOH-moh es-TAHS"),
            Phrase(target: "Mucho gusto", native: "Nice to meet you", phonetic: "MOO-choh GOOS-toh"),
            Phrase(target: "Gracias", native: "Thank you", phonetic: "GRAH-see-as"),
        ]

        evaluator.loadPhrases(testPhrases)
    }

    func testExactMatch() {
        XCTAssertTrue(
            evaluator.evaluate(recognized: "Buenos días", target: "Buenos días"),
            "Exact match should return true"
        )
    }

    func testCaseInsensitiveMatch() {
        XCTAssertTrue(
            evaluator.evaluate(recognized: "buenos días", target: "Buenos días"),
            "Case-insensitive match should return true"
        )

        XCTAssertTrue(
            evaluator.evaluate(recognized: "BUENOS DÍAS", target: "Buenos días"),
            "All caps should match"
        )
    }

    func testDiacriticInsensitiveMatch() {
        XCTAssertTrue(
            evaluator.evaluate(recognized: "buenos dias", target: "Buenos días"),
            "Diacritic-insensitive match should return true"
        )

        XCTAssertTrue(
            evaluator.evaluate(recognized: "Como estas", target: "¿Cómo estás?"),
            "Removing accents should still match"
        )
    }

    func testLevenshteinDistance() {
        XCTAssertTrue(
            evaluator.evaluate(recognized: "Buenos dias", target: "Buenos días"),
            "Single character difference should pass (distance 1)"
        )

        XCTAssertTrue(
            evaluator.evaluate(recognized: "Buenos dais", target: "Buenos días"),
            "Two character differences should pass (distance 2)"
        )

        XCTAssertFalse(
            evaluator.evaluate(recognized: "Hello world", target: "Buenos días"),
            "Completely different phrase should fail (distance > 2)"
        )
    }

    func testWhitespaceHandling() {
        XCTAssertTrue(
            evaluator.evaluate(recognized: "  Buenos días  ", target: "Buenos días"),
            "Leading/trailing whitespace should be handled"
        )

        XCTAssertTrue(
            evaluator.evaluate(recognized: "Buenos  días", target: "Buenos días"),
            "Extra whitespace should be normalized"
        )
    }

    func testClearMismatch() {
        XCTAssertFalse(
            evaluator.evaluate(recognized: "Adiós", target: "Buenos días"),
            "Completely different phrases should not match"
        )

        XCTAssertFalse(
            evaluator.evaluate(recognized: "Hello", target: "Buenos días"),
            "Different languages should not match"
        )
    }

    func testAccuracyCalculation() {
        let accuracy1 = evaluator.getAccuracy(recognized: "Buenos días", target: "Buenos días")
        XCTAssertEqual(accuracy1, 1.0, "Exact match should have 100% accuracy")

        let accuracy2 = evaluator.getAccuracy(recognized: "Buenos dais", target: "Buenos días")
        XCTAssertGreaterThan(accuracy2, 0.8, "Close match should have high accuracy")
        XCTAssertLessThan(accuracy2, 1.0, "Close match should not be perfect")

        let accuracy3 = evaluator.getAccuracy(recognized: "Bueno", target: "Buenos días")
        XCTAssertGreaterThan(accuracy3, 0.0, "Partial match should have positive accuracy")
        XCTAssertLessThan(accuracy3, 0.5, "Partial match should have lower accuracy")
    }

    func testGetPhoneticHint() {
        let hint1 = evaluator.getPhoneticHint(for: "Buenos días")
        XCTAssertEqual(hint1, "BWEH-nos DEE-as", "Should return correct phonetic hint")

        let hint2 = evaluator.getPhoneticHint(for: "Gracias")
        XCTAssertEqual(hint2, "GRAH-see-as", "Should find phonetic from database")

        let hint3 = evaluator.getPhoneticHint(for: "Unknown phrase")
        XCTAssertNil(hint3, "Should return nil for unknown phrase")
    }

    func testFeedbackResultCorrect() {
        let feedback = evaluator.getFeedback(recognized: "Buenos días", target: "Buenos días")
        XCTAssertTrue(feedback.isSuccessful, "Correct match should be successful")
        XCTAssertEqual(feedback.accuracyPercentage, 100, "Correct should have 100% accuracy")
    }

    func testFeedbackResultCloseAttempt() {
        let feedback = evaluator.getFeedback(recognized: "Buenos d", target: "Buenos días")
        XCTAssertFalse(feedback.isSuccessful, "Close attempt should not be marked as successful")

        if case .closeAttempt(let accuracy) = feedback {
            XCTAssertGreaterThan(accuracy, 0.7, "Close attempt should have > 70% accuracy")
        } else {
            XCTFail("Should be classified as closeAttempt")
        }
    }

    func testFeedbackResultPartialAttempt() {
        let feedback = evaluator.getFeedback(recognized: "Buenos", target: "Buenos días")

        if case .partialAttempt = feedback {
            XCTAssertTrue(true, "Should be classified as partialAttempt")
        } else {
            XCTFail("Should be classified as partialAttempt")
        }
    }

    func testFeedbackResultIncorrect() {
        let feedback = evaluator.getFeedback(recognized: "Adiós", target: "Buenos días")

        if case .incorrect = feedback {
            XCTAssertTrue(true, "Should be classified as incorrect")
        } else {
            XCTFail("Should be classified as incorrect")
        }
    }

    func testEmptyInputHandling() {
        XCTAssertFalse(
            evaluator.evaluate(recognized: "", target: "Buenos días"),
            "Empty recognized text should not match"
        )

        XCTAssertTrue(
            evaluator.evaluate(recognized: "", target: ""),
            "Empty strings should match"
        )
    }

    func testSpecialCharactersHandling() {
        XCTAssertTrue(
            evaluator.evaluate(recognized: "como estas", target: "¿Cómo estás?"),
            "Should handle punctuation removal"
        )

        XCTAssertTrue(
            evaluator.evaluate(recognized: "mucho gusto", target: "Mucho gusto"),
            "Should handle various case combinations"
        )
    }

    func testFeedbackMessages() {
        let correctFeedback = evaluator.getFeedback(recognized: "Buenos días", target: "Buenos días")
        XCTAssertTrue(correctFeedback.feedbackMessage.contains("Excelente"))

        let closeFeedback = evaluator.getFeedback(recognized: "Buenos d", target: "Buenos días")
        XCTAssertTrue(closeFeedback.feedbackMessage.contains("Casi"))

        let partialFeedback = evaluator.getFeedback(recognized: "Buenos", target: "Buenos días")
        XCTAssertTrue(partialFeedback.feedbackMessage.contains("Intenta"))

        let incorrectFeedback = evaluator.getFeedback(recognized: "Adiós", target: "Buenos días")
        XCTAssertTrue(incorrectFeedback.feedbackMessage.contains("Intenta"))
    }

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
}
