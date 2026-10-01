import Foundation
import AppKit

/// Model representing a configurable keyboard shortcut key mapping
public struct KeyShortcut: Codable, Equatable, Hashable {
    public var keyCode: UInt16
    public var modifierFlagsRaw: UInt
    
    public init(keyCode: UInt16, modifierFlagsRaw: UInt) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifierFlagsRaw
    }
    
    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        // Keep only standard modifier flags (Command, Option, Shift, Control)
        let relevantFlags = modifiers.intersection([.command, .option, .shift, .control])
        self.modifierFlagsRaw = relevantFlags.rawValue
    }
    
    public var modifierFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
    }
    
    /// Display symbol for the shortcut (e.g. "⌘⇧R")
    public var displayString: String {
        var str = ""
        let flags = modifierFlags
        
        if flags.contains(.control) { str += "⌃" }
        if flags.contains(.option) { str += "⌥" }
        if flags.contains(.shift) { str += "⇧" }
        if flags.contains(.command) { str += "⌘" }
        
        str += keyName
        return str
    }
    
    /// Human-readable key name derived from key code
    public var keyName: String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            return "Key(\(keyCode))"
        }
    }
    
    /// Single key string equivalent for NSMenuItem
    public var keyEquivalent: String {
        switch keyCode {
        case 15: return "r"
        case 35: return "p"
        case 23: return "5"
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 31: return "o"
        case 49: return " "
        default:
            return keyName.lowercased()
        }
    }
    
    // MARK: - Standard Presets
    
    /// Default Start / Stop shortcut: Cmd + Shift + R
    public static let defaultStartStop = KeyShortcut(keyCode: 15, modifiers: [.command, .shift])
    
    /// Default Pause / Resume shortcut: Cmd + Shift + P
    public static let defaultPauseResume = KeyShortcut(keyCode: 35, modifiers: [.command, .shift])
    
    /// Default Toggle Control Bar shortcut: Cmd + Shift + 5
    public static let defaultToggleBar = KeyShortcut(keyCode: 23, modifiers: [.command, .shift])
    
    /// Check whether an incoming event matches this shortcut
    public func matches(event: NSEvent) -> Bool {
        guard event.keyCode == self.keyCode else { return false }
        let eventFlags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return eventFlags.rawValue == self.modifierFlagsRaw
    }
}
