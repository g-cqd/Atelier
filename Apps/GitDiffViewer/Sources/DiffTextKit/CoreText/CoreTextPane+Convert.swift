import AppKit
import AtelierSyntaxModel
import AtelierTextRendering
import DiffRendering
import Foundation

/// `RenderedText`/`DiffDecorations` (TextKit-shaped: UTF-16, `NSColor`) converted to `AtelierTextRendering`'s
/// backend-neutral model (UTF-8 bytes, `ColorRef`), for `CoreTextPane` to show.
extension CoreTextPane {
    /// The text and its decoration layers for `rendered`, coloured from `decorations` when given.
    /// - Complexity: O(bytes in `rendered`).
    static func convert(rendered: RenderedText, decorations: DiffDecorations?) -> (
        text: StyledText, layers: [DecorationLayer]
    ) {
        let rowStrings = Self.rowStrings(of: rendered)
        let units = rowStrings.map(RowUnits.init)

        var utf8: [UInt8] = []
        var rowStarts: [UInt32] = []
        var runs: [LineRuns.Run] = []
        var offsets: [UInt32] = []
        var rowFills: [RowIndex: [DecorationLayer.Paint]] = [:]
        var emphasisFills: [RowIndex: [DecorationLayer.Paint]] = [:]

        for (index, unit) in units.enumerated() {
            let row = rendered.rows[index]
            rowStarts.append(UInt32(utf8.count))
            offsets.append(UInt32(runs.count))
            if let decorations {
                for token in decorations.tokens(of: row, on: rendered.side) ?? [] {
                    appendRun(&runs, token: token, unit: unit)
                }
                if let background = rendered.palette.rowBackground(
                    for: row.kind, side: rendered.side, isMoved: decorations.isMoved(row))
                {
                    rowFills[RowIndex(index), default: []].append(.rowFill(Self.colorRef(background)))
                }
                let emphasis = decorations.emphasis(of: row, on: rendered.side)
                if !emphasis.isEmpty {
                    let color = Self.colorRef(rendered.palette.emphasis(for: row.kind, side: rendered.side))
                    for range in emphasis {
                        appendEmphasis(&emphasisFills, row: index, range: range, unit: unit, color: color)
                    }
                }
            }
            utf8.append(contentsOf: unit.utf8)
        }
        rowStarts.append(UInt32(utf8.count))
        offsets.append(UInt32(runs.count))

        let font = rendered.palette.font
        let styleSheet = StyleSheet(
            font: FontSpec(postScriptName: font.fontName, pointSize: font.pointSize),
            styles: [TextStyle(foreground: Self.colorRef(rendered.palette.textColor))]
                + HighlightRole.allCases.map { TextStyle(foreground: Self.colorRef(rendered.palette.color(for: $0))) })
        let text = StyledText(
            utf8: utf8, rowStarts: rowStarts, runs: LineRuns(runs: runs, offsets: offsets), styles: styleSheet)

        var layers: [DecorationLayer] = []
        if !rowFills.isEmpty { layers.append(DecorationLayer(id: LayerID(0), zIndex: 0, paints: rowFills)) }
        if !emphasisFills.isEmpty { layers.append(DecorationLayer(id: LayerID(1), zIndex: 1, paints: emphasisFills)) }
        return (text, layers)
    }

    private static func appendRun(_ runs: inout [LineRuns.Run], token: LineToken, unit: RowUnits) {
        let start = unit.byteOffset(atUTF16: Int(token.start))
        let end = unit.byteOffset(atUTF16: Int(token.start) + Int(token.length))
        guard end > start else { return }
        let styleID = StyleID(UInt16(token.role.rawValue) + 1)
        runs.append(
            LineRuns.Run(start: UInt32(start), length: UInt16(min(end - start, Int(UInt16.max))), style: styleID))
    }

    private static func appendEmphasis(
        _ fills: inout [RowIndex: [DecorationLayer.Paint]], row: Int, range: Range<Int>, unit: RowUnits, color: ColorRef
    ) {
        let start = unit.byteOffset(atUTF16: range.lowerBound)
        let end = unit.byteOffset(atUTF16: range.upperBound)
        guard end > start else { return }
        fills[RowIndex(row), default: []].append(.rangeFill(ByteOffset(start) ..< ByteOffset(end), color))
    }

    /// Every row's plain text, from `rendered`'s one attributed string: its UTF-16 range, less the newline joining it
    /// to the next.
    private static func rowStrings(of rendered: RenderedText) -> [String] {
        let full = rendered.attributed.string as NSString
        var rows: [String] = []
        rows.reserveCapacity(rendered.rows.count)
        for index in 0 ..< rendered.rows.count {
            let start = rendered.lineStarts[index]
            let end = index + 1 < rendered.lineStarts.count ? rendered.lineStarts[index + 1] - 1 : full.length
            let length = max(min(end, full.length) - start, 0)
            rows.append(full.substring(with: NSRange(location: start, length: length)))
        }
        return rows
    }

    /// `color` resolved under the system light and dark appearances, once, so a tile drawn in either needs no further
    /// appearance lookup (text-renderer.md §3.2: colour is resolved per appearance at render time from a `ColorRef`,
    /// never from a live `NSColor`).
    static func colorRef(_ color: NSColor) -> ColorRef {
        .adaptive(
            light: Self.rgba(color, appearance: NSAppearance(named: .aqua)),
            dark: Self.rgba(color, appearance: NSAppearance(named: .darkAqua)))
    }

    private static func rgba(_ color: NSColor, appearance: NSAppearance?) -> RGBA {
        var result = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
        let resolve = {
            let resolved = color.usingColorSpace(.sRGB) ?? color
            result = RGBA(
                red: Float(resolved.redComponent), green: Float(resolved.greenComponent),
                blue: Float(resolved.blueComponent), alpha: Float(resolved.alphaComponent))
        }
        if let appearance { appearance.performAsCurrentDrawingAppearance(resolve) } else { resolve() }
        return result
    }
}

/// A row's UTF-16 offsets (`DiffDecorations`' unit) mapped to UTF-8 byte offsets (`AtelierTextRendering`'s).
struct RowUnits {
    let utf8: [UInt8]
    private let utf16ToByte: [Int]

    init(_ string: String) {
        utf8 = Array(string.utf8)
        var map: [Int] = []
        map.reserveCapacity(string.utf16.count + 1)
        var byteOffset = 0
        for scalar in string.unicodeScalars {
            let utf16Length = scalar.value > 0xFFFF ? 2 : 1
            for _ in 0 ..< utf16Length { map.append(byteOffset) }
            byteOffset += UTF8.width(scalar)
        }
        map.append(byteOffset)
        utf16ToByte = map
    }

    func byteOffset(atUTF16 index: Int) -> Int {
        guard index >= 0 else { return 0 }
        guard index < utf16ToByte.count else { return utf16ToByte.last ?? 0 }
        return utf16ToByte[index]
    }
}
