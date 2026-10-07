import Foundation

// Virtual key codes from HIToolbox/Events.h, named after their position on a US ANSI layout.
enum KeyNames {
    static let byCode: [Int64: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
        0x08: "C", 0x09: "V", 0x0A: "Section", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
        0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
        0x18: "Equal", 0x19: "9", 0x1A: "7", 0x1B: "Minus", 0x1C: "8", 0x1D: "0", 0x1E: "RightBracket", 0x1F: "O",
        0x20: "U", 0x21: "LeftBracket", 0x22: "I", 0x23: "P", 0x24: "Return", 0x25: "L", 0x26: "J", 0x27: "Quote",
        0x28: "K", 0x29: "Semicolon", 0x2A: "Backslash", 0x2B: "Comma", 0x2C: "Slash", 0x2D: "N", 0x2E: "M", 0x2F: "Period",
        0x30: "Tab", 0x31: "Space", 0x32: "Grave", 0x33: "Delete", 0x35: "Escape",
        0x40: "F17", 0x41: "KeypadDecimal", 0x43: "KeypadMultiply", 0x45: "KeypadPlus", 0x47: "KeypadClear",
        0x4B: "KeypadDivide", 0x4C: "KeypadEnter", 0x4E: "KeypadMinus", 0x4F: "F18",
        0x50: "F19", 0x51: "KeypadEquals", 0x52: "Keypad0", 0x53: "Keypad1", 0x54: "Keypad2", 0x55: "Keypad3",
        0x56: "Keypad4", 0x57: "Keypad5", 0x58: "Keypad6", 0x59: "Keypad7", 0x5A: "F20", 0x5B: "Keypad8", 0x5C: "Keypad9",
        0x5D: "Yen", 0x5E: "Underscore", 0x5F: "KeypadComma",
        0x60: "F5", 0x61: "F6", 0x62: "F7", 0x63: "F3", 0x64: "F8", 0x65: "F9", 0x66: "Eisu", 0x67: "F11",
        0x68: "Kana", 0x69: "F13", 0x6A: "F16", 0x6B: "F14", 0x6D: "F10", 0x6F: "F12",
        0x71: "F15", 0x72: "Help", 0x73: "Home", 0x74: "PageUp", 0x75: "ForwardDelete", 0x76: "F4", 0x77: "End",
        0x78: "F2", 0x79: "PageDown", 0x7A: "F1", 0x7B: "LeftArrow", 0x7C: "RightArrow", 0x7D: "DownArrow", 0x7E: "UpArrow",
    ]

    static let byName: [String: Int64] = Dictionary(uniqueKeysWithValues: byCode.map { ($0.value.lowercased(), $0.key) })

    static func name(_ code: Int64) -> String {
        byCode[code] ?? "keycode_\(code)"
    }

    static func code(_ name: String) -> Int64? {
        let lowered = name.lowercased()
        if lowered.hasPrefix("keycode_") {
            return Int64(lowered.dropFirst("keycode_".count))
        }
        return byName[lowered]
    }
}
