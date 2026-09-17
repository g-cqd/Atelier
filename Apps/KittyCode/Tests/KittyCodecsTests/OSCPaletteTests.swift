import Testing

@testable import KittyCodecs

/// The palette query and the replies a terminal sends back.
struct OSCPaletteTests {
    @Test
    func `the query asks for foreground, background, the ANSI slots and ends with device attributes`() {
        let query = String(decoding: OSCPalette.query(ansiCount: 2), as: UTF8.self)
        #expect(query == "\u{1b}]10;?\u{1b}\\\u{1b}]11;?\u{1b}\\\u{1b}]4;0;?\u{1b}\\\u{1b}]4;1;?\u{1b}\\\u{1b}[c")
    }

    @Test(arguments: [
        ("\u{1b}]10;rgb:ffff/8000/0000\u{1b}\\", OSCPalette.Reply.foreground(ColorRGB(r: 255, g: 128, b: 0))),
        ("\u{1b}]11;rgb:1c/1c/1c\u{07}", .background(ColorRGB(r: 28, g: 28, b: 28))),
        ("\u{1b}]4;9;rgb:f/0/8\u{1b}\\", .ansi(index: 9, ColorRGB(r: 255, g: 0, b: 136))),
        ("\u{1b}]4;1;#c81e1e\u{07}", .ansi(index: 1, ColorRGB(r: 200, g: 30, b: 30))),
        ("\u{1b}[?62;22c", .end)
    ])
    func `replies parse in every digit width and terminator`(sequence: String, reply: OSCPalette.Reply) {
        #expect(OSCPalette.parse(Array(sequence.utf8)) == reply)
    }

    @Test(arguments: [
        "\u{1b}]10;rgb:ff/ff\u{1b}\\", "\u{1b}]4;x;rgb:0/0/0\u{07}", "\u{1b}]4;256;rgb:0/0/0\u{07}",
        "\u{1b}]4;-1;rgb:0/0/0\u{07}", "\u{1b}]52;c;YQ==\u{07}", "\u{1b}[A",
        "\u{1b}]10;rgb:1/2/3",
        "abc"
    ])
    func `anything else is not a palette reply`(sequence: String) {
        #expect(OSCPalette.parse(Array(sequence.utf8)) == nil)
    }
}
