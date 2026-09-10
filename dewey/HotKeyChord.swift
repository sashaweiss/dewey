//
//  HotKeyChord.swift
//  dewey
//

import Carbon.HIToolbox
import Cocoa

/// A parsed global hot key combination, e.g. "command+space".
struct HotKeyChord {
    let keyCode: Int
    let keyName: String
    let modifierFlags: NSEvent.ModifierFlags

    static let `default` = HotKeyChord(rawValue: "option+space")!

    /// Parses a "+"-separated list of modifiers followed by a key, e.g.
    /// "command+space" or "ctrl+opt+d". Requires at least one modifier.
    init?(rawValue: String) {
        var modifierFlags = NSEvent.ModifierFlags()
        var keyCode: Int?
        var keyName: String?

        let tokens = rawValue.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        for token in tokens {
            switch token {
            case "command", "cmd":
                modifierFlags.insert(.command)
            case "option", "opt", "alt":
                modifierFlags.insert(.option)
            case "control", "ctrl":
                modifierFlags.insert(.control)
            case "shift":
                modifierFlags.insert(.shift)
            default:
                guard keyCode == nil, let code = Self.keyCodesByName[token] else {
                    return nil
                }
                keyCode = code
                keyName = token
            }
        }

        guard let keyCode, let keyName, !modifierFlags.isEmpty else {
            return nil
        }

        self.keyCode = keyCode
        self.keyName = keyName
        self.modifierFlags = modifierFlags
    }

    /// E.g. "⌥Space" or "⌃⌘D".
    var displayString: String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        result += keyName.capitalized
        return result
    }

    private static let keyCodesByName: [String: Int] = [
        "space": kVK_Space,
        "return": kVK_Return,
        "tab": kVK_Tab,
        "escape": kVK_Escape,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
        "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]
}
