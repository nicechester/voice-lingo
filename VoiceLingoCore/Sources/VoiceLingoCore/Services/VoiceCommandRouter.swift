import Foundation
import Speech
import OSLog

private let routerLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceLingo", category: "VoiceCommandRouter")
private let routerTsFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

private func routerLog(_ message: String) {
    let ts = routerTsFormatter.string(from: Date())
    routerLogger.info("[\(ts, privacy: .public)] \(message, privacy: .public)")
}

#if os(iOS)
public enum VoiceCommand: String, Equatable, Sendable {
    case startLesson = "start lesson"
    case review = "review"
    case `continue` = "continue"
    case changeLanguage = "change language"
    case `repeat` = "repeat"
    case help = "help"
    case skip = "skip"
    case stop = "stop"

    public func normalized() -> String {
        self.rawValue.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)
    }
}

public final class VoiceCommandRouter: @unchecked Sendable {
    public nonisolated(unsafe) static let shared = VoiceCommandRouter()

    private let speechRecognitionService = SpeechRecognitionService()
    private var commandCallbacks: [(VoiceCommand) -> Void] = []
    private var isListening = false
    private var isSuspended = false
    private var currentLocale: String = "es-MX"
    private let callbackLock = NSLock()

    private init() {
        requestPermissions()
        speechRecognitionService.setLocale("en-US")
    }

    public func setLocale(_ locale: String) {
        currentLocale = locale
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
        isSuspended = false
        speechRecognitionService.stopRecognition()
    }

    public func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        speechRecognitionService.stopRecognition()
    }

    public func resume() {
        guard isSuspended else { return }
        isSuspended = false
        listenForCommands()
    }

    public func isCurrentlyListening() -> Bool {
        isListening
    }

    public func requestPermissions() {
        speechRecognitionService.requestMicrophonePermission()
    }

    // MARK: - Private

    private func listenForCommands() {
        guard isListening, !isSuspended else { return }

        speechRecognitionService.recognize(timeout: 10.0) { [weak self] (recognizedText: String) in
            guard let self = self else { return }
            routerLog("Recognized: \"\(recognizedText)\"")
            self.processRecognizedText(recognizedText)
        } onError: { [weak self] (error: Error) in
            guard let self = self else { return }
            let nsError = error as NSError
            if nsError.code != 1110 {
                routerLog("Voice command recognition error: \(error.localizedDescription)")
            }
            let isNoSpeech = (error as? SpeechRecognitionError) == .noSpeechDetected
            let delay: Double = nsError.code == 1101 ? 2.0 : 0.5
            if isNoSpeech {
                DispatchQueue.main.async {
                    SpeechOutputService.shared.speak("Say again.", locale: "en-US", suspendRouter: false) { [weak self] in
                        self?.scheduleNextListen(delay: 0.5)
                    }
                }
            } else {
                self.scheduleNextListen(delay: delay)
            }
        }
    }

    private func processRecognizedText(_ text: String) {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .folding(options: .diacriticInsensitive, locale: .current)

        let commands: [VoiceCommand] = [.startLesson, .review, .continue, .changeLanguage, .repeat, .help, .skip, .stop]
        let aliases: [String: VoiceCommand] = ["start listening": .startLesson]

        for command in commands {
            if normalized.contains(command.normalized()) || command.normalized().contains(normalized) {
                callbackLock.lock()
                let callbacks = commandCallbacks
                callbackLock.unlock()
                for callback in callbacks { callback(command) }
                break
            }
        }

        if let matched = aliases.first(where: { normalized.contains($0.key) }) {
            callbackLock.lock()
            let callbacks = commandCallbacks
            callbackLock.unlock()
            for callback in callbacks { callback(matched.value) }
        }

        scheduleNextListen()
    }

    private func scheduleNextListen(delay: Double = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            if self?.isListening == true {
                self?.listenForCommands()
            }
        }
    }
}

#endif
