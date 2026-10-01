import Testing
@testable import NativeVoiceCore

@Suite struct PlaceholderTests {
    @Test func targetCompilesAndTestsRun() {
        #expect(Placeholder.marker == "nativevoice")
    }
}
