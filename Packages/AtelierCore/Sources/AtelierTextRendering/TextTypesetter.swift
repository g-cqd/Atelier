public import CoreGraphics
import CoreText

/// Typesets and draws rows with CoreText, off the main actor (text-renderer.md §3.4). Every CoreText object is built,
/// used and released inside one call: none of `CTFont`, `CTLine` or `CTTypesetter` is `Sendable`, so none crosses a
/// task boundary. Only `Sendable` value types and `CGImage` (itself `Sendable`) come back.
///
/// Colour is resolved and baked into the attributed string ``render(_:of:decorations:configuration:appearance:colorSpace:scale:)``
/// typesets, and text draws with `CTLineDraw`; ``layout(_:of:configuration:)`` typesets the same breaks without any
/// colour, for geometry alone. Drawing glyph runs directly with `CTFontDrawGlyphs` is a follow-up performance pass
/// (text-renderer.md §3.5); `CTLineDraw` is correct and simple, and M1's budget is for a tile of some 32 rows, not a
/// whole document.
public enum TextTypesetter {
    /// Geometry of `rows`.
    /// - Complexity: O(bytes in rows). Throws only on cancellation.
    @concurrent
    public static func layout(
        _ rows: Range<RowIndex>, of text: StyledText, configuration: LayoutConfiguration
    ) async throws(CancellationError) -> [RowGeometry] {
        try layoutSynchronously(rows, of: text, configuration: configuration)
    }

    /// ``layout(_:of:configuration:)``'s synchronous core: nothing in it ever suspends, so a caller that already
    /// needs an immediate answer off an `async` boundary — a gutter, a minimap or hover hit-testing reading geometry
    /// from the main actor — can call it directly instead of awaiting a child task for cheap, bounded ranges.
    public static func layoutSynchronously(
        _ rows: Range<RowIndex>, of text: StyledText, configuration: LayoutConfiguration
    ) throws(CancellationError) -> [RowGeometry] {
        let baseFont = Self.font(for: text.styles.font, weight: nil, isItalic: false)
        var fontCache: [FontKey: CTFont] = [FontKey(font: text.styles.font, weight: nil, isItalic: false): baseFont]
        let wrapWidth = Self.wrapWidth(configuration: configuration, cellAdvance: Self.cellAdvance(of: baseFont))
        let baseline = Self.baseline(font: baseFont, lineHeight: configuration.resolvedLineHeight)
        var results: [RowGeometry] = []
        results.reserveCapacity(rows.count)
        for rawRow in stride(from: rows.lowerBound.rawValue, to: rows.upperBound.rawValue, by: 1) {
            if Task.isCancelled { throw CancellationError() }
            let row = RowIndex(rawRow)
            let rowText = RowText(bytes: text.bytes(ofRow: row))
            let attributed = Self.attributedString(
                rowText: rowText, runs: text.runs[row], sheet: text.styles, fontCache: &fontCache, includeColor: false,
                appearance: .light)
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let breaks = Self.breakLines(typesetter: typesetter, length: rowText.utf16Count, wrapWidth: wrapWidth)
            var lines: [VisualLine] = []
            lines.reserveCapacity(breaks.count)
            for range in breaks {
                let line = CTTypesetterCreateLine(typesetter, range)
                lines.append(Self.visualLine(line: line, range: range, rowText: rowText, baseline: baseline))
            }
            let height = Float(configuration.resolvedLineHeight) * Float(max(lines.count, 1))
            results.append(RowGeometry(height: height, lines: lines))
        }
        return results
    }

    /// Typesets and draws `rows` into one image in `colorSpace`.
    @concurrent
    // swiftlint:disable:next function_parameter_count
    public static func render(
        _ rows: Range<RowIndex>, of text: StyledText, decorations: [DecorationLayer],
        configuration: LayoutConfiguration, appearance: Appearance, colorSpace: CGColorSpace, scale: Double
    ) async throws(CancellationError) -> RenderedTile {
        try renderSynchronously(
            rows, of: text, decorations: decorations, configuration: configuration, appearance: appearance,
            colorSpace: colorSpace, scale: scale)
    }

