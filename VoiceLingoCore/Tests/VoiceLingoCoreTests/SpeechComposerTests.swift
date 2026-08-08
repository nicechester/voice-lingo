import XCTest
@testable import VoiceLingoCore

final class SpeechComposerTests: XCTestCase {

    private func makeBank() -> SpeechBank {
        SpeechBank(
            language: "es",
            pools: [
                SpeechAct.praise.rawValue: [
                    SpeechVariant(text: "A", locale: "en-US"),
                    SpeechVariant(text: "B", locale: "en-US"),
                    SpeechVariant(text: "C", locale: "es-MX")
                ],
                SpeechAct.echoResponse.rawValue: [
                    SpeechVariant(text: "¡Qué bien, {recognized}!", locale: "es-MX")
                ],
                SpeechAct.timeRemaining.rawValue: [
                    SpeechVariant(text: "About {minutes} minutes in.", locale: "en-US"),
                    SpeechVariant(text: "Halfway there.", locale: "en-US")
                ]
            ],
            slots: ["city": ["México", "Chicago"]]
        )
    }

    // MARK: - Selection

    func testReturnsNilForAnEmptyOrMissingPool() {
        let composer = SpeechComposer(bank: SpeechBank(language: "es", pools: [:]))
        XCTAssertNil(composer.line(for: .praise),
                     "A missing pool must return nil so the caller can fall back")
    }

    func testNeverRepeatsTheSameVariantTwiceInARow() {
        // Force the RNG to always pick index 0; the no-repeat rule must break the tie.
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        let first = composer.line(for: .praise)?.text
        let second = composer.line(for: .praise)?.text
        XCTAssertEqual(first, "A")
        XCTAssertNotEqual(first, second, "Consecutive praise lines must differ")
    }

    func testSingleVariantPoolIsAllowedToRepeat() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertEqual(composer.line(for: .echoResponse, slots: ["recognized": "x"])?.text,
                       composer.line(for: .echoResponse, slots: ["recognized": "x"])?.text,
                       "A one-variant pool has no alternative and may repeat")
    }

    func testLocaleIsCarriedThrough() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 2 })
        XCTAssertEqual(composer.line(for: .praise)?.locale, "es-MX")
    }

    // MARK: - Slot filling

    func testSlotsAreFilled() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertEqual(composer.line(for: .timeRemaining, slots: ["minutes": "10"])?.text,
                       "About 10 minutes in.")
    }

    func testVariantsWithUnfillableSlotsAreExcluded() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        let line = composer.line(for: .timeRemaining)   // no "minutes" supplied
        XCTAssertEqual(line?.text, "Halfway there.",
                       "Should fall back to the variant that needs no slots")
        XCTAssertFalse(line?.text.contains("{") ?? true,
                       "A rendered line must never contain a leftover placeholder")
    }

    func testSlotValuesComeOnlyFromTheBank() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertTrue(["México", "Chicago"].contains(composer.slotValue("city") ?? ""))
        XCTAssertNil(composer.slotValue("undefinedSlot"),
                     "An unauthored slot must yield nothing, never an invented value")
    }

    // MARK: - STT echo

    func testEchoSplicesRecognizedTextVerbatim() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertEqual(composer.echo(recognized: "Soy de Chicago")?.text,
                       "¡Qué bien, Soy de Chicago!",
                       "Recognized text must be passed through unmodified")
    }

    func testEchoRejectsEmptyOrOverlongInput() {
        let composer = SpeechComposer(bank: makeBank(), randomIndex: { _ in 0 })
        XCTAssertNil(composer.echo(recognized: "   "))
        XCTAssertNil(composer.echo(recognized: String(repeating: "a", count: 200)))
    }
}
