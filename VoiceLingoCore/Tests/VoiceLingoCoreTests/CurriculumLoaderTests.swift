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

    // MARK: - Manifest Loading Tests

    func testLoadSpanishManifest() throws {
        let manifest = try loader.loadManifest(for: "es")
        XCTAssertEqual(manifest.language, "es")
        XCTAssertFalse(manifest.voiceLocale.isEmpty)
        XCTAssertFalse(manifest.recognizerLocale.isEmpty)
        XCTAssertFalse(manifest.levels.isEmpty)
    }

    func testLoadedManifestHasValidLevels() throws {
        let manifest = try loader.loadManifest(for: "es")
        let levels = manifest.levels

        XCTAssertGreaterThan(levels.count, 0)

        for level in levels {
            XCTAssertFalse(level.id.isEmpty)
            XCTAssertFalse(level.title.isEmpty)
            XCTAssertFalse(level.lessons.isEmpty)

            for lesson in level.lessons {
                XCTAssertFalse(lesson.id.isEmpty)
                XCTAssertFalse(lesson.title.isEmpty)
            }
        }
    }

    func testManifestCaching() throws {
        let manifest1 = try loader.loadManifest(for: "es")
        let manifest2 = try loader.loadManifest(for: "es")

        XCTAssertEqual(manifest1.language, manifest2.language)
        XCTAssertEqual(manifest1.levels.count, manifest2.levels.count)
    }

    func testGetCachedManifestBeforeLoad() {
        let cached = loader.getCachedManifest(for: "es")
        XCTAssertNil(cached)
    }

    func testGetCachedManifestAfterLoad() throws {
        _ = try loader.loadManifest(for: "es")
        let cached = loader.getCachedManifest(for: "es")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.language, "es")
    }

    // MARK: - Lesson Loading Tests

    func testLoadSpanishLesson() throws {
        let lesson = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        XCTAssertEqual(lesson.id, "A1-L1")
        XCTAssertEqual(lesson.title, "Greetings")
        XCTAssertFalse(lesson.phrases.isEmpty)
    }

    func testLoadedLessonHasValidPhrases() throws {
        let lesson = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        let phrases = lesson.phrases

        XCTAssertGreaterThan(phrases.count, 0)

        for phrase in phrases {
            XCTAssertFalse(phrase.target.isEmpty)
            XCTAssertFalse(phrase.native.isEmpty)
            XCTAssertFalse(phrase.phonetic.isEmpty)
        }
    }

    func testBuenosDiasEnhancedFields() throws {
        let lesson = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        guard let phrase = lesson.phrases.first(where: { $0.target == "Buenos días" }) else {
            XCTFail("Buenos días phrase not found")
            return
        }

        XCTAssertNotNil(phrase.exampleSentence)
        XCTAssertNotNil(phrase.syllables)
        XCTAssertFalse(phrase.syllables?.isEmpty ?? true)
        XCTAssertNotNil(phrase.grammarNote)
        XCTAssertNotNil(phrase.memoryHook)
        XCTAssertNotNil(phrase.vocabularyIntro)
        XCTAssertNotNil(phrase.practiceItems)
        XCTAssertFalse(phrase.practiceItems?.isEmpty ?? true)
    }

    func testA1L2BackwardCompatibility() throws {
        let lesson = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L2")
        let phrases = lesson.phrases

        // All phrases should have basic fields
        for phrase in phrases {
            XCTAssertFalse(phrase.target.isEmpty)
            XCTAssertFalse(phrase.native.isEmpty)
            XCTAssertFalse(phrase.phonetic.isEmpty)

            // Optional new fields should be nil for A1-L2
            XCTAssertNil(phrase.exampleSentence)
            XCTAssertNil(phrase.syllables)
            XCTAssertNil(phrase.grammarNote)
        }
    }

    func testLessonCaching() throws {
        let lesson1 = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        let lesson2 = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")

        XCTAssertEqual(lesson1.id, lesson2.id)
        XCTAssertEqual(lesson1.phrases.count, lesson2.phrases.count)
    }

    func testGetCachedLessonBeforeLoad() {
        let cached = loader.getCachedLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        XCTAssertNil(cached)
    }

    func testGetCachedLessonAfterLoad() throws {
        _ = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        let cached = loader.getCachedLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.id, "A1-L1")
    }

    func testLessonDialogue() throws {
        let lesson = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        XCTAssertNotNil(lesson.dialogue)
        XCTAssertGreaterThan(lesson.dialogue?.turns.count ?? 0, 0)
        if let firstTurn = lesson.dialogue?.turns.first {
            XCTAssertEqual(firstTurn.speaker, .npc)
        }
    }

    // MARK: - Manifest Integrity Tests

    func testAllManifestLessonsLoadAndAreUnique() throws {
        let manifest = try loader.loadManifest(for: "es")
        var seenLessonIds = Set<String>()

        for level in manifest.levels {
            for lesson in level.lessons {
                // Assert lesson ID is unique
                if seenLessonIds.contains(lesson.id) {
                    XCTFail("Duplicate lesson ID found: \(lesson.id)")
                }
                seenLessonIds.insert(lesson.id)

                // Load the lesson and assert it doesn't throw
                do {
                    let loadedLesson = try loader.loadLesson(language: "es", levelId: level.id, lessonId: lesson.id)

                    // Assert the loaded lesson's id matches the manifest
                    XCTAssertEqual(loadedLesson.id, lesson.id)

                    // Assert the lesson has at least 10 phrases
                    XCTAssertGreaterThanOrEqual(loadedLesson.phrases.count, 10)
                } catch {
                    XCTFail("Failed to load lesson \(lesson.id) from level \(level.id): \(error)")
                }
            }
        }
    }

    // MARK: - Error Handling Tests

    func testLoadNonexistentLanguageManifest() {
        XCTAssertThrowsError(
            try loader.loadManifest(for: "xyz"),
            "Should throw manifestNotFound error for non-existent language"
        ) { error in
            if case CurriculumLoader.CurriculumError.manifestNotFound = error {
                XCTAssert(true)
            } else {
                XCTFail("Expected manifestNotFound error, got \(error)")
            }
        }
    }

    func testLoadNonexistentLesson() {
        XCTAssertThrowsError(
            try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L99"),
            "Should throw lessonNotFound error for non-existent lesson"
        ) { error in
            if case CurriculumLoader.CurriculumError.lessonNotFound = error {
                XCTAssert(true)
            } else {
                XCTFail("Expected lessonNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Cache Management Tests

    func testClearAllCache() throws {
        _ = try loader.loadManifest(for: "es")
        _ = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")

        XCTAssertNotNil(loader.getCachedManifest(for: "es"))
        XCTAssertNotNil(loader.getCachedLesson(language: "es", levelId: "A1", lessonId: "A1-L1"))

        loader.clearCache()

        XCTAssertNil(loader.getCachedManifest(for: "es"))
        XCTAssertNil(loader.getCachedLesson(language: "es", levelId: "A1", lessonId: "A1-L1"))
    }

    func testClearCacheForSpecificLanguage() throws {
        _ = try loader.loadManifest(for: "es")
        _ = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        _ = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L2")

        loader.clearCache(for: "es")

        XCTAssertNil(loader.getCachedManifest(for: "es"))
        XCTAssertNil(loader.getCachedLesson(language: "es", levelId: "A1", lessonId: "A1-L1"))
        XCTAssertNil(loader.getCachedLesson(language: "es", levelId: "A1", lessonId: "A1-L2"))
    }

    // MARK: - Data Integrity Tests

    func testSpanishA1LevelExists() throws {
        let manifest = try loader.loadManifest(for: "es")
        let a1Level = manifest.levels.first { $0.id == "A1" }
        XCTAssertNotNil(a1Level)
    }

    func testSpanishA1HasValidLessons() throws {
        let manifest = try loader.loadManifest(for: "es")
        let a1Level = manifest.levels.first { $0.id == "A1" }
        XCTAssertNotNil(a1Level)
        XCTAssertFalse(a1Level?.lessons.isEmpty ?? true)
    }

    // MARK: - Stable Phrase Key Tests

    func testProgressKeyIsStableAcrossDecodes() throws {
        // Load A1-L1 twice, clearing cache between loads
        let lesson1 = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        let firstPhrase1 = lesson1.phrases.first
        let key1 = firstPhrase1?.progressKey(inLesson: "A1-L1")

        loader.clearCache()

        let lesson2 = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        let firstPhrase2 = lesson2.phrases.first
        let key2 = firstPhrase2?.progressKey(inLesson: "A1-L1")

        XCTAssertEqual(key1, key2,
                       "Progress key must be identical across decodes")
        XCTAssertNotEqual(firstPhrase1?.id, firstPhrase2?.id,
                          "UUID should differ between decodes (proving it's not stable)")
    }

    // MARK: - Singleton Pattern Tests

    func testSharedInstanceExists() {
        let loader1 = CurriculumLoader.shared
        let loader2 = CurriculumLoader.shared
        XCTAssertTrue(loader1 === loader2)
    }

    func testSharedInstanceManifestCache() throws {
        loader.clearCache()
        _ = try loader.loadManifest(for: "es")
        let cached = CurriculumLoader.shared.getCachedManifest(for: "es")
        XCTAssertNotNil(cached)
    }

    func testSharedInstanceLessonCache() throws {
        loader.clearCache()
        _ = try loader.loadLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        let cached = CurriculumLoader.shared.getCachedLesson(language: "es", levelId: "A1", lessonId: "A1-L1")
        XCTAssertNotNil(cached)
    }

    // MARK: - Dialogue Content Integrity

    func testDialogueContentIntegrity() throws {
        let manifest = try loader.loadManifest(for: "es")
        for level in manifest.levels {
            for lesson in level.lessons {
                let loadedLesson = try loader.loadLesson(language: "es", levelId: level.id, lessonId: lesson.id)
                guard let dialogue = loadedLesson.dialogue else { continue }

                for (index, turn) in dialogue.turns.enumerated() {
                    if turn.speaker == .learner {
                        XCTAssertFalse(turn.hints?.isEmpty ?? true,
                                       "Learner turn \(index) in \(lesson.id) must have non-empty hints")
                    } else if turn.speaker == .npc {
                        XCTAssertFalse(turn.line?.isEmpty ?? true,
                                       "NPC turn \(index) in \(lesson.id) must have non-empty line")
                    }
                }
            }
        }
    }
}