    /// ``render(_:of:decorations:configuration:appearance:colorSpace:scale:)``'s synchronous core; see
    /// ``layoutSynchronously(_:of:configuration:)``.
    // swiftlint:disable:next function_parameter_count
    public static func renderSynchronously(
        _ rows: Range<RowIndex>, of text: StyledText, decorations: [DecorationLayer],
        configuration: LayoutConfiguration, appearance: Appearance, colorSpace: CGColorSpace, scale: Double
    ) throws(CancellationError) -> RenderedTile {
        let baseFont = Self.font(for: text.styles.font, weight: nil, isItalic: false)
        var fontCache: [FontKey: CTFont] = [FontKey(font: text.styles.font, weight: nil, isItalic: false): baseFont]
        let wrapWidth = Self.wrapWidth(configuration: configuration, cellAdvance: Self.cellAdvance(of: baseFont))
        let baseline = Self.baseline(font: baseFont, lineHeight: configuration.resolvedLineHeight)
        let lineHeight = configuration.resolvedLineHeight

        var geometry: [RowGeometry] = []
        var rowTops: [Double] = []
        var rowTexts: [RowText] = []
        var drawLines: [[(line: CTLine, y: Double)]] = []
        var totalWidth: Double = 1
        var y: Double = 0

        for rawRow in stride(from: rows.lowerBound.rawValue, to: rows.upperBound.rawValue, by: 1) {
            if Task.isCancelled { throw CancellationError() }
            let row = RowIndex(rawRow)
            let rowText = RowText(bytes: text.bytes(ofRow: row))
            let attributed = Self.attributedString(
                rowText: rowText, runs: text.runs[row], sheet: text.styles, fontCache: &fontCache, includeColor: true,
                appearance: appearance)
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let breaks = Self.breakLines(typesetter: typesetter, length: rowText.utf16Count, wrapWidth: wrapWidth)
            rowTops.append(y)
            var visualLines: [VisualLine] = []
            var lines: [(CTLine, Double)] = []
            for range in breaks {
                let line = CTTypesetterCreateLine(typesetter, range)
                let visual = Self.visualLine(line: line, range: range, rowText: rowText, baseline: baseline)
                totalWidth = max(totalWidth, Double(visual.width) + configuration.padding * 2)
                visualLines.append(visual)
                lines.append((line, y))
                y += lineHeight
            }
            geometry.append(
                RowGeometry(height: Float(lineHeight) * Float(max(visualLines.count, 1)), lines: visualLines))
            drawLines.append(lines)
            rowTexts.append(rowText)
        }
        let totalHeight = max(y, 1)

        let scale = max(scale, 1)
        let pixelWidth = max(Int((totalWidth * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((totalHeight * scale).rounded(.up)), 1)
        guard
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CancellationError() }
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        // A flipped, top-left origin so row `y` matches document coordinates.
        context.translateBy(x: 0, y: CGFloat(totalHeight))
        context.scaleBy(x: 1, y: -1)

        let environment = PaintEnvironment(totalWidth: totalWidth, lineHeight: lineHeight, appearance: appearance)
        for layer in decorations.sorted(by: { $0.zIndex < $1.zIndex }) {
            for (index, rawRow) in stride(from: rows.lowerBound.rawValue, to: rows.upperBound.rawValue, by: 1)
                .enumerated()
            {
                guard let paints = layer.paints[RowIndex(rawRow)] else { continue }
                let target = RowPaintTarget(
                    top: rowTops[index], height: Double(geometry[index].height), lines: drawLines[index],
                    rowText: rowTexts[index])
                for paint in paints { Self.draw(paint, row: target, in: environment, context: context) }
            }
        }

        for lines in drawLines {
            for (line, lineY) in lines {
                context.textPosition = CGPoint(x: CGFloat(configuration.padding), y: CGFloat(lineY + Double(baseline)))
                CTLineDraw(line, context)
            }
        }

        guard let image = context.makeImage() else { throw CancellationError() }
        return RenderedTile(rows: rows, image: image, geometry: geometry)
    }
}

// The typesetting and drawing helpers, split from ``TextTypesetter``'s own body only to stay under the file's
// type-body-length limit; there is no visibility change, since `private` is file-scoped.
extension TextTypesetter {
    // MARK: Fonts

    private struct FontKey: Hashable {
        var font: FontSpec
        var weight: FontWeight?
        var isItalic: Bool
    }

