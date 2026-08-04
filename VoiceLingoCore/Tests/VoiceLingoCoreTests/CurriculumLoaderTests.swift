import XCTest
@testable import VoiceLingoCore

final class CurriculumLoaderTests: XCTestCase {
    var loader: CurriculumLoader!

    override func setUp() {
        super.setUp()
        loader = CurriculumLoader.shared
        loader.clearCache()
    }

    override func tearDown() {
        loader.clearCache()
        super.tearDown()
    }

    // MARK: - Load Curriculum Tests

    func testLoadSpanishCurriculum() throws {
        let curriculum = try loader.loadCurriculum(for: "es")
        XCTAssertEqual(curriculum.language, "es")
        XCTAssertEqual(curriculum.voiceLocale, "es-MX")
        XCTAssertEqual(curriculum.recognizerLocale, "es-MX")
        XCTAssertFalse(curriculum.levels.isEmpty)
    }

    func testLoadedCurriculumHasValidLevels() throws {
        let curriculum = try loader.loadCurriculum(for: "es")
        let levels = curriculum.levels

        XCTAssertGreaterThan(levels.count, 0)

        for level in levels {
            XCTAssertFalse(level.id.isEmpty)
            XCTAssertFalse(level.title.isEmpty)
            XCTAssertFalse(level.lessons.isEmpty)

            for lesson in level.lessons {
                XCTAssertFalse(lesson.id.isEmpty)
                XCTAssertFalse(lesson.title.isEmpty)
                XCTAssertFalse(lesson.phrases.isEmpty)

                for phrase in lesson.phrases {
                    XCTAssertFalse(phrase.target.isEmpty)
                    XCTAssertFalse(phrase.native.isEmpty)
                    XCTAssertFalse(phrase.phonetic.isEmpty)
                }
            }
        }
    }

    func testCurriculumCaching() throws {
        let curriculum1 = try loader.loadCurriculum(for: "es")
        let curriculum2 = try loader.loadCurriculum(for: "es")

        XCTAssertEqual(curriculum1.language, curriculum2.language)
        XCTAssertEqual(curriculum1.levels.count, curriculum2.levels.count)
    }

    func testGetCachedCurriculumBeforeLoad() {
        let cached = loader.getCachedCurriculum(for: "es")
        XCTAssertNil(cached)
    }

    func testGetCachedCurriculumAfterLoad() throws {
        _ = try loader.loadCurriculum(for: "es")
        let cached = loader.getCachedCurriculum(for: "es")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.language, "es")
    }

    // MARK: - Error Handling Tests

    func testLoadNonexistentLanguage() {
        XCTAssertThrowsError(
            try loader.loadCurriculum(for: "xyz"),
            "Should throw fileNotFound error for non-existent language"
        ) { error in
            if case CurriculumLoader.CurriculumError.fileNotFound = error {
                XCTAssert(true)
            } else {
                XCTFail("Expected fileNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Cache Management Tests

    func testClearCache() throws {
        _ = try loader.loadCurriculum(for: "es")
        XCTAssertNotNil(loader.getCachedCurriculum(for: "es"))

        loader.clearCache()
        XCTAssertNil(loader.getCachedCurriculum(for: "es"))
    }

    func testClearCacheForSpecificLanguage() throws {
        _ = try loader.loadCurriculum(for: "es")
        loader.clearCache(for: "es")
        XCTAssertNil(loader.getCachedCurriculum(for: "es"))
    }

    // MARK: - Data Integrity Tests

    func testSpanishA1LevelExists() throws {
        let curriculum = try loader.loadCurriculum(for: "es")
        let a1Level = curriculum.levels.first { $0.id == "A1" }
        XCTAssertNotNil(a1Level)
    }

    func testSpanishA1HasValidLessons() throws {
        let curriculum = try loader.loadCurriculum(for: "es")
        let a1Level = curriculum.levels.first { $0.id == "A1" }
        XCTAssertNotNil(a1Level)
        XCTAssertFalse(a1Level?.lessons.isEmpty ?? true)
    }

    func testPhrasesHaveAllRequiredFields() throws {
        let curriculum = try loader.loadCurriculum(for: "es")
        let phrase = curriculum.levels
            .flatMap { $0.lessons }
            .flatMap { $0.phrases }
            .first

        XCTAssertNotNil(phrase)
        XCTAssertFalse(phrase?.target.isEmpty ?? true)
        XCTAssertFalse(phrase?.native.isEmpty ?? true)
        XCTAssertFalse(phrase?.phonetic.isEmpty ?? true)
    }

    // MARK: - Singleton Pattern Tests

    func testSharedInstanceExists() {
        let loader1 = CurriculumLoader.shared
        let loader2 = CurriculumLoader.shared
        XCTAssertTrue(loader1 === loader2)
    }

    func testSharedInstanceCache() throws {
        loader.clearCache()
        _ = try loader.loadCurriculum(for: "es")
        let cached = CurriculumLoader.shared.getCachedCurriculum(for: "es")
        XCTAssertNotNil(cached)
    }
}
