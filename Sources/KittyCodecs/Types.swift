// MARK: - Color

public enum Color: Sendable, Equatable, Hashable {
    case `default`
    case indexed(UInt8)
    case rgb(r: UInt8, g: UInt8, b: UInt8)
}

// MARK: - Underline Style

public enum UnderlineStyle: UInt8, Sendable, Equatable, Hashable {
    case none = 0
    case single = 1
    case double = 2
    case curly = 3
    case dotted = 4
    case dashed = 5
}

// MARK: - Style

public struct Style: Sendable, Equatable, Hashable {
    public var fg: Color
    public var bg: Color
    public var underlineColor: Color
    public var bold: Bool
    public var dim: Bool
    public var italic: Bool
    public var underline: UnderlineStyle
    public var strikethrough: Bool
    public var inverse: Bool

    public static let `default` = Style()

    public init(
        fg: Color = .default,
        bg: Color = .default,
        underlineColor: Color = .default,
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: UnderlineStyle = .none,
        strikethrough: Bool = false,
        inverse: Bool = false
    ) {
        self.fg = fg
        self.bg = bg
        self.underlineColor = underlineColor
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.inverse = inverse
    }
}

// MARK: - Key Modifiers

public struct KeyModifiers: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift   = KeyModifiers(rawValue: 1 << 0)
    public static let alt     = KeyModifiers(rawValue: 1 << 1)
    public static let ctrl    = KeyModifiers(rawValue: 1 << 2)
    public static let `super` = KeyModifiers(rawValue: 1 << 3)
    public static let hyper   = KeyModifiers(rawValue: 1 << 4)
    public static let meta    = KeyModifiers(rawValue: 1 << 5)
    public static let capsLock = KeyModifiers(rawValue: 1 << 6)
    public static let numLock = KeyModifiers(rawValue: 1 << 7)
}

// MARK: - Key Event Type

public enum KeyEventType: UInt8, Sendable, Equatable {
    case press = 1
    case `repeat` = 2
    case release = 3
}

// MARK: - Key Event

public struct KeyEvent: Sendable, Equatable {
    public var keyCode: UInt32
    public var modifiers: KeyModifiers
    public var eventType: KeyEventType
    public var alternateKeys: [UInt32]
    public var associatedText: String

    public init(
        keyCode: UInt32,
        modifiers: KeyModifiers = [],
        eventType: KeyEventType = .press,
        alternateKeys: [UInt32] = [],
        associatedText: String = ""
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.eventType = eventType
        self.alternateKeys = alternateKeys
        self.associatedText = associatedText
    }
}

// MARK: - Mouse Button

public enum MouseButton: UInt8, Sendable, Equatable {
    case left = 0
    case middle = 1
    case right = 2
    case release = 3
    case scrollUp = 64
    case scrollDown = 65
    case scrollLeft = 66
    case scrollRight = 67
    case button4 = 128
    case button5 = 129
}

// MARK: - Mouse Event Kind

public enum MouseEventKind: Sendable, Equatable {
    case press
    case release
    case motion
    case drag
}

// MARK: - Mouse Event

public struct MouseEvent: Sendable, Equatable {
    public var button: MouseButton
    public var modifiers: KeyModifiers
    public var row: Int
    public var col: Int
    public var pixelX: Int?
    public var pixelY: Int?
    public var kind: MouseEventKind

    public init(
        button: MouseButton,
        modifiers: KeyModifiers = [],
        row: Int,
        col: Int,
        pixelX: Int? = nil,
        pixelY: Int? = nil,
        kind: MouseEventKind = .press
    ) {
        self.button = button
        self.modifiers = modifiers
        self.row = row
        self.col = col
        self.pixelX = pixelX
        self.pixelY = pixelY
        self.kind = kind
    }
}

// MARK: - Decoder Result

public enum DecoderResult<T: Sendable & Equatable>: Sendable, Equatable {
    case pending
    case complete(T)
    case invalid([UInt8])
}

// MARK: - Graphics Command

public struct GraphicsCommand: Sendable, Equatable {
    public enum Action: Character, Sendable, Equatable {
        case transmit = "t"
        case transmitAndDisplay = "T"
        case query = "q"
        case placement = "p"
        case delete = "d"
        case frame = "f"
        case animation = "a"
        case compose = "c"
    }

    public enum Format: UInt8, Sendable, Equatable {
        case rgba = 32
        case rgb = 24
        case png = 100
    }

    public enum Transmission: Character, Sendable, Equatable {
        case direct = "d"
        case file = "f"
        case tempFile = "t"
        case sharedMemory = "s"
    }

    public var action: Action
    public var format: Format
    public var transmission: Transmission
    public var id: UInt32
    public var width: UInt32
    public var height: UInt32
    public var payload: [UInt8]

    public init(
        action: Action = .transmitAndDisplay,
        format: Format = .png,
        transmission: Transmission = .direct,
        id: UInt32 = 0,
        width: UInt32 = 0,
        height: UInt32 = 0,
        payload: [UInt8] = []
    ) {
        self.action = action
        self.format = format
        self.transmission = transmission
        self.id = id
        self.width = width
        self.height = height
        self.payload = payload
    }
}