    private static func font(for spec: FontSpec, weight: FontWeight?, isItalic: Bool) -> CTFont {
        var base: CTFont
        if let name = spec.postScriptName, !name.isEmpty {
            base = CTFontCreateWithName(name as CFString, CGFloat(spec.pointSize), nil)
        } else {
            base =
                CTFontCreateUIFontForLanguage(.userFixedPitch, CGFloat(spec.pointSize), nil)
                ?? CTFontCreateWithName("Menlo" as CFString, CGFloat(spec.pointSize), nil)
        }
        if !spec.features.isEmpty {
            let settings =
                spec.features.map { feature -> CFDictionary in
                    let entry: [CFString: Any] = [
                        kCTFontOpenTypeFeatureTag: feature.tag, kCTFontOpenTypeFeatureValue: feature.value
                    ]
                    return entry as CFDictionary
                } as CFArray
            let attributes: [CFString: Any] = [kCTFontFeatureSettingsAttribute: settings]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            base = CTFontCreateCopyWithAttributes(base, CGFloat(spec.pointSize), nil, descriptor)
        }
        if weight != nil || isItalic {
            var value = CTFontSymbolicTraits(rawValue: 0)
            var mask = CTFontSymbolicTraits(rawValue: 0)
            if let weight, weight >= .semibold {
                value.insert(.traitBold)
                mask.insert(.traitBold)
            }
            if isItalic {
                value.insert(.traitItalic)
                mask.insert(.traitItalic)
            }
            if let styled = CTFontCreateCopyWithSymbolicTraits(base, CGFloat(spec.pointSize), nil, value, mask) {
                base = styled
            }
        }
        return base
    }

    /// The advance of one cell: the digit "0" of `font`, or an estimate when the font has none.
    private static func cellAdvance(of font: CTFont) -> Double {
        var character = UniChar(UnicodeScalar("0").value)
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1), glyph != 0 else {
            return Double(CTFontGetSize(font)) * 0.6
        }
        var advance = CGSize.zero
        withUnsafePointer(to: glyph) { pointer in
            _ = CTFontGetAdvancesForGlyphs(font, .horizontal, pointer, &advance, 1)
        }
        return advance.width > 0 ? Double(advance.width) : Double(CTFontGetSize(font)) * 0.6
    }

    /// Baseline y from the top of a line box `lineHeight` tall, the font's own ascent and descent centred in it.
    private static func baseline(font: CTFont, lineHeight: Double) -> Float {
        let ascent = Double(CTFontGetAscent(font))
        let descent = Double(CTFontGetDescent(font))
        let extra = max((lineHeight - (ascent + descent)) / 2, 0)
        return Float(ascent + extra)
    }

    // MARK: Attributed strings

