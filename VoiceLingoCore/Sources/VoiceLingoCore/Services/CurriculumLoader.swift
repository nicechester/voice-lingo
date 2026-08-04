import Foundation

public class CurriculumLoader {
    public nonisolated(unsafe) static let shared = CurriculumLoader()

    private var cache: [String: Curriculum] = [:]
    private let decoder = JSONDecoder()
    private let cacheLock = NSLock()

    private init() {}

    public enum CurriculumError: LocalizedError {
        case fileNotFound(language: String)
        case invalidJSON(language: String)
        case decodingFailed(language: String, underlying: Error)
        case unknownError(language: String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let language):
                return "Curriculum file not found for language: \(language)"
            case .invalidJSON(let language):
                return "Invalid JSON in curriculum file for language: \(language)"
            case .decodingFailed(let language, let error):
                return "Failed to decode curriculum for language \(language): \(error.localizedDescription)"
            case .unknownError(let language):
                return "Unknown error loading curriculum for language: \(language)"
            }
        }
    }

    /// Loads a curriculum for the specified language code.
    /// Results are cached for subsequent calls.
    /// - Parameter language: Language code (e.g., "es" for Spanish)
    /// - Returns: Curriculum object
    /// - Throws: CurriculumError if loading or parsing fails
    public func loadCurriculum(for language: String) throws -> Curriculum {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cache[language] {
            return cached
        }

        let curriculum = try loadFromFile(language: language)
        cache[language] = curriculum
        return curriculum
    }

    /// Retrieves a cached curriculum without attempting to reload.
    /// - Parameter language: Language code
    /// - Returns: Cached curriculum, or nil if not loaded
    public func getCachedCurriculum(for language: String) -> Curriculum? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[language]
    }

    /// Clears the curriculum cache.
    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeAll()
    }

    /// Clears the cache for a specific language.
    /// - Parameter language: Language code
    public func clearCache(for language: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeValue(forKey: language)
    }

    // MARK: - Private

    private func loadFromFile(language: String) throws -> Curriculum {
        let bundle = Bundle.module

        guard let url = bundle.url(
            forResource: "curriculum",
            withExtension: "json",
            subdirectory: "Content/\(language)"
        ) ?? bundle.url(
            forResource: "curriculum",
            withExtension: "json"
        ) else {
            throw CurriculumError.fileNotFound(language: language)
        }

        if language != "es" && url.path.contains("/Content/") == false {
            throw CurriculumError.fileNotFound(language: language)
        }

        do {
            let data = try Data(contentsOf: url)
            let curriculum = try decoder.decode(Curriculum.self, from: data)
            return curriculum
        } catch let error as DecodingError {
            throw CurriculumError.decodingFailed(language: language, underlying: error)
        } catch {
            throw CurriculumError.unknownError(language: language)
        }
    }
}
