import Speech
import AVFoundation

#if os(iOS)
public final class SpeechRecognitionService: @unchecked Sendable {
    static let shared = SpeechRecognitionService()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var currentLocale: String = "es-MX"
    private var lastRecognizedText: String = ""

    public init() {
        requestMicrophonePermission()
    }

    public func setLocale(_ locale: String) {
        currentLocale = locale
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

        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let recognitionRequest = recognitionRequest else {
                onError(SpeechRecognitionError.requestInitializationFailed)
                return
            }

            recognitionRequest.shouldReportPartialResults = true

            if let inputNode = audioEngine.inputNode as AVAudioInputNode? {
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    recognitionRequest.append(buffer)
                }

                audioEngine.prepare()
                try audioEngine.start()

                recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                    var isFinal = false

                    if let result = result {
                        isFinal = result.isFinal
                        let recognizedText = result.bestTranscription.formattedString
                        self.lastRecognizedText = recognizedText
                        onResult(recognizedText)

                        if isFinal {
                            self.stopRecognition()
                        }
                    }

                    if let error = error {
                        self.stopRecognition()
                        onError(error)
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    if self.recognitionTask != nil {
                        self.stopRecognition()
                        if !self.lastRecognizedText.isEmpty {
                            onResult(self.lastRecognizedText)
                        }
                    }
                }
            }
        } catch {
            onError(error)
        }
    }

    public func stopRecognition() {
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        audioEngine.stop()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }

    public func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
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

    public var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .requestInitializationFailed:
            return "Failed to initialize speech recognition request"
        case .audioSessionError:
            return "Failed to configure audio session"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}
#endif
