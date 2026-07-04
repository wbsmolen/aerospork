import Carbon

/// Local drop-in replacement for soffes/HotKey's `Key` enum.
/// Case names and Carbon virtual keycodes mirror HotKey's `Key` exactly, so the rest of the
/// config code (keysMap.swift `[String: Key]` tables, `toString()`, `HotkeyBinding.keyCode`)
/// keeps compiling unchanged. `carbonKeyCode` is used for `RegisterEventHotKey`.
enum Key: CaseIterable, Equatable, Hashable, Sendable {
    // MARK: - Letters
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    // MARK: - Numbers
    case zero, one, two, three, four, five, six, seven, eight, nine

    // MARK: - Symbols
    case period
    case quote
    case rightBracket
    case semicolon
    case slash
    case backslash
    case comma
    case equal
    case grave // Backtick
    case leftBracket
    case minus
    case section

    // MARK: - Whitespace
    case space
    case tab
    case `return`

    // MARK: - Modifiers
    case command
    case rightCommand
    case option
    case rightOption
    case control
    case rightControl
    case shift
    case rightShift
    case function
    case capsLock

    // MARK: - Navigation
    case pageUp
    case pageDown
    case home
    case end
    case upArrow
    case rightArrow
    case downArrow
    case leftArrow

    // MARK: - Functions
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    // MARK: - Keypad
    case keypad0, keypad1, keypad2, keypad3, keypad4
    case keypad5, keypad6, keypad7, keypad8, keypad9
    case keypadClear
    case keypadDecimal
    case keypadDivide
    case keypadEnter
    case keypadEquals
    case keypadMinus
    case keypadMultiply
    case keypadPlus

    // MARK: - Misc
    case escape
    case delete
    case forwardDelete
    case help
    case volumeUp
    case volumeDown
    case mute

