import AppKit
import Foundation
import Testing

@testable import DiffRendering

/// The one line height every pane and backend takes (text-renderer.md §5, M0 item 9): measured with TextKit 2, it
/// matches what the TextKit 1 object it replaces answered, on the fonts where no CoreText formula does.
struct FontLineHeightTests {
    /// A font by name, the system's monospaced one for a nil name.
    struct FontCase: Sendable, CustomTestStringConvertible {
        let name: String?
        let size: CGFloat
        let bold: Bool

        var font: NSFont? {
            guard let name else {
                return .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
            }
            return NSFont(name: name, size: size)
        }

        var testDescription: String { "\(name ?? "system monospaced")\(bold ? " bold" : "") \(size) pt" }
    }

    static let fonts = [
        FontCase(name: nil, size: 12, bold: false),
        FontCase(name: nil, size: 17, bold: true),
        FontCase(name: "Menlo", size: 12, bold: false),
        FontCase(name: "SFMono-Regular", size: 12, bold: false),
        FontCase(name: "Helvetica", size: 13, bold: false)
    ]

    @Test(arguments: fonts)
    func `a font's line height is what TextKit 1 gave it`(fontCase: FontCase) throws {
        // A font the machine does not have is not measured.
        guard let font = fontCase.font else { return }
        #expect(FontLineHeight.of(font) == NSLayoutManager().defaultLineHeight(for: font))
    }

    @Test
    func `a palette takes its font's measured line height`() {
        let palette = DiffPalette.system
        #expect(palette.defaultLineHeight == FontLineHeight.of(palette.font))
        #expect(palette.defaultLineHeight > 0)
    }

    /// The palette's cost of its line height, the TextKit 1 object built per palette against the measurement cached
    /// per font. Run in release with GDV_BENCH=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `line height per palette, TextKit 1 against the cached measurement`() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let clock = ContinuousClock()
        let iterations = 1_000
        var textKit1: [Double] = []
        var cached: [Double] = []
        var sink: CGFloat = 0
        for _ in 0 ..< 11 {
            let before = clock.now
            for _ in 0 ..< iterations { sink += NSLayoutManager().defaultLineHeight(for: font) }
            textKit1.append(Self.microseconds(clock.now - before) / Double(iterations))
            let middle = clock.now
            for _ in 0 ..< iterations { sink += FontLineHeight.of(font) }
            cached.append(Self.microseconds(clock.now - middle) / Double(iterations))
        }
        let first = clock.now
        sink += FontLineHeight.measure(font)
        let measuring = Self.microseconds(clock.now - first)
        print(
            "BENCH palette line height: TextKit 1 object \(Self.summary(textKit1)); cached TextKit 2 "
                + "\(Self.summary(cached)); one uncached measurement \(String(format: "%.1f", measuring)) us "
                + "(\(sink > 0))")
    }

    private static func microseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1e6 + Double(duration.components.attoseconds) / 1e12
    }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        func format(_ value: Double) -> String { String(format: "%.3f", value) }
        return "median \(format(sorted[sorted.count / 2])) us (p10 \(format(sorted[sorted.count / 10])), "
            + "p90 \(format(sorted[sorted.count * 9 / 10])))"
    }
}
