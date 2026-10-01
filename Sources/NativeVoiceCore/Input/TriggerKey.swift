import Carbon.HIToolbox
import Foundation

/// The key held to dictate.
///
/// Modifiers only. An ordinary key could not be used: the event tap listens to
/// `flagsChanged` and nothing else. That is a deliberate constraint, not an
/// oversight — a version that also tapped `keyDown` coincided with every
/// keyboard shortcut in the system breaking. The mechanism was never proven;
/// the difference was reproducible, and the narrow mask has run without a
/// repeat ever since.
///
/// Left and right cannot be told apart from `event.flags` alone: the generic
/// command flag is set for both. The side is read from the device-specific bit
/// (`NX_DEVICE*KEYMASK` in `IOLLEvent.h`).
public enum TriggerKey: String, CaseIterable, Equatable {
    case rightCommand, leftCommand
    case rightOption, leftOption
    case rightControl, leftControl
    case rightShift, leftShift

    public static let `default` = TriggerKey.rightCommand

    public var keyCode: UInt16 {
        switch self {
        case .rightCommand: return UInt16(kVK_RightCommand)
        case .leftCommand:  return UInt16(kVK_Command)
        case .rightOption:  return UInt16(kVK_RightOption)
        case .leftOption:   return UInt16(kVK_Option)
        case .rightControl: return UInt16(kVK_RightControl)
        case .leftControl:  return UInt16(kVK_Control)
        case .rightShift:   return UInt16(kVK_RightShift)
        case .leftShift:    return UInt16(kVK_Shift)
        }
    }

    /// Bit set while this specific key is down. Values taken from
    /// `IOLLEvent.h`, not inferred.
    public var deviceMask: UInt64 {
        switch self {
        case .leftControl:  return 0x00000001   // NX_DEVICELCTLKEYMASK
        case .leftShift:    return 0x00000002   // NX_DEVICELSHIFTKEYMASK
        case .rightShift:   return 0x00000004   // NX_DEVICERSHIFTKEYMASK
        case .leftCommand:  return 0x00000008   // NX_DEVICELCMDKEYMASK
        case .rightCommand: return 0x00000010   // NX_DEVICERCMDKEYMASK
        case .leftOption:   return 0x00000020   // NX_DEVICELALTKEYMASK
        case .rightOption:  return 0x00000040   // NX_DEVICERALTKEYMASK
        case .rightControl: return 0x00002000   // NX_DEVICERCTLKEYMASK
        }
    }

    public func isHeld(flags: UInt64) -> Bool { flags & deviceMask != 0 }

    public var menuTitle: String {
        switch self {
        case .rightCommand: return String(localized: "Right Command (⌘)", bundle: .module)
        case .leftCommand:  return String(localized: "Left Command (⌘)", bundle: .module)
        case .rightOption:  return String(localized: "Right Option (⌥)", bundle: .module)
        case .leftOption:   return String(localized: "Left Option (⌥)", bundle: .module)
        case .rightControl: return String(localized: "Right Control (⌃)", bundle: .module)
        case .leftControl:  return String(localized: "Left Control (⌃)", bundle: .module)
        case .rightShift:   return String(localized: "Right Shift (⇧)", bundle: .module)
        case .leftShift:    return String(localized: "Left Shift (⇧)", bundle: .module)
        }
    }

    public var symbol: String {
        switch self {
        case .rightCommand, .leftCommand: return "⌘"
        case .rightOption,  .leftOption:  return "⌥"
        case .rightControl, .leftControl: return "⌃"
        case .rightShift,   .leftShift:   return "⇧"
        }
    }
}
