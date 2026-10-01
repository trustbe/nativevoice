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

    @Test func onlyTheQuietCaseGetsAMessage() {
        #expect(LevelAdvice.message(forPeakDecibels: -12) == nil)
        #expect(LevelAdvice.message(forPeakDecibels: -70) == nil)
        #expect(LevelAdvice.message(forPeakDecibels: -41) != nil)
    }

    @Test func theMessageNamesTheActualNumber() {
        // "Too quiet" invites an argument about whether it really was.
        let message = LevelAdvice.message(forPeakDecibels: -41)
        #expect(message?.contains("-41") == true || message?.contains("−41") == true)
    }
}
