import Speech
import AVFoundation

#if os(iOS)
public final class SpeechRecognitionService: @unchecked Sendable {
    public static let shared = SpeechRecognitionService()

    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentLocale: String = "es-MX"
    private var lastRecognizedText: String = ""
    private var isTapInstalled = false
    public init() {
        requestMicrophonePermission()
    }

    public func setLocale(_ locale: String) {
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
    }

    public func requestMicrophonePermission() {
        SFSpeechRecognizer.requestAuthorization { authorizationStatus in
            switch authorizationStatus {
            case .authorized:
                print("Speech recognition authorized")
            case .denied:
                print("User denied speech recognition permission")
            case .restricted:
                print("Speech recognition restricted")
            case .notDetermined:
                print("Speech recognition permission not yet requested")
            @unknown default:
                break
            }
        }
    }

    public func recognize(timeout: TimeInterval = 5.0, onResult: @escaping @Sendable (String) -> Void, onError: @escaping @Sendable (Error) -> Void) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            onError(SpeechRecognitionError.recognizerUnavailable)
            return
        }

        stopRecognition()
        lastRecognizedText = ""

        var finished = false
        func finish(result: String?, error: Error?) {
            guard !finished else { return }
            finished = true
            self.stopRecognition()
            if let result { onResult(result) }
            else if let error { onError(error) }
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .duckOthers])
            try audioSession.setActive(true)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                onError(SpeechRecognitionError.requestInitializationFailed)
                return
            }
            recognitionRequest.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            if !isTapInstalled {
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    recognitionRequest.append(buffer)
                }
                isTapInstalled = true
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result {
                    self.lastRecognizedText = result.bestTranscription.formattedString
                    if result.isFinal {
                        finish(result: self.lastRecognizedText, error: nil)
                    }
                }
                if let error {
                    let nsError = error as NSError
                    if nsError.code == 1110 { return }
                    finish(result: self.lastRecognizedText.isEmpty ? nil : self.lastRecognizedText, error: self.lastRecognizedText.isEmpty ? error : nil)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if self.lastRecognizedText.isEmpty {
                    finish(result: nil, error: SpeechRecognitionError.noSpeechDetected)
                } else {
                    finish(result: self.lastRecognizedText, error: nil)
                }
            }
        } catch {
            onError(error)
        }
    }

    public func stopRecognition() {
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    public func cancelRecognition() {
        stopRecognition()
    }

    public func isRecognizing() -> Bool {
        recognitionTask?.state == .running
    }
}

#endif

#if os(iOS)
public enum SpeechRecognitionError: LocalizedError {
    case recognizerUnavailable
    case requestInitializationFailed
    case audioSessionError
    case permissionDenied
    case noSpeechDetected

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer is not available"
        case .requestInitializationFailed: return "Failed to initialize speech recognition request"
        case .audioSessionError: return "Failed to configure audio session"
        case .permissionDenied: return "Microphone permission denied"
        case .noSpeechDetected: return "No speech detected"
        }
    }
}
#endif
