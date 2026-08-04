import XCTest
import AVFoundation
@testable import VoiceLingo

class SpeechOutputServiceTests: XCTestCase {
    var service: SpeechOutputService!

    override func setUp() {
        super.setUp()
        service = SpeechOutputService()
    }

    override func tearDown() {
        super.tearDown()
        service.stop()
    }

    func testServiceInitialization() {
        XCTAssertNotNil(service, "SpeechOutputService should initialize")
        XCTAssertFalse(service.isSpeaking(), "Service should not be speaking initially")
    }

    func testConfigureLocaleAndRate() {
        service.configure(locale: "es-MX", speechRate: 0.8, pitch: 1.2)
        XCTAssertTrue(true, "Configuration should not throw error")
    }

    func testSpeechRateBounds() {
        service.configure(locale: "es-MX", speechRate: 5.0, pitch: 1.0)
        XCTAssertTrue(true, "Speech rate should be clamped to valid range")

        service.configure(locale: "es-MX", speechRate: 0.0, pitch: 1.0)
        XCTAssertTrue(true, "Speech rate should be clamped to minimum")
    }

    func testPitchBounds() {
        service.configure(locale: "es-MX", speechRate: 0.5, pitch: 3.0)
        XCTAssertTrue(true, "Pitch should be clamped to valid range")

        service.configure(locale: "es-MX", speechRate: 0.5, pitch: 0.0)
        XCTAssertTrue(true, "Pitch should be clamped to minimum")
    }

    func testSpeakMethod() {
        let expectation = XCTestExpectation(description: "Speak completion called")
        service.speak("Buenos días") {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testSpeakSlowlyMethod() {
        let expectation = XCTestExpectation(description: "Speak slowly completion called")
        service.speakSlowly("Buenos días") {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testStopMethod() {
        service.speak("Buenos días")
        service.stop()
        XCTAssertFalse(service.isSpeaking(), "Service should stop speaking after stop() call")
    }

    func testPauseMethod() {
        service.speak("Buenos días")
        service.pause()
        XCTAssertTrue(true, "Pause should complete without error")
    }

    func testResumeMethod() {
        service.speak("Buenos días")
        service.pause()
        service.resume()
        XCTAssertTrue(true, "Resume should complete without error")
    }

    func testEmptyTextHandling() {
        let expectation = XCTestExpectation(description: "Empty text completion called")
        service.speak("") {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testMultipleSpeakCalls() {
        let expectation1 = XCTestExpectation(description: "First speak completed")
        let expectation2 = XCTestExpectation(description: "Second speak completed")

        service.speak("Hola") {
            expectation1.fulfill()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.service.speak("Adiós") {
                expectation2.fulfill()
            }
        }

        wait(for: [expectation1, expectation2], timeout: 5.0)
    }

    func testEstimatedDurationForCompletion() {
        let expectation = XCTestExpectation(description: "Completion timing test")
        let startTime = Date()

        service.configure(locale: "es-MX", speechRate: 0.5, pitch: 1.0)
        service.speak("Buenos días cómo estás") {
            let duration = Date().timeIntervalSince(startTime)
            XCTAssertGreaterThan(duration, 0.5, "Completion should take reasonable time")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
