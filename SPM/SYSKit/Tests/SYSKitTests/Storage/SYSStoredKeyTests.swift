import XCTest
@testable import SYSKit

final class SYSStoredKeyTests: XCTestCase {
    private final class Box: ObservableObject {
        static let key = SYSSettingsKey<Bool>("SYSStoredKeyTests.flag", default: true)
        @SYSStored(Box.key) var flag: Bool
    }

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: Box.key.name)
    }

    func testAKeyedPreferenceStartsAtTheKeysDefaultAndKeepsWhatIsWritten() {
        let box = Box()
        XCTAssertTrue(box.flag)
        box.flag = false
        XCTAssertFalse(Box().flag)
    }
}
