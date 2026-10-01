import XCTest
@testable import NativeVoiceCore

final class PlaceholderTests: XCTestCase {
    func testTargetCompilesAndTestsRun() {
        XCTAssertEqual(Placeholder.marker, "nativevoice")
    }
}
