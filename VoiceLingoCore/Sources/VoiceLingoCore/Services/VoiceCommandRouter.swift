import Foundation
import Speech

#if os(iOS)
public enum VoiceCommand: String, Equatable, Sendable {
    case startLesson = "start lesson"
    case review = "review"
    case `continue` = "continue"
    case changeLanguage = "change language"
    case `repeat` = "repeat"
    case help = "help"
    case skip = "skip"

    public func normalized() -> String {
        self.rawValue.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}

public final class VoiceCommandRouter: @unchecked Sendable {
    public nonisolated(unsafe) static let shared = VoiceCommandRouter()

    private let speechRecognitionService = SpeechRecognitionService.shared
    private var commandCallbacks: [(VoiceCommand) -> Void] = []
    private var isListening = false
    private var currentLocale: String = "es-MX"
    private let callbackLock = NSLock()

    private init() {
        requestPermissions()
    }

    public func setLocale(_ locale: String) {
        currentLocale = locale
        speechRecognitionService.setLocale(locale)
    }

    public func startListening(onCommand: @escaping (VoiceCommand) -> Void) {
        callbackLock.lock()
        commandCallbacks.append(onCommand)
        callbackLock.unlock()

        if isListening {
            return
        }

        isListening = true
        listenForCommands()
    }

    public func stopListening() {
        isListening = false
        speechRecognitionService.stopRecognition()
    }

    public func isCurrentlyListening() -> Bool {
        isListening
    }

    public func requestPermissions() {
        speechRecognitionService.requestMicrophonePermission()
    }

    // MARK: - Private

    private func listenForCommands() {
        guard isListening else { return }

        speechRecognitionService.recognize(timeout: 10.0) { [weak self] (recognizedText: String) in
            guard let self = self else { return }
            self.processRecognizedText(recognizedText)
        } onError: { [weak self] (error: Error) in
            guard let self = self else { return }
            print("Voice command recognition error: \(error)")
            self.scheduleNextListen()
        }
    }

    private func processRecognizedText(_ text: String) {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)

        let commands: [VoiceCommand] = [.startLesson, .review, .continue, .changeLanguage, .repeat, .help, .skip]

        for command in commands {
            if normalized.contains(command.normalized()) || command.normalized().contains(normalized) {
                callbackLock.lock()
                let callbacks = commandCallbacks
                callbackLock.unlock()

                for callback in callbacks {
                    callback(command)
                }
                break
            }
        }

        scheduleNextListen()
    }

    private func scheduleNextListen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.isListening == true {
                self?.listenForCommands()
            }
        }
    }
}

#endif
