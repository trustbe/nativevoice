import Foundation

/// The key held to dictate.
///
/// Modifiers only. An ordinary key could not be used: the event tap listens to
/// `flagsChanged` and nothing else. That is a deliberate constraint, not an
/// oversight — a version that also tapped `keyDown` coincided with every
/// keyboard shortcut in the system breaking. The mechanism was never proven;
/// the difference was reproducible, and the narrow mask has run without a
/// repeat ever since. It is also why "hold Space to talk" is not on offer.
///
/// Two choices, not eight. The left-hand modifiers are held constantly while
/// typing shortcuts, so binding dictation to one of them means recording
/// starts every time you save a file. The right-hand Command key is the one
/// most people never press, and adding Shift to it gives a second binding for
/// anyone whose right thumb lands on Command by habit.
///
/// Left and right cannot be told apart from the generic flags: the command bit
/// is set for both sides. The side is read from the device-specific bit
/// (`NX_DEVICE*KEYMASK` in `IOLLEvent.h`).
public enum TriggerKey: String, CaseIterable, Equatable {
    case rightCommand
    case shiftRightCommand

    public static let `default` = TriggerKey.rightCommand

    /// Bits taken from `IOLLEvent.h`, not inferred.
    private enum Mask {
        static let leftShift: UInt64    = 0x00000002   // NX_DEVICELSHIFTKEYMASK
        static let rightShift: UInt64   = 0x00000004   // NX_DEVICERSHIFTKEYMASK
        static let rightCommand: UInt64 = 0x00000010   // NX_DEVICERCMDKEYMASK
    }

    /// Groups of bits, each of which must have at least one bit set for the
    /// trigger to count as held.
    ///
    /// A single modifier has one group. A combination has one group per key,
    /// which is what makes "Shift and right Command" insist on both keys while
    /// still accepting either Shift — nobody should have to learn which one.
    public var requiredMasks: [UInt64] {
        switch self {
        case .rightCommand:
            return [Mask.rightCommand]
        case .shiftRightCommand:
            return [Mask.rightCommand, Mask.leftShift | Mask.rightShift]
        }
    }

    public func isHeld(flags: UInt64) -> Bool {
        requiredMasks.allSatisfy { flags & $0 != 0 }
    }

    public var menuTitle: String {
        switch self {
        case .rightCommand:
            return String(localized: "Right Command (⌘)", bundle: .module)
        case .shiftRightCommand:
            return String(localized: "Shift + Right Command (⇧⌘)", bundle: .module)
        }
    }
}