    private static func attributedString(
        rowText: RowText, runs: ArraySlice<LineRuns.Run>, sheet: StyleSheet, fontCache: inout [FontKey: CTFont],
        includeColor: Bool, appearance: Appearance
    ) -> CFAttributedString {
        let mutable = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(mutable, CFRange(location: 0, length: 0), rowText.string as CFString)
        let fullRange = CFRange(location: 0, length: rowText.utf16Count)
        let plainStyle = sheet[StyleID(0)] ?? TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0)))

        func resolvedFont(_ style: TextStyle) -> CTFont {
            let key = FontKey(font: sheet.font, weight: style.weight, isItalic: style.isItalic)
            if let cached = fontCache[key] { return cached }
            let made = Self.font(for: sheet.font, weight: style.weight, isItalic: style.isItalic)
            fontCache[key] = made
            return made
        }

        CFAttributedStringSetAttribute(mutable, fullRange, kCTFontAttributeName, resolvedFont(plainStyle))
        if includeColor {
            CFAttributedStringSetAttribute(
                mutable, fullRange, kCTForegroundColorAttributeName,
                Self.cgColor(plainStyle.foreground.resolved(for: appearance)))
        }
        for run in runs {
            guard let style = sheet[run.style] else { continue }
            let start = rowText.utf16Offset(atByte: Int(run.start))
            let end = rowText.utf16Offset(atByte: Int(run.start) + Int(run.length))
            let range = CFRange(location: start, length: end - start)
            guard range.length > 0 else { continue }
            if !style.hasSameFont(as: plainStyle) {
                CFAttributedStringSetAttribute(mutable, range, kCTFontAttributeName, resolvedFont(style))
            }
            if includeColor {
                CFAttributedStringSetAttribute(
                    mutable, range, kCTForegroundColorAttributeName,
                    Self.cgColor(style.foreground.resolved(for: appearance)))
            }
        }
        return mutable
    }

    private static func cgColor(_ rgba: RGBA) -> CGColor {
        CGColor(
            srgbRed: CGFloat(rgba.red), green: CGFloat(rgba.green), blue: CGFloat(rgba.blue), alpha: CGFloat(rgba.alpha)
        )
    }

    // MARK: Line breaking and geometry

    private static func wrapWidth(configuration: LayoutConfiguration, cellAdvance: Double) -> Double? {
        switch configuration.wrap {
            case .none: nil
            case .width(let width): max(width - configuration.padding * 2, 1)
            case .columns(let count): Double(count) * cellAdvance
        }
    }

    private static func breakLines(typesetter: CTTypesetter, length: Int, wrapWidth: Double?) -> [CFRange] {
        guard let wrapWidth, wrapWidth > 0, length > 0 else {
            return [CFRange(location: 0, length: length)]
        }
        var ranges: [CFRange] = []
        var start = 0
        while start < length {
            let count = max(CTTypesetterSuggestLineBreak(typesetter, start, wrapWidth), 1)
            ranges.append(CFRange(location: start, length: count))
            start += count
        }
        return ranges
    }

    private static func visualLine(line: CTLine, range: CFRange, rowText: RowText, baseline: Float) -> VisualLine {
        var carets: [Float] = []
        carets.reserveCapacity(range.length + 1)
        for offset in range.location ... (range.location + range.length) {
            carets.append(Float(CTLineGetOffsetForStringIndex(line, offset, nil)))
        }
        let width = Float(CTLineGetTypographicBounds(line, nil, nil, nil))
        let startByte = rowText.byteOffset(atUTF16: range.location)
        let endByte = rowText.byteOffset(atUTF16: range.location + range.length)
        return VisualLine(
            bytes: ByteOffset(startByte) ..< ByteOffset(endByte), carets: carets, baseline: baseline, width: width)
    }

    // MARK: Decoration paint

    /// One row's already-typeset lines and text, for mapping a decoration's byte range to a rectangle.
    private struct RowPaintTarget {
        var top: Double
        var height: Double
        var lines: [(line: CTLine, y: Double)]
        var rowText: RowText
    }

    /// What every row's paint shares.
    private struct PaintEnvironment {
        var totalWidth: Double
        var lineHeight: Double
        var appearance: Appearance
    }

    private static func draw(
        _ paint: DecorationLayer.Paint, row: RowPaintTarget, in environment: PaintEnvironment, context: CGContext
    ) {
        let rowRect = CGRect(
            x: 0, y: CGFloat(row.top), width: CGFloat(environment.totalWidth), height: CGFloat(row.height))
        switch paint {
            case .rowFill(let color):
                context.setFillColor(Self.cgColor(color.resolved(for: environment.appearance)))
                context.fill(rowRect)
            case .rangeFill(let range, let color):
                guard
                    let rect = Self.rect(
                        for: range, lineHeight: environment.lineHeight, lines: row.lines, rowText: row.rowText)
                else { return }
                context.setFillColor(Self.cgColor(color.resolved(for: environment.appearance)))
                context.fill(rect)
            case .underline(let range, let shape, let color):
                let rect =
                    range.flatMap({
                        Self.rect(for: $0, lineHeight: environment.lineHeight, lines: row.lines, rowText: row.rowText)
                    }) ?? rowRect
                context.setStrokeColor(Self.cgColor(color.resolved(for: environment.appearance)))
                context.setLineWidth(shape == .double ? 2 : 1)
                let y = rect.minY + 1
                context.stroke(CGRect(x: rect.minX, y: y, width: rect.width, height: 0.5))
        }
    }

    /// The rectangle a byte range covers: the visual line whose row-relative UTF-16 range contains its start, the x
    /// of each end found through that line's own coordinates; approximate when a range spans more than one visual
    /// line, since a decoration layer paints per row and code emphasis rarely wraps.
    private static func rect(
        for range: Range<ByteOffset>, lineHeight: Double, lines: [(line: CTLine, y: Double)], rowText: RowText
    ) -> CGRect? {
        let start = rowText.utf16Offset(atByte: Int(range.lowerBound.rawValue))
        let end = rowText.utf16Offset(atByte: Int(range.upperBound.rawValue))
        guard end > start,
            let (line, y) = lines.first(where: { line, _ in
                let stringRange = CTLineGetStringRange(line)
                return start >= stringRange.location && start <= stringRange.location + stringRange.length
            }) ?? lines.first
        else { return nil }
        let stringRange = CTLineGetStringRange(line)
        let clampedStart = min(max(start, stringRange.location), stringRange.location + stringRange.length)
        let clampedEnd = min(max(end, stringRange.location), stringRange.location + stringRange.length)
        let startX = CTLineGetOffsetForStringIndex(line, clampedStart, nil)
        let endX = CTLineGetOffsetForStringIndex(line, clampedEnd, nil)
        guard endX > startX else { return nil }
        return CGRect(x: startX, y: CGFloat(y), width: endX - startX, height: CGFloat(lineHeight))
    }
}