    /// Carbon virtual keycode (`kVK_*`) for this key, used to register global hotkeys.
    /// Values copied verbatim from soffes/HotKey `Key.carbonKeyCode`.
    var carbonKeyCode: UInt32 {
        switch self {
            case .a: return UInt32(kVK_ANSI_A)
            case .s: return UInt32(kVK_ANSI_S)
            case .d: return UInt32(kVK_ANSI_D)
            case .f: return UInt32(kVK_ANSI_F)
            case .h: return UInt32(kVK_ANSI_H)
            case .g: return UInt32(kVK_ANSI_G)
            case .z: return UInt32(kVK_ANSI_Z)
            case .x: return UInt32(kVK_ANSI_X)
            case .c: return UInt32(kVK_ANSI_C)
            case .v: return UInt32(kVK_ANSI_V)
            case .b: return UInt32(kVK_ANSI_B)
            case .q: return UInt32(kVK_ANSI_Q)
            case .w: return UInt32(kVK_ANSI_W)
            case .e: return UInt32(kVK_ANSI_E)
            case .r: return UInt32(kVK_ANSI_R)
            case .y: return UInt32(kVK_ANSI_Y)
            case .t: return UInt32(kVK_ANSI_T)
            case .one: return UInt32(kVK_ANSI_1)
            case .two: return UInt32(kVK_ANSI_2)
            case .three: return UInt32(kVK_ANSI_3)
            case .four: return UInt32(kVK_ANSI_4)
            case .six: return UInt32(kVK_ANSI_6)
            case .five: return UInt32(kVK_ANSI_5)
            case .equal: return UInt32(kVK_ANSI_Equal)
            case .nine: return UInt32(kVK_ANSI_9)
            case .seven: return UInt32(kVK_ANSI_7)
            case .minus: return UInt32(kVK_ANSI_Minus)
            case .eight: return UInt32(kVK_ANSI_8)
            case .zero: return UInt32(kVK_ANSI_0)
            case .rightBracket: return UInt32(kVK_ANSI_RightBracket)
            case .o: return UInt32(kVK_ANSI_O)
            case .u: return UInt32(kVK_ANSI_U)
            case .leftBracket: return UInt32(kVK_ANSI_LeftBracket)
            case .i: return UInt32(kVK_ANSI_I)
            case .p: return UInt32(kVK_ANSI_P)
            case .l: return UInt32(kVK_ANSI_L)
            case .j: return UInt32(kVK_ANSI_J)
            case .quote: return UInt32(kVK_ANSI_Quote)
            case .k: return UInt32(kVK_ANSI_K)
            case .semicolon: return UInt32(kVK_ANSI_Semicolon)
            case .backslash: return UInt32(kVK_ANSI_Backslash)
            case .comma: return UInt32(kVK_ANSI_Comma)
            case .slash: return UInt32(kVK_ANSI_Slash)
            case .n: return UInt32(kVK_ANSI_N)
            case .m: return UInt32(kVK_ANSI_M)
            case .period: return UInt32(kVK_ANSI_Period)
            case .grave: return UInt32(kVK_ANSI_Grave)
            case .keypadDecimal: return UInt32(kVK_ANSI_KeypadDecimal)
            case .keypadMultiply: return UInt32(kVK_ANSI_KeypadMultiply)
            case .keypadPlus: return UInt32(kVK_ANSI_KeypadPlus)
            case .keypadClear: return UInt32(kVK_ANSI_KeypadClear)
            case .keypadDivide: return UInt32(kVK_ANSI_KeypadDivide)
            case .keypadEnter: return UInt32(kVK_ANSI_KeypadEnter)
            case .keypadMinus: return UInt32(kVK_ANSI_KeypadMinus)
            case .keypadEquals: return UInt32(kVK_ANSI_KeypadEquals)
            case .keypad0: return UInt32(kVK_ANSI_Keypad0)
            case .keypad1: return UInt32(kVK_ANSI_Keypad1)
            case .keypad2: return UInt32(kVK_ANSI_Keypad2)
            case .keypad3: return UInt32(kVK_ANSI_Keypad3)
            case .keypad4: return UInt32(kVK_ANSI_Keypad4)
            case .keypad5: return UInt32(kVK_ANSI_Keypad5)
            case .keypad6: return UInt32(kVK_ANSI_Keypad6)
            case .keypad7: return UInt32(kVK_ANSI_Keypad7)
            case .keypad8: return UInt32(kVK_ANSI_Keypad8)
            case .keypad9: return UInt32(kVK_ANSI_Keypad9)
            case .`return`: return UInt32(kVK_Return)
            case .tab: return UInt32(kVK_Tab)
            case .space: return UInt32(kVK_Space)
            case .delete: return UInt32(kVK_Delete)
            case .escape: return UInt32(kVK_Escape)
            case .command: return UInt32(kVK_Command)
            case .shift: return UInt32(kVK_Shift)
            case .capsLock: return UInt32(kVK_CapsLock)
            case .option: return UInt32(kVK_Option)
            case .control: return UInt32(kVK_Control)
            case .rightCommand: return UInt32(kVK_RightCommand)
            case .rightShift: return UInt32(kVK_RightShift)
            case .rightOption: return UInt32(kVK_RightOption)
            case .rightControl: return UInt32(kVK_RightControl)
            case .function: return UInt32(kVK_Function)
            case .f17: return UInt32(kVK_F17)
            case .volumeUp: return UInt32(kVK_VolumeUp)
            case .volumeDown: return UInt32(kVK_VolumeDown)
            case .mute: return UInt32(kVK_Mute)
            case .f18: return UInt32(kVK_F18)
            case .f19: return UInt32(kVK_F19)
            case .f20: return UInt32(kVK_F20)
            case .f5: return UInt32(kVK_F5)
            case .f6: return UInt32(kVK_F6)
            case .f7: return UInt32(kVK_F7)
            case .f3: return UInt32(kVK_F3)
            case .f8: return UInt32(kVK_F8)
            case .f9: return UInt32(kVK_F9)
            case .f11: return UInt32(kVK_F11)
            case .f13: return UInt32(kVK_F13)
            case .f16: return UInt32(kVK_F16)
            case .f14: return UInt32(kVK_F14)
            case .f10: return UInt32(kVK_F10)
            case .f12: return UInt32(kVK_F12)
            case .f15: return UInt32(kVK_F15)
            case .help: return UInt32(kVK_Help)
            case .home: return UInt32(kVK_Home)
            case .pageUp: return UInt32(kVK_PageUp)
            case .forwardDelete: return UInt32(kVK_ForwardDelete)
            case .f4: return UInt32(kVK_F4)
            case .end: return UInt32(kVK_End)
            case .f2: return UInt32(kVK_F2)
            case .pageDown: return UInt32(kVK_PageDown)
            case .f1: return UInt32(kVK_F1)
            case .leftArrow: return UInt32(kVK_LeftArrow)
            case .rightArrow: return UInt32(kVK_RightArrow)
            case .downArrow: return UInt32(kVK_DownArrow)
            case .upArrow: return UInt32(kVK_UpArrow)
            case .section: return UInt32(kVK_ISO_Section)
        }
    }
}
