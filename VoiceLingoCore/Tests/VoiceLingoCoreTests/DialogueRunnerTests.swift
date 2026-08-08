import XCTest
@testable import VoiceLingoCore

final class DialogueRunnerTests: XCTestCase {

    // MARK: - Step Sequencing Tests

    func testStartReturnsIntroduceScenario() {
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test scenario",
            turns: []
        )
        let runner = DialogueRunner(scenario: scenario)
        let step = runner.start()
        XCTAssertEqual(step, .introduceScenario("Test scenario"))
    }

    func testAdvanceOnEmptyTurnsReturnsFinished() {
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test scenario",
            turns: []
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        let step = runner.advance()
        XCTAssertEqual(step, .finished)
    }

    func testAdvanceYieldsNPCLineForNPCTurn() {
        let turn = DialogueTurn(
            speaker: .npc,
            line: "Hola",
            native: "Hello"
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        let step = runner.advance()
        if case .npcLine(let text, let native) = step {
            XCTAssertEqual(text, "Hola")
            XCTAssertEqual(native, "Hello")
        } else {
            XCTFail("Expected npcLine step")
        }
    }

    func testAdvanceYieldsAwaitLearnerForLearnerTurn() {
        let turn = DialogueTurn(
            speaker: .learner,
            hints: ["Estoy bien"]
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        let step = runner.advance()
        if case .awaitLearner(_, let candidates, _, _) = step {
            XCTAssertEqual(candidates, ["Estoy bien"])
        } else {
            XCTFail("Expected awaitLearner step")
        }
    }

    // MARK: - Matching Behavior Tests

    func testSubmitWithMatchReturnsMatched() {
        let turn = DialogueTurn(
            speaker: .learner,
            hints: ["Estoy bien"]
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        _ = runner.advance()
        let outcome = runner.submit(recognized: "estoy bien")
        if case .matched(let candidate) = outcome {
            XCTAssertEqual(candidate, "Estoy bien")
        } else {
            XCTFail("Expected matched outcome")
        }
    }

    func testSubmitWithNoMatchReturnsRetryOnFirstAttempt() {
        let turn = DialogueTurn(
            speaker: .learner,
            hints: ["Estoy bien"]
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        _ = runner.advance()
        let outcome = runner.submit(recognized: "hola")
        if case .retry(let remaining, let modelAnswer) = outcome {
            XCTAssertEqual(remaining, 1)
            XCTAssertEqual(modelAnswer, "Estoy bien")
        } else {
            XCTFail("Expected retry outcome on first attempt")
        }
    }

    func testSubmitWithNoMatchReturnsMovedOnOnSecondAttempt() {
        let turn = DialogueTurn(
            speaker: .learner,
            hints: ["Estoy bien"]
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        _ = runner.advance()
        _ = runner.submit(recognized: "hola")  // First miss
        let outcome = runner.submit(recognized: "adios")  // Second miss
        if case .movedOn(let modelAnswer) = outcome {
            XCTAssertEqual(modelAnswer, "Estoy bien")
        } else {
            XCTFail("Expected movedOn outcome on second attempt")
        }
    }

    // MARK: - Open Response Tests

    func testOpenResponseTurnReturnsOpenAccepted() {
        let turn = DialogueTurn(
            speaker: .learner,
            hints: ["Soy de Chicago"],
            openResponse: true
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        _ = runner.advance()
        let outcome = runner.submit(recognized: "Soy de Los Angeles")
        if case .openAccepted(let text) = outcome {
            XCTAssertEqual(text, "Soy de Los Angeles")
        } else {
            XCTFail("Expected openAccepted outcome")
        }
    }

    func testEmptyHintsReturnsOpenAccepted() {
        let turn = DialogueTurn(
            speaker: .learner,
            hints: []
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        _ = runner.advance()
        let outcome = runner.submit(recognized: "anything")
        if case .openAccepted = outcome {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected openAccepted for empty hints")
        }
    }

    // MARK: - Integration Tests

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
        let lesson = try CurriculumLoader.shared.loadLesson(language: "es",
                                                           levelId: "A1", lessonId: "A1-L1")
        let scenario = try XCTUnwrap(lesson.dialogue)
        let runner = DialogueRunner(scenario: scenario)

        _ = runner.start()
        var step = runner.advance()
        var guardCounter = 0
        while step != .finished, guardCounter < 50 {
            guardCounter += 1
            if case .awaitLearner = step {
                _ = runner.submit(recognized: "")
            }
            step = runner.advance()
        }
        XCTAssertEqual(step, .finished,
                       "A learner who says nothing must never strand the session")
    }

    // MARK: - Accuracy Tests

    func testAccuracyCalculation() {
        let turn = DialogueTurn(
            speaker: .learner,
            hints: ["Estoy bien"]
        )
        let scenario = DialogueScenario(
            id: "test",
            scenario: "Test",
            turns: [turn]
        )
        let runner = DialogueRunner(scenario: scenario)
        _ = runner.start()
        _ = runner.advance()
        _ = runner.submit(recognized: "estoy bien")
        XCTAssertEqual(runner.accuracy, 1.0)
    }
}
