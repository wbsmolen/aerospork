import AppKit
import Common

func getKeysPreset(_ layout: KeyMapping.Preset) -> [String: Key] {
    return switch layout {
        case .qwerty: keyNotationToKeyCode
        case .dvorak: dvorakMap
        case .colemak: colemakMap
    }
}

/// Every key a binding can name. Modifiers and media keys have notations too, but can't be bound.
let keyNotationToKeyCode: [String: Key] = {
    let unbindable: Set<Key> = [
        .command, .rightCommand, .option, .rightOption, .control, .rightControl, .shift, .rightShift,
        .function, .capsLock, .help, .volumeUp, .volumeDown, .mute,
    ]
    return Dictionary(uniqueKeysWithValues: Key.allCases.filter { !unbindable.contains($0) }.map { ($0.rawValue, $0) })
}()

private let dvorakMap: [String: Key] = keyNotationToKeyCode + [
    "leftSquareBracket": .minus,
    "rightSquareBracket": .equal,

    "quote": .q,
    "comma": .w,
    "period": .e,
    "p": .r,
    "y": .t,
    "f": .y,
    "g": .u,
    "c": .i,
    "r": .o,
    "l": .p,
    "slash": .leftBracket, // leftBracket -> leftSquareBracket
    "equal": .rightBracket, // rightBracket -> rightSquareBracket
    "backslash": .backslash,

    "a": .a,
    "o": .s,
    "e": .d,
    "u": .f,
    "i": .g,
    "d": .h,
    "h": .j,
    "t": .k,
    "n": .l,
    "s": .semicolon,
    "minus": .quote,

    "semicolon": .z,
    "q": .x,
    "j": .c,
    "k": .v,
    "x": .b,
    "b": .n,
    "m": .m,
    "w": .comma,
    "v": .period,
    "z": .slash,
]

private let colemakMap: [String: Key] = keyNotationToKeyCode + [
    "q": .q,
    "w": .w,
    "f": .e,
    "p": .r,
    "g": .t,
    "j": .y,
    "l": .u,
    "u": .i,
    "y": .o,
    "semicolon": .p,
    "leftSquareBracket": .leftBracket,
    "rightSquareBracket": .rightBracket,
    "backslash": .backslash,

    "a": .a,
    "r": .s,
    "s": .d,
    "t": .f,
    "d": .g,
    "h": .h,
    "n": .j,
    "e": .k,
    "i": .l,
    "o": .semicolon,
    "quote": .quote,

    "z": .z,
    "x": .x,
    "c": .c,
    "v": .v,
    "b": .b,
    "k": .n,
    "m": .m,
    "comma": .comma,
    "period": .period,
    "slash": .slash,
]

let modifiersMap: [String: NSEvent.ModifierFlags] = [
    "shift": .shift,
    "alt": .option,
    "ctrl": .control,
    "cmd": .command,
]

extension NSEvent.ModifierFlags {
    func toString() -> String {
        var result: [String] = []
        if contains(.option) { result.append("alt") }
        if contains(.control) { result.append("ctrl") }
        if contains(.command) { result.append("cmd") }
        if contains(.shift) { result.append("shift") }
        return result.joined(separator: "-")
    }
}

// doesn't work :(
//extension NSEvent.ModifierFlags {
//    static let lOption = NSEvent.ModifierFlags(rawValue: 1 << 1)
//    static let rOption = NSEvent.ModifierFlags(rawValue: 1 << 2)
//    static let lShift = NSEvent.ModifierFlags(rawValue: 0x00000002)
//    static let rShift = NSEvent.ModifierFlags(rawValue: 0x00000004)
//    static let lCommand = NSEvent.ModifierFlags(rawValue: 1 << 7)
//    static let rCommand = NSEvent.ModifierFlags(rawValue: 0x00000010)
//}

// NSEvent.ModifierFlags.command.rawValue // 1 << 20
// NSEvent.ModifierFlags.option.rawValue // 1 << 19
// NSEvent.ModifierFlags.control.rawValue // 1 << 18
// NSEvent.ModifierFlags.shift.rawValue // 1 << 17
// https://github.com/koekeishiya/skhd/blob/master/src/hotkey.h
