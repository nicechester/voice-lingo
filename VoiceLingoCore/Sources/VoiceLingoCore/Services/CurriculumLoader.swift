import Foundation

public class CurriculumLoader {
    public nonisolated(unsafe) static let shared = CurriculumLoader()

    private var manifestCache: [String: CurriculumManifest] = [:]
    private var lessonCache: [String: Lesson] = [:]   // key: "\(language)/\(levelId)/\(lessonId)"
    private var speechBankCache: [String: SpeechBank] = [:]
    private let decoder = JSONDecoder()
    private let cacheLock = NSLock()

    private init() {}

    public enum CurriculumError: LocalizedError {
        case manifestNotFound(language: String)
        case lessonNotFound(language: String, levelId: String, lessonId: String)
        case decodingFailed(language: String, underlying: Error)
        case unknownError(language: String)

        public var errorDescription: String? {
            switch self {
            case .manifestNotFound(let language):
                return "Curriculum manifest not found for language: \(language)"
            case .lessonNotFound(let language, let levelId, let lessonId):
                return "Lesson not found: \(language)/\(levelId)/\(lessonId)"
            case .decodingFailed(let language, let error):
                return "Failed to decode curriculum content for language \(language): \(error.localizedDescription)"
            case .unknownError(let language):
                return "Unknown error loading curriculum for language: \(language)"
            }
        }
    }

    /// Loads a curriculum manifest for the specified language code.
    /// Results are cached for subsequent calls.
    /// - Parameter language: Language code (e.g., "es" for Spanish)
    /// - Returns: CurriculumManifest object
    /// - Throws: CurriculumError if loading or parsing fails
    public func loadManifest(for language: String) throws -> CurriculumManifest {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = manifestCache[language] {
            return cached
        }

        let manifest = try loadManifestFromFile(language: language)
        manifestCache[language] = manifest
        return manifest
    }

