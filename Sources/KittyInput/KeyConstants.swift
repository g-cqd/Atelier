public enum Key: UInt32 {
    case up = 57352
    case down = 57353
    case right = 57354
    case left = 57355
    case enter = 13
    case enterAlt = 10
    case backspace = 127
    case backspaceAlt = 8
    case home = 57356
    case end = 57357
    case pageUp = 57358
    case pageDown = 57359
}

/// Named ASCII key code constants to avoid force-unwrapping asciiValue.
public enum AsciiKey {
    public static let b: UInt32 = 0x62
    public static let c: UInt32 = 0x63
    public static let f: UInt32 = 0x66
    public static let g: UInt32 = 0x67
    public static let h: UInt32 = 0x68
    public static let i: UInt32 = 0x69
    public static let j: UInt32 = 0x6A
    public static let k: UInt32 = 0x6B
    public static let l: UInt32 = 0x6C
    public static let n: UInt32 = 0x6E
    public static let o: UInt32 = 0x6F
    public static let q: UInt32 = 0x71
    public static let v: UInt32 = 0x76
    public static let w: UInt32 = 0x77
    public static let x: UInt32 = 0x78
    public static let y: UInt32 = 0x79
    public static let z: UInt32 = 0x7A
    public static let colon: UInt32 = 0x3A
    public static let escape: UInt32 = 27
}
