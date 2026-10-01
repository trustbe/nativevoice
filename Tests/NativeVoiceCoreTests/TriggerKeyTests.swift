import Testing
@testable import NativeVoiceCore

@Suite struct TriggerKeyTests {

    // Values from IOLLEvent.h, read from the header rather than guessed.
    private let leftShift: UInt64    = 0x00000002   // NX_DEVICELSHIFTKEYMASK
    private let rightShift: UInt64   = 0x00000004   // NX_DEVICERSHIFTKEYMASK
    private let leftCommand: UInt64  = 0x00000008   // NX_DEVICELCMDKEYMASK
    private let rightCommand: UInt64 = 0x00000010   // NX_DEVICERCMDKEYMASK
    private let rightOption: UInt64  = 0x00000040   // NX_DEVICERALTKEYMASK
    private let capsLockFlag: UInt64 = 0x00010000   // NX_ALPHASHIFTMASK

    @Test func thereAreTwoChoices() {
        #expect(TriggerKey.allCases.count == 2)
    }

    @Test func defaultIsRightCommand() {
        #expect(TriggerKey.default == .rightCommand)
    }

    @Test func rightCommandIsNotConfusedWithLeftCommand() {
        // The whole reason for reading device bits: the generic command flag
        // is set for both sides, so it cannot tell them apart. Holding left
        // Command must not start a recording.
        #expect(TriggerKey.rightCommand.isHeld(flags: rightCommand))
        #expect(!(TriggerKey.rightCommand.isHeld(flags: leftCommand)))
    }

    @Test func plainRightCommandStillCountsWhenSomethingElseIsAlsoDown() {
        // Someone holding Shift for an unrelated reason should not find that
        // dictation has stopped working.
        #expect(TriggerKey.rightCommand.isHeld(flags: rightCommand | leftShift))
        #expect(TriggerKey.rightCommand.isHeld(flags: rightCommand | capsLockFlag))
    }

    @Test func theCombinationNeedsBothKeys() {
        #expect(!(TriggerKey.shiftRightCommand.isHeld(flags: rightCommand)))
        #expect(!(TriggerKey.shiftRightCommand.isHeld(flags: leftShift)))
        #expect(TriggerKey.shiftRightCommand.isHeld(flags: rightCommand | leftShift))
    }

    @Test func eitherShiftWorksForTheCombination() {
        // Nobody should have to learn which Shift the app wanted.
        #expect(TriggerKey.shiftRightCommand.isHeld(flags: rightCommand | leftShift))
        #expect(TriggerKey.shiftRightCommand.isHeld(flags: rightCommand | rightShift))
    }

    @Test func theCombinationIsNotSatisfiedByLeftCommandAndShift() {
        #expect(!(TriggerKey.shiftRightCommand.isHeld(flags: leftCommand | leftShift)))
    }

    @Test func nothingIsHeldWhenNoFlagsAreSet() {
        for key in TriggerKey.allCases {
            #expect(!(key.isHeld(flags: 0)), "\(key)")
        }
    }

    @Test func anUnrelatedModifierDoesNotTrigger() {
        for key in TriggerKey.allCases {
            #expect(!(key.isHeld(flags: rightOption)), "\(key)")
        }
    }

    @Test func everyChoiceHasATitle() {
        for key in TriggerKey.allCases {
            #expect(!(key.menuTitle.isEmpty), "\(key)")
        }
    }

    @Test func rawValuesAreStableForStorage() {
        // These strings land in UserDefaults. Renaming a case silently resets
        // the stored choice, so the mapping is pinned here.
        #expect(TriggerKey.rightCommand.rawValue == "rightCommand")
        #expect(TriggerKey.shiftRightCommand.rawValue == "shiftRightCommand")
        #expect(TriggerKey(rawValue: "middleCommand") == nil)
    }

    @Test func aChoiceThatNoLongerExistsDoesNotParse() {
        // Anyone who had picked one of the six modifiers that used to be on
        // offer gets the default back rather than a value nothing understands.
        #expect(TriggerKey(rawValue: "leftOption") == nil)
        #expect(TriggerKey(rawValue: "rightShift") == nil)
    }
}
