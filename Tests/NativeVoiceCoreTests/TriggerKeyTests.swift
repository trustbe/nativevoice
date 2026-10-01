import Testing
@testable import NativeVoiceCore

@Suite struct TriggerKeyTests {

    // Values from IOLLEvent.h, verified against the header rather than guessed.
    private let NX_DEVICELCTLKEYMASK: UInt64   = 0x00000001
    private let NX_DEVICELSHIFTKEYMASK: UInt64 = 0x00000002
    private let NX_DEVICERSHIFTKEYMASK: UInt64 = 0x00000004
    private let NX_DEVICELCMDKEYMASK: UInt64   = 0x00000008
    private let NX_DEVICERCMDKEYMASK: UInt64   = 0x00000010
    private let NX_DEVICELALTKEYMASK: UInt64   = 0x00000020
    private let NX_DEVICERALTKEYMASK: UInt64   = 0x00000040
    private let NX_DEVICERCTLKEYMASK: UInt64   = 0x00002000

    @Test func offersEveryModifierOnBothSides() {
        #expect(TriggerKey.allCases.count == 8)
    }

    @Test func defaultIsRightCommand() {
        #expect(TriggerKey.default == .rightCommand)
    }

    @Test func deviceMasksMatchTheHeader() {
        #expect(TriggerKey.leftControl.deviceMask ==  NX_DEVICELCTLKEYMASK)
        #expect(TriggerKey.leftShift.deviceMask ==    NX_DEVICELSHIFTKEYMASK)
        #expect(TriggerKey.rightShift.deviceMask ==   NX_DEVICERSHIFTKEYMASK)
        #expect(TriggerKey.leftCommand.deviceMask ==  NX_DEVICELCMDKEYMASK)
        #expect(TriggerKey.rightCommand.deviceMask == NX_DEVICERCMDKEYMASK)
        #expect(TriggerKey.leftOption.deviceMask ==   NX_DEVICELALTKEYMASK)
        #expect(TriggerKey.rightOption.deviceMask ==  NX_DEVICERALTKEYMASK)
        #expect(TriggerKey.rightControl.deviceMask == NX_DEVICERCTLKEYMASK)
    }

    @Test func masksAreUnique() {
        let masks = TriggerKey.allCases.map(\.deviceMask)
        #expect(Set(masks).count == masks.count)
    }

    @Test func rightCommandIsNotConfusedWithLeftCommand() {
        // This is the whole point of reading device bits: the generic
        // maskCommand flag is set for both sides, so it cannot tell them
        // apart. Holding left Command must not start a recording bound to
        // the right one.
        #expect(TriggerKey.rightCommand.isHeld(flags: NX_DEVICERCMDKEYMASK))
        #expect(!(TriggerKey.rightCommand.isHeld(flags: NX_DEVICELCMDKEYMASK)))
        #expect(!(TriggerKey.leftCommand.isHeld(flags: NX_DEVICERCMDKEYMASK)))
    }

    @Test func heldWhileOtherModifiersAreAlsoDown() {
        let both = NX_DEVICERCMDKEYMASK | NX_DEVICELSHIFTKEYMASK | 0x20000
        #expect(TriggerKey.rightCommand.isHeld(flags: both))
        #expect(TriggerKey.leftShift.isHeld(flags: both))
        #expect(!(TriggerKey.rightOption.isHeld(flags: both)))
    }

    @Test func notHeldWhenNoFlagsAreSet() {
        for key in TriggerKey.allCases {
            #expect(!(key.isHeld(flags: 0)), "\(key)")
        }
    }

    @Test func keyCodesAreUnique() {
        let codes = TriggerKey.allCases.map(\.keyCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test func everyKeyHasATitleAndASymbol() {
        for key in TriggerKey.allCases {
            #expect(!(key.menuTitle.isEmpty), "\(key)")
            #expect(!(key.symbol.isEmpty), "\(key)")
        }
    }

    @Test func rawValuesAreStableForStorage() {
        // These strings land in UserDefaults. Renaming a case silently resets
        // the user's choice, so the mapping is pinned here.
        #expect(TriggerKey.rightCommand.rawValue == "rightCommand")
        #expect(TriggerKey(rawValue: "leftOption") == .leftOption)
        #expect(TriggerKey(rawValue: "middleCommand") == nil)
    }
}
