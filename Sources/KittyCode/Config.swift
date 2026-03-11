import Foundation
import KittyCodecs

struct ColorRGB: Sendable, Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    var color: Color { .rgb(r: r, g: g, b: b) }

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") {
            value = String(value.dropFirst())
        }

        guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
            return nil
        }

        self.r = UInt8((rgb >> 16) & 0xFF)
        self.g = UInt8((rgb >> 8) & 0xFF)
        self.b = UInt8(rgb & 0xFF)
    }
}

extension ColorRGB: Codable {
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let hex = try? container.decode(String.self),
           let color = ColorRGB(hex: hex) {
            self = color
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.r = try container.decode(UInt8.self, forKey: .r)
        self.g = try container.decode(UInt8.self, forKey: .g)
        self.b = try container.decode(UInt8.self, forKey: .b)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "#%02x%02x%02x", r, g, b))
    }

    private enum CodingKeys: String, CodingKey {
        case r
        case g
        case b
    }
}

struct KittyConfig: Codable, Sendable {
    enum KeybindingMode: String, Codable, Sendable {
        case nano
        case vim
    }

    struct Theme: Codable, Sendable {
        // GitHub Dark (foreground-focused) defaults.
        // Backgrounds are intentionally omitted so terminal default background is preserved.
        var treePanelForeground = ColorRGB(r: 0xc9, g: 0xd1, b: 0xd9)
        var treeSelectedForeground = ColorRGB(r: 0x58, g: 0xa6, b: 0xff)
        var treeDirectoryForeground = ColorRGB(r: 0x7e, g: 0xe7, b: 0x87)
        var editorForeground = ColorRGB(r: 0xc9, g: 0xd1, b: 0xd9)
        var lineNumberForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        var statusBarForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        var titleBarForeground = ColorRGB(r: 0xf0, g: 0xf6, b: 0xfc)
        var separatorForeground = ColorRGB(r: 0x30, g: 0x36, b: 0x3d)

        var keywordForeground = ColorRGB(r: 0xff, g: 0x7b, b: 0x72)
        var typeForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        var commentForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        var stringForeground = ColorRGB(r: 0xa5, g: 0xd6, b: 0xff)
        var numberForeground = ColorRGB(r: 0x79, g: 0xc0, b: 0xff)
        var attributeForeground = ColorRGB(r: 0xd2, g: 0xa8, b: 0xff)

        var gitModifiedForeground = ColorRGB(r: 0xe3, g: 0xb3, b: 0x41)
        var gitAddedForeground = ColorRGB(r: 0x3f, g: 0xb9, b: 0x50)
        var gitUntrackedForeground = ColorRGB(r: 0x8b, g: 0x94, b: 0x9e)
        var gitDeletedForeground = ColorRGB(r: 0xf8, g: 0x51, b: 0x49)
        var gitConflictedForeground = ColorRGB(r: 0xff, g: 0x7b, b: 0x72)
    }

    var keybindingMode: KeybindingMode = .nano
    var wrapLines = false
    var treeWidth = 30
    var useSFSymbolsInTerminal = true
    var theme = Theme()

    static func load() -> KittyConfig {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".kittycode.json")
        guard let data = try? Data(contentsOf: configURL) else {
            return KittyConfig()
        }
        do {
            return try JSONDecoder().decode(KittyConfig.self, from: data)
        } catch {
            FileHandle.standardError.write(
                Data("Warning: failed to parse ~/.kittycode.json: \(error). Using defaults.\n".utf8)
            )
            return KittyConfig()
        }
    }
}
