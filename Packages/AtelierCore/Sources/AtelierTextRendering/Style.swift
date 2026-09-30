/// The attribute model text is styled with (text-renderer.md §3.2): style runs are looked up by a small integer id,
/// resolved to concrete colours only when a tile draws, so recolouring a theme never re-typesets.

/// An 8-bit RGBA colour, straight alpha, in the sRGB colour space.
public struct RGBA: Hashable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// A colour resolved per appearance at render time; no platform colour type in the model.
public enum ColorRef: Hashable, Sendable {
    case fixed(RGBA)
    case adaptive(light: RGBA, dark: RGBA, highContrast: RGBA? = nil)

    /// This colour under `appearance`, `highContrast` preferred when it exists and is asked for.
    public func resolved(for appearance: Appearance, highContrast: Bool = false) -> RGBA {
        switch self {
            case .fixed(let color): return color
            case .adaptive(let light, let dark, let contrast):
                let base = appearance == .dark ? dark : light
                return highContrast ? (contrast ?? base) : base
        }
    }
}

/// A font's weight, independent of any platform's numeric scale.
public enum FontWeight: Int, Hashable, Sendable, Comparable {
    case ultraLight = 100
    case thin = 200
    case light = 300
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700
    case heavy = 800
    case black = 900

    public static func < (lhs: FontWeight, rhs: FontWeight) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One row's style run, 8 bytes: `runs[offsets[row] ..< offsets[row + 1]]` in ``LineRuns``.
public struct StyleID: Hashable, Sendable {
    public var rawValue: UInt16

    public init(_ rawValue: UInt16) { self.rawValue = rawValue }
    public init(_ rawValue: Int) { self.rawValue = UInt16(rawValue) }
}

/// Everything a run can change. Font-affecting fields force re-typesetting; colour does not.
public struct TextStyle: Hashable, Sendable {
    public var foreground: ColorRef
    /// `nil` keeps the base font's weight.
    public var weight: FontWeight?
    public var isItalic: Bool
    /// Per-run OpenType feature overrides.
    public var features: [FontFeature]

    public init(
        foreground: ColorRef, weight: FontWeight? = nil, isItalic: Bool = false, features: [FontFeature] = []
    ) {
        self.foreground = foreground
        self.weight = weight
        self.isItalic = isItalic
        self.features = features
    }

    /// Whether two styles typeset the same glyphs, so a change between them never forces new layout.
    public func hasSameFont(as other: TextStyle) -> Bool {
        weight == other.weight && isItalic == other.isItalic && features == other.features
    }
}

public struct StyleSheet: Sendable {
    public var font: FontSpec
    /// Indexed by ``StyleID``.
    public var styles: [TextStyle]

    public init(font: FontSpec, styles: [TextStyle]) {
        self.font = font
        self.styles = styles
    }

    public subscript(id: StyleID) -> TextStyle? {
        let index = Int(id.rawValue)
        return styles.indices.contains(index) ? styles[index] : nil
    }
}

/// Style runs per row, in one flat buffer.
public struct LineRuns: Sendable {
    /// One run within a row, 8 bytes.
    public struct Run: Hashable, Sendable {
        /// Byte offset within the row.
        public var start: UInt32
        public var length: UInt16
        public var style: StyleID

        public init(start: UInt32, length: UInt16, style: StyleID) {
            self.start = start
            self.length = length
            self.style = style
        }

        public var range: Range<Int> { Int(start) ..< Int(start) + Int(length) }
    }

    /// `runs[offsets[row] ..< offsets[row + 1]]` is row `row`'s runs; `offsets` has `rowCount + 1` entries.
    public var runs: [Run]
    public var offsets: [UInt32]

    public init(runs: [Run], offsets: [UInt32]) {
        self.runs = runs
        self.offsets = offsets
    }

    /// No runs for any row: every byte styles as the plain style, `StyleID(0)`.
    public static func empty(rowCount: Int) -> LineRuns {
        LineRuns(runs: [], offsets: [UInt32](repeating: 0, count: rowCount + 1))
    }

    public subscript(row: RowIndex) -> ArraySlice<Run> {
        let index = row.index
        guard offsets.indices.contains(index), offsets.indices.contains(index + 1) else { return [] }
        return runs[Int(offsets[index]) ..< Int(offsets[index + 1])]
    }
}
