import Testing
@testable import NativeVoiceCore

@Suite struct LoginItemStateTests {

    @Test func aRegisteredAppIsOn() {
        #expect(LoginItemState.from(rawStatus: 1) == .on)
    }

    @Test func anAppWaitingForTheUserSaysSo() {
        // Registered but unconfirmed. Without this case the row looked plain
        // off, clicking it registered again — which does nothing — and the
        // person had no way to learn they were the one being waited for.
        #expect(LoginItemState.from(rawStatus: 2) == .needsApproval)
    }

    @Test func anAppThatWasNeverRegisteredIsOff() {
        #expect(LoginItemState.from(rawStatus: 0) == .off)
    }

    @Test func notFoundIsAlsoOff() {
        // Review Focus 4: a never-registered app reports notFound, not
        // notRegistered — measured with a throwaway bundle. Both are off.
        #expect(LoginItemState.from(rawStatus: 3) == .off)
    }

    @Test func anUnknownStatusIsOffRatherThanACrash() {
        #expect(LoginItemState.from(rawStatus: 99) == .off)
    }
}
