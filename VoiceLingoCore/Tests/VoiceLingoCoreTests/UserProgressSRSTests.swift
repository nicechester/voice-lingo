import XCTest
import SwiftData
@testable import VoiceLingoCore

final class UserProgressSRSTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: UserProgress.self, PhraseProgress.self,
                                       configurations: config)
        context = ModelContext(container)
    }

    // MARK: - Scheduling Tests

    func testCorrectAnswerPushesNextReviewIntoTheFuture() throws {
        let progress = UserProgress(languageCode: "es")
        context.insert(progress)
        progress.recordPhrase("A1-L1#buenos dias", correct: true)

        let phrase = try XCTUnwrap(progress.phraseProgress(for: "A1-L1#buenos dias"))
        XCTAssertEqual(phrase.correctCount, 1, "Should increment correct count")
        XCTAssertGreaterThan(phrase.nextReviewDate, Date(),
                             "recordPhrase must schedule the next review, not leave it at now")
        XCTAssertFalse(phrase.isDue, "A just-answered item must not be immediately due")
    }

    func testIncorrectAnswerResetsTheInterval() throws {
        let progress = UserProgress(languageCode: "es")
        context.insert(progress)

        // First correct answer pushes the interval out
        progress.recordPhrase("A1-L1#buenos dias", correct: true)
        var phrase = try XCTUnwrap(progress.phraseProgress(for: "A1-L1#buenos dias"))
        XCTAssertGreaterThan(phrase.interval, 1, "Correct answer should increase interval")

        // Incorrect answer resets interval to 1
        progress.recordPhrase("A1-L1#buenos dias", correct: false)
        phrase = try XCTUnwrap(progress.phraseProgress(for: "A1-L1#buenos dias"))
        XCTAssertEqual(phrase.interval, 1, "Incorrect answer should reset interval to 1")
    }

    func testIntervalDoublesAcrossConsecutiveCorrectAnswers() throws {
        let progress = UserProgress(languageCode: "es")
        context.insert(progress)

        // First correct: interval should be 2
        progress.recordPhrase("A1-L1#buenos dias", correct: true)
        var phrase = try XCTUnwrap(progress.phraseProgress(for: "A1-L1#buenos dias"))
        XCTAssertEqual(phrase.interval, 2, "First correct answer should set interval to 2")

        // Second correct: interval should be 4
        progress.recordPhrase("A1-L1#buenos dias", correct: true)
        phrase = try XCTUnwrap(progress.phraseProgress(for: "A1-L1#buenos dias"))
        XCTAssertEqual(phrase.interval, 4, "Second correct answer should double to 4")

        // Third correct: interval should be 8
        progress.recordPhrase("A1-L1#buenos dias", correct: true)
        phrase = try XCTUnwrap(progress.phraseProgress(for: "A1-L1#buenos dias"))
        XCTAssertEqual(phrase.interval, 8, "Third correct answer should double to 8")
    }
}
