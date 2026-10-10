import CoreGraphics
import CoreText
import Testing

@testable import AtelierTextRendering

/// A tile's pixels against the canonical CoreText rendering of the same visual lines: the same font, size, scale,
/// baselines and x padding, each line drawn with `CTLineDraw` and the identity text matrix into an unflipped bitmap,
/// origin at the bottom left, with each line's baseline at `imageHeight - lineTop - baseline`.
///
/// Only the alpha plane is compared: the text is black on a transparent tile, so alpha is the ink coverage and the
/// comparison does not depend on the colour space. Anti-aliasing makes two correct renderings differ by a few percent
/// of their ink, and a vertically mirrored glyph differs by most of it, so the assertions use the share of ink that
/// disagrees (``inkMismatch(_:_:)``) against ``tolerance``.
@Suite
struct TextTypesetterGlyphOrientationTests {
    private static let fontName = "Menlo-Regular"
    private static let pointSize = 20.0
    private static let lineHeight = 28.0
    private static let padding = 4.0
    private static let scale = 2.0
    /// The most ink a tile line may disagree with its native rendering on, as a share of the ink in either. The fixed
    /// code measures 0.0 on every case (identical pixels); a glyph mirrored about its baseline measures about 0.92.
    private static let tolerance = 0.10

    private static let plainStyle = TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0)))
    /// A row tall enough that a glyph flipped about its baseline would still land in the top band.
    private static let tallLineHeight = 60.0

    /// The rows each parity case draws: one row with glyphs that differ from their reflections (b/p, d/q, n/u), one
    /// of ordinary text, and both together to check each row lands in its own band.
    static let parityRows: [[String]] = [
        ["bdpq nu"], ["Hello, world!"], ["bdpq nu", "Hello, world!"]
    ]

    // MARK: Tests

    @Test(arguments: Self.parityRows)
    func `a tile's glyphs are upright, as CoreText draws them in an unflipped bitmap`(rows: [String]) throws {
        let fixture = try Self.fixture(rows: rows, lineHeight: Self.lineHeight, wrap: .none)
        try #require(fixture.tile.bandCount == rows.count, "the tile should hold one band per row")
        for band in 0 ..< rows.count {
            let tile = fixture.tile.band(band)
            let native = fixture.native.band(band)
            try #require(Self.ink(native) > 0, "the native reference of band \(band) drew nothing")
            let fromNative = Self.inkMismatch(tile, native)
            #expect(
                fromNative <= Self.tolerance,
                "band \(band) of \(rows) differs from the native rendering on \(fromNative) of its ink")
        }
    }

    /// A row that wraps to two visual lines is drawn line by line, so a text matrix lost between the lines would
    /// leave the second line flipped.
    @Test
    func `a wrapped row's glyphs are upright on each of its visual lines`() throws {
        let fixture = try Self.fixture(rows: ["bdpq nu"], lineHeight: Self.lineHeight, wrap: .columns(4))
        try #require(fixture.tile.bandCount == 2, "the row should wrap to two visual lines")
        for band in 0 ..< 2 {
            let tile = fixture.tile.band(band)
            let native = fixture.native.band(band)
            try #require(Self.ink(native) > 0, "the native reference of line \(band) drew nothing")
            let fromNative = Self.inkMismatch(tile, native)
            #expect(
                fromNative <= Self.tolerance,
                "visual line \(band) differs from the native rendering on \(fromNative) of its ink")
        }
    }

    /// Guards against flipping the whole tile: the first row's ink must sit in the top band, and nothing in the bottom.
    /// The rows are tall so that a glyph flipped about its baseline would still land in the top band.
    @Test
    func `the first row's ink is in the top band of the tile and nothing is in the bottom band`() throws {
        let fixture = try Self.fixture(rows: ["MMMMMMMM", ""], lineHeight: Self.tallLineHeight, wrap: .none)
        #expect(Self.ink(fixture.tile.band(0)) > 0)
        #expect(Self.ink(fixture.tile.band(1)) == 0)
    }

    // MARK: Fixture

    /// What the tile and the native rendering drew for one set of rows.
    private struct Fixture {
        var tile: Pixels
        var native: Pixels
    }

    private static func fixture(
        rows: [String], lineHeight: Double, wrap: LayoutConfiguration.Wrap
    ) throws -> Fixture {
        let configuration = LayoutConfiguration(wrap: wrap, lineHeight: lineHeight, padding: padding)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let text = StyledText.plain(
            rows: rows, font: FontSpec(postScriptName: fontName, pointSize: pointSize), plainStyle: plainStyle)
        let range = RowIndex(0) ..< RowIndex(rows.count)
        let geometry = try TextTypesetter.layoutSynchronously(range, of: text, configuration: configuration)
        let baseline = try #require(geometry.first?.lines.first?.baseline)
        let tile = try TextTypesetter.renderSynchronously(
            range, of: text, decorations: [], configuration: configuration, appearance: .light,
            colorSpace: colorSpace, scale: scale)
        // One native line per visual line of the tile's geometry, each at its own top.
        var lines: [(text: String, top: Double)] = []
        for (row, rowGeometry) in zip(rows, geometry) {
            let bytes = Array(row.utf8)
            for visual in rowGeometry.lines {
                let lower = Int(visual.bytes.lowerBound.rawValue)
                let upper = Int(visual.bytes.upperBound.rawValue)
                let text = String(decoding: bytes[lower ..< upper], as: UTF8.self)
                lines.append((text, Double(lines.count) * lineHeight))
            }
        }
        let native = try nativeImage(
            lines: lines, imageHeight: Double(lines.count) * lineHeight, width: tile.image.width,
            height: tile.image.height, baseline: Double(baseline), colorSpace: colorSpace)
        let bandHeight = Int(lineHeight * scale)
        return Fixture(
            tile: try Pixels(tile.image, bandHeight: bandHeight, colorSpace: colorSpace),
            native: try Pixels(native, bandHeight: bandHeight, colorSpace: colorSpace))
    }

    /// `lines` drawn the canonical way: plain CoreText into an unflipped bitmap of `width` by `height` pixels.
    private static func nativeImage(
        lines: [(text: String, top: Double)], imageHeight: Double, width: Int, height: Int, baseline: Double,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let font = CTFontCreateWithName(fontName as CFString, CGFloat(pointSize), nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        ]
        for line in lines {
            let attributed = try #require(
                CFAttributedStringCreate(kCFAllocatorDefault, line.text as CFString, attributes as CFDictionary))
            let ctLine = CTLineCreateWithAttributedString(attributed)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: CGFloat(padding), y: CGFloat(imageHeight - line.top - baseline))
            CTLineDraw(ctLine, context)
        }
        return try #require(context.makeImage())
    }

    // MARK: Pixels

    /// The alpha plane of an image, top row first.
    private struct Pixels {
        var width: Int
        var height: Int
        var alpha: [UInt8]
        /// The pixel rows of one text line.
        var bandHeight: Int

        /// The number of text lines the image holds.
        var bandCount: Int { height / bandHeight }

        init(_ image: CGImage, bandHeight: Int, colorSpace: CGColorSpace) throws {
            let width = image.width
            let height = image.height
            let context = try #require(
                CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = try #require(context.data)
            let bytes = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4)
            self.width = width
            self.height = height
            self.bandHeight = bandHeight
            alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        }

        private init(width: Int, height: Int, alpha: [UInt8], bandHeight: Int) {
            self.width = width
            self.height = height
            self.alpha = alpha
            self.bandHeight = bandHeight
        }

        /// The pixel rows of text line `index`.
        func band(_ index: Int) -> Pixels {
            let rows = (index * bandHeight ..< (index + 1) * bandHeight)
                .map { Array(alpha[$0 * width ..< ($0 + 1) * width]) }
            return Pixels(width: width, height: bandHeight, alpha: rows.flatMap { $0 }, bandHeight: bandHeight)
        }
    }

    /// The summed alpha of `pixels`.
    private static func ink(_ pixels: Pixels) -> Int {
        pixels.alpha.reduce(0) { $0 + Int($1) }
    }

    /// The ink that differs between two same-sized renderings, as a share of the ink in either: 0 for identical
    /// pixels, about 1 for renderings that share none.
    private static func inkMismatch(_ lhs: Pixels, _ rhs: Pixels) -> Double {
        var difference = 0
        var total = 0
        for (left, right) in zip(lhs.alpha, rhs.alpha) {
            difference += abs(Int(left) - Int(right))
            total += max(Int(left), Int(right))
        }
        return Double(difference) / Double(max(total, 1))
    }
}
