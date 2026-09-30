#if canImport(AVFoundation)
import XCTest
@testable import SYSKit

final class SYSVoicePickerTests: XCTestCase {
    private func voice(_ id: String, enhanced: Bool = false, _ gender: SYSVoiceGender? = nil, language: String = "en-US") -> SYSVoiceInfo {
        SYSVoiceInfo(identifier: id, language: language, isEnhanced: enhanced, gender: gender)
    }

    func testAnEnhancedVoiceOfTheRightGenderWins() {
        let voices = [
            voice("a", .female),
            voice("b", enhanced: true, .male),
            voice("c", enhanced: true, .female)
        ]
        XCTAssertEqual(SYSVoicePicker.best(from: voices, language: "en", gender: .female)?.identifier, "c")
        XCTAssertEqual(SYSVoicePicker.best(from: voices, language: "en", gender: .male)?.identifier, "b")
    }

    func testAPlainVoiceOfTheRightGenderBeatsAnEnhancedOneOfTheOther() {
        let voices = [voice("wrong", enhanced: true, .male), voice("right", .female)]
        XCTAssertEqual(SYSVoicePicker.best(from: voices, language: "en", gender: .female)?.identifier, "right")
    }

    func testAVoiceOfTheOppositeGenderIsNeverChosen() {
        let voices = [voice("only", enhanced: true, .male)]
        XCTAssertNil(SYSVoicePicker.best(from: voices, language: "en", gender: .female))
    }

    func testAKnownNameIsUsedWhenGenderIsNotReported() {
        let voices = [voice("com.apple.voice.compact.en-US.Fred"), voice("com.apple.voice.compact.en-US.Samantha")]
        XCTAssertEqual(SYSVoicePicker.best(from: voices, language: "en", gender: .female)?.identifier, "com.apple.voice.compact.en-US.Samantha")
        XCTAssertEqual(SYSVoicePicker.best(from: voices, language: "en", gender: .male)?.identifier, "com.apple.voice.compact.en-US.Fred")
    }

    func testAnUnspecifiedEnhancedVoiceIsAcceptableWhenNothingBetterExists() {
        let voices = [voice("plain"), voice("fancy", enhanced: true)]
        XCTAssertEqual(SYSVoicePicker.best(from: voices, language: "en", gender: .female)?.identifier, "fancy")
    }

    func testOnlyTheRequestedLanguageIsConsidered() {
        let voices = [voice("fr", enhanced: true, .female, language: "fr-FR"), voice("en", .female, language: "en-GB")]
        XCTAssertEqual(SYSVoicePicker.best(from: voices, language: "en", gender: .female)?.identifier, "en")
        XCTAssertNil(SYSVoicePicker.best(from: voices, language: "de", gender: .female))
    }

    func testNoVoicesGivesNoChoice() {
        XCTAssertNil(SYSVoicePicker.best(from: [], language: "en", gender: .male))
    }
}
#endif
