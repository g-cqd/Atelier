// Color / UnderlineStyle / Style moved to the `KittyStyle` target
// (audit D2 — `Sources/KittyStyle/Style.swift`). `@_exported` re-export
// keeps every existing `import KittyCodecs` consumer (KittyRenderer,
// KittyWidgets, KittyCode, …) compiling unchanged — they still see
// `Style`, `Color`, `UnderlineStyle` as if those types lived here.
// New consumers that only need style types can import the leaner
// `KittyStyle` directly. `KittySyntax` was switched over precisely to
// drop its transitive dep on the terminal-codec layer.
@_exported import KittyStyle

// MARK: - Key Modifiers

public struct KeyModifiers: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let alt = KeyModifiers(rawValue: 1 << 1)
    public static let ctrl = KeyModifiers(rawValue: 1 << 2)
    public static let `super` = KeyModifiers(rawValue: 1 << 3)
    public static let hyper = KeyModifiers(rawValue: 1 << 4)
    public static let meta = KeyModifiers(rawValue: 1 << 5)
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

    public var isScroll: Bool {
        switch self {
            case .scrollUp, .scrollDown, .scrollLeft, .scrollRight: true
            default: false
        }
    }
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
    /// Placement fields (`a=p`): the placement id, the z-index (negative draws under text), the pixel offset
    /// inside the cursor cell, and whether the cursor stays put after the placement.
    public var placement: Placement?
    /// What `a=d` deletes.
    public var deletion: Deletion?
    /// Suppress the terminal's `OK` reply (`q=2`), so a fire-and-forget command never lands in the input stream.
    public var isQuiet = false

    public struct Placement: Sendable, Equatable {
        public var id: UInt32
        public var zIndex: Int32
        public var xOffset: UInt32
        public var yOffset: UInt32
        public var keepsCursor: Bool
        /// Cells the image is scaled to fill (`c=`, `r=`); zero shows it at its pixel size.
        public var columns: UInt32
        public var rows: UInt32

        public init(
            id: UInt32, zIndex: Int32 = 0, xOffset: UInt32 = 0, yOffset: UInt32 = 0, keepsCursor: Bool = true,
            columns: UInt32 = 0, rows: UInt32 = 0
        ) {
            self.id = id
            self.zIndex = zIndex
            self.xOffset = xOffset
            self.yOffset = yOffset
            self.keepsCursor = keepsCursor
            self.columns = columns
            self.rows = rows
        }
    }

    public enum Deletion: Sendable, Equatable {
        /// Every visible placement; `freeingData` also frees the image data.
        case allPlacements(freeingData: Bool)
        /// The placements of the image `id` (and, with `freeingData`, the image itself).
        case image(id: UInt32, freeingData: Bool)
    }

    public init(
        action: Action = .transmitAndDisplay,
        format: Format = .png,
        transmission: Transmission = .direct,
        id: UInt32 = 0,
        width: UInt32 = 0,
        height: UInt32 = 0,
        payload: [UInt8] = [],
        placement: Placement? = nil,
        deletion: Deletion? = nil,
        isQuiet: Bool = false
    ) {
        self.action = action
        self.format = format
        self.transmission = transmission
        self.id = id
        self.width = width
        self.height = height
        self.payload = payload
        self.placement = placement
        self.deletion = deletion
        self.isQuiet = isQuiet
    }
}
