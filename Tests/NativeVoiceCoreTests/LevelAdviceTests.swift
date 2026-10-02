import Testing
@testable import NativeVoiceCore

@Suite struct LevelAdviceTests {

    @Test func ordinarySpeechIsFine() {
        #expect(LevelAdvice.of(peakDecibels: -12) == .fine)
        #expect(LevelAdvice.of(peakDecibels: -6) == .fine)
        #expect(LevelAdvice.of(peakDecibels: -25) == .fine)
    }

    @Test func theMeasuredFailingLevelIsFlagged() {
        // −41 dB is the level at which "one hundred and forty-two" came back
        // as "one hundred and sixty-two" on a real recording.
        #expect(LevelAdvice.of(peakDecibels: -41) == .tooQuiet)
    }

    @Test func theMeasuredWorkingLevelIsNotFlagged() {
        // −26 dB is the level at which the same sentence was correct.
        #expect(LevelAdvice.of(peakDecibels: -26) == .fine)
    }

    @Test func nearSilenceIsItsOwnCase() {
        // The caller already has a message for this one; it must not be
        // told to raise the volume when there was nothing there at all.
        #expect(LevelAdvice.of(peakDecibels: -70) == .silent)
        #expect(LevelAdvice.of(peakDecibels: -56) == .silent)
    }

    @Test func theBoundariesFallOnTheStatedSide() {
        #expect(LevelAdvice.of(peakDecibels: LevelAdvice.quietBelow) == .fine)
        #expect(LevelAdvice.of(peakDecibels: LevelAdvice.silentBelow) == .tooQuiet)
    }

}
