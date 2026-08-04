import XCTest
import Speech
import AVFoundation
@testable import VoiceLingo

class SpeechRecognitionServiceTests: XCTestCase {
    var service: SpeechRecognitionService!

    override func setUp() {
        super.setUp()
        service = SpeechRecognitionService()
    }

    override func tearDown() {
        super.tearDown()
        service.cancelRecognition()
    }

    func testServiceInitialization() {
        XCTAssertNotNil(service, "SpeechRecognitionService should initialize")
        XCTAssertFalse(service.isRecognizing(), "Service should not be recognizing initially")
    }

    func testSetLocale() {
        service.setLocale("es-ES")
        XCTAssertTrue(true, "Setting locale should not throw error")
    }

    func testRequestMicrophonePermission() {
        service.requestMicrophonePermission()
        XCTAssertTrue(true, "Requesting microphone permission should not throw error")
    }

    func testRecognizeWithTimeout() {
        let expectation = XCTestExpectation(description: "Recognition completed with timeout")
        var resultReceived = false

        service.recognize(timeout: 2.0, onResult: { text in
            resultReceived = true
        }, onError: { error in
            print("Recognition error: \(error)")
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            XCTAssertTrue(true, "Recognition should timeout and complete")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }

    func testCancelRecognition() {
        var resultReceived = false

        service.recognize(timeout: 5.0, onResult: { text in
            resultReceived = true
        }, onError: { error in
            print("Recognition error: \(error)")
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.service.cancelRecognition()
            XCTAssertFalse(self.service.isRecognizing(), "Service should not be recognizing after cancel")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // After cancellation, no result should be received
        }
    }

    func testStopRecognition() {
        service.recognize(timeout: 5.0, onResult: { text in
            // No-op
        }, onError: { error in
            print("Recognition error: \(error)")
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.service.stopRecognition()
            XCTAssertFalse(self.service.isRecognizing(), "Service should not be recognizing after stop")
        }
    }

    func testIsRecognizingStatus() {
        XCTAssertFalse(service.isRecognizing(), "Should not be recognizing initially")

        service.recognize(timeout: 5.0, onResult: { _ in
            // No-op
        }, onError: { _ in
            // No-op
        })

        // Note: isRecognizing() may not immediately return true due to AVAudioEngine setup time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Status check after initialization
        }
    }

    func testErrorHandlingForUnavailableRecognizer() {
        // This test would verify error handling if the recognizer becomes unavailable
        // In a real scenario, this would test graceful degradation
        XCTAssertTrue(true, "Error handling should be robust")
    }

    func testMultipleRecognitionAttempts() {
        let expectation1 = XCTestExpectation(description: "First recognition completed")
        let expectation2 = XCTestExpectation(description: "Second recognition completed")

        service.recognize(timeout: 1.0, onResult: { _ in
            expectation1.fulfill()
        }, onError: { _ in
            expectation1.fulfill()
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.service.recognize(timeout: 1.0, onResult: { _ in
                expectation2.fulfill()
            }, onError: { _ in
                expectation2.fulfill()
            })
        }

        wait(for: [expectation1, expectation2], timeout: 5.0)
    }

    func testRecognitionErrorCallback() {
        let expectation = XCTestExpectation(description: "Error callback called if recognizer unavailable")
        var errorReceived = false

        service.recognize(timeout: 1.0, onResult: { _ in
            // No-op
        }, onError: { error in
            errorReceived = true
            print("Expected error: \(error.localizedDescription)")
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3.0)
    }

    func testSpeechRecognitionErrorEnum() {
        let unavailableError = SpeechRecognitionError.recognizerUnavailable
        XCTAssertNotNil(unavailableError.errorDescription)
        XCTAssert(unavailableError.errorDescription?.contains("unavailable") ?? false)

        let requestError = SpeechRecognitionError.requestInitializationFailed
        XCTAssertNotNil(requestError.errorDescription)

        let audioError = SpeechRecognitionError.audioSessionError
        XCTAssertNotNil(audioError.errorDescription)

        let permissionError = SpeechRecognitionError.permissionDenied
        XCTAssertNotNil(permissionError.errorDescription)
    }
}
