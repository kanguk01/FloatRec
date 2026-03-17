import XCTest
@testable import FloatRec

final class ClipDurationFormatterTests: XCTestCase {
    func testFormatsMinuteAndSecond() {
        XCTAssertEqual(ClipDurationFormatter.string(from: 65.9), "1:05")
    }
}