    /// Retrieves a cached manifest without attempting to reload.
    /// - Parameter language: Language code
    /// - Returns: Cached manifest, or nil if not loaded
    public func getCachedManifest(for language: String) -> CurriculumManifest? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return manifestCache[language]
    }

    /// Loads a lesson for the specified language, level, and lesson IDs.
    /// Results are cached for subsequent calls.
    /// - Parameters:
    ///   - language: Language code
    ///   - levelId: Level identifier
    ///   - lessonId: Lesson identifier
    /// - Returns: Lesson object
    /// - Throws: CurriculumError if loading or parsing fails
    public func loadLesson(language: String, levelId: String, lessonId: String) throws -> Lesson {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let cacheKey = "\(language)/\(levelId)/\(lessonId)"
        if let cached = lessonCache[cacheKey] {
            return cached
        }

        let lesson = try loadLessonFromFile(language: language, levelId: levelId, lessonId: lessonId)
        lessonCache[cacheKey] = lesson
        return lesson
    }

    /// Retrieves a cached lesson without attempting to reload.
    /// - Parameters:
    ///   - language: Language code
    ///   - levelId: Level identifier
    ///   - lessonId: Lesson identifier
    /// - Returns: Cached lesson, or nil if not loaded
    public func getCachedLesson(language: String, levelId: String, lessonId: String) -> Lesson? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let cacheKey = "\(language)/\(levelId)/\(lessonId)"
        return lessonCache[cacheKey]
    }

    /// Loads `Content/{language}/speech-bank.json`, or nil if the language has no bank.
    ///
    /// Returns nil rather than throwing: the bank is a presentation nicety, and a missing or
    /// malformed bank must degrade to the app's built-in fallback strings, never to a crash
    /// or a silent session.
    public func loadSpeechBank(for language: String) -> SpeechBank? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = speechBankCache[language] { return cached }
        guard let bank = try? loadSpeechBankFromFile(language: language) else { return nil }
        speechBankCache[language] = bank
        return bank
    }

    /// Clears all cached manifests, lessons, and speech banks.
    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        manifestCache.removeAll()
        lessonCache.removeAll()
        speechBankCache.removeAll()
    }

    /// Clears the cache for a specific language (manifest + all lessons + speech bank for that language).
    /// - Parameter language: Language code
    public func clearCache(for language: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        manifestCache.removeValue(forKey: language)
        speechBankCache.removeValue(forKey: language)
        // Remove all lesson cache keys that start with this language
        let keysToRemove = lessonCache.keys.filter { $0.hasPrefix("\(language)/") }
        keysToRemove.forEach { lessonCache.removeValue(forKey: $0) }
    }

    // MARK: - Private

    private func loadManifestFromFile(language: String) throws -> CurriculumManifest {
        let bundle = Bundle.module

        // Try to load from language-specific subdirectory first
        if let url = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "Content/\(language)"
        ), url.path.contains("/Content/\(language)/") {
            do {
                let data = try Data(contentsOf: url)
                let manifest = try decoder.decode(CurriculumManifest.self, from: data)
                return manifest
            } catch let error as DecodingError {
                throw CurriculumError.decodingFailed(language: language, underlying: error)
            } catch {
                throw CurriculumError.unknownError(language: language)
            }
        }

        // Fallback for SwiftPM bundle flattening: SPM flattens all Content/ resources
        // to the bundle root, so look up the resource by name directly. Since manifest.json
        // is not language-scoped in the flattened bundle, verify the decoded manifest
        // actually matches the requested language before returning it.
        if let url = bundle.url(
            forResource: "manifest",
            withExtension: "json"
        ), url.path.contains("/manifest.json") {
            do {
                let data = try Data(contentsOf: url)
                let manifest = try decoder.decode(CurriculumManifest.self, from: data)
                if manifest.language == language {
                    return manifest
                }
            } catch let error as DecodingError {
                throw CurriculumError.decodingFailed(language: language, underlying: error)
            } catch {
                throw CurriculumError.unknownError(language: language)
            }
        }

        throw CurriculumError.manifestNotFound(language: language)
    }

    private func loadLessonFromFile(language: String, levelId: String, lessonId: String) throws -> Lesson {
        let bundle = Bundle.module

        // Try to load from language/level-specific subdirectory first
        if let url = bundle.url(
            forResource: lessonId,
            withExtension: "json",
            subdirectory: "Content/\(language)/\(levelId)"
        ), url.path.contains("/Content/\(language)/\(levelId)/") {
            do {
                let data = try Data(contentsOf: url)
                let lesson = try decoder.decode(Lesson.self, from: data)
                return lesson
            } catch let error as DecodingError {
                throw CurriculumError.decodingFailed(language: language, underlying: error)
            } catch {
                throw CurriculumError.unknownError(language: language)
            }
        }

        // Fallback for SwiftPM bundle flattening: SPM flattens all Content/ resources
        // to the bundle root, so look up the resource by name directly.
        if let url = bundle.url(
            forResource: lessonId,
            withExtension: "json"
        ), url.path.contains("/\(lessonId).json") {
            do {
                let data = try Data(contentsOf: url)
                let lesson = try decoder.decode(Lesson.self, from: data)
                return lesson
            } catch let error as DecodingError {
                throw CurriculumError.decodingFailed(language: language, underlying: error)
            } catch {
                throw CurriculumError.unknownError(language: language)
            }
        }

        throw CurriculumError.lessonNotFound(language: language, levelId: levelId, lessonId: lessonId)
    }

    private func loadSpeechBankFromFile(language: String) throws -> SpeechBank {
        let bundle = Bundle.module

        // Try to load from language-specific subdirectory first
        if let url = bundle.url(
            forResource: "speech-bank",
            withExtension: "json",
            subdirectory: "Content/\(language)"
        ), url.path.contains("/Content/\(language)/") {
            do {
                let data = try Data(contentsOf: url)
                let bank = try decoder.decode(SpeechBank.self, from: data)
                if bank.language == language {
                    return bank
                }
            } catch let error as DecodingError {
                throw CurriculumError.decodingFailed(language: language, underlying: error)
            } catch {
                throw CurriculumError.unknownError(language: language)
            }
        }

        // Fallback for SwiftPM bundle flattening: SPM flattens all Content/ resources
        // to the bundle root, so look up the resource by name directly. Since speech-bank.json
        // is language-scoped but flattens to the bundle root, verify the decoded bank
        // actually matches the requested language before accepting it.
        if let url = bundle.url(
            forResource: "speech-bank",
            withExtension: "json"
        ), url.path.contains("/speech-bank.json") {
            do {
                let data = try Data(contentsOf: url)
                let bank = try decoder.decode(SpeechBank.self, from: data)
                if bank.language == language {
                    return bank
                }
            } catch let error as DecodingError {
                throw CurriculumError.decodingFailed(language: language, underlying: error)
            } catch {
                throw CurriculumError.unknownError(language: language)
            }
        }

        throw CurriculumError.unknownError(language: language)
    }
}
