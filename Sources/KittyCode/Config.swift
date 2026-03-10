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
        var backgroundColor = ColorRGB(r: 0x1e, g: 0x1e, b: 0x1e)
        var treePanelBackground = ColorRGB(r: 0x18, g: 0x18, b: 0x18)
        var treePanelForeground = ColorRGB(r: 0xcc, g: 0xcc, b: 0xcc)
        var treeSelectedBackground = ColorRGB(r: 0x26, g: 0x4f, b: 0x78)
        var treeSelectedForeground = ColorRGB(r: 0xff, g: 0xff, b: 0xff)
        var editorForeground = ColorRGB(r: 0xd4, g: 0xd4, b: 0xd4)
        var editorCursorLineBackground = ColorRGB(r: 0x28, g: 0x28, b: 0x28)
        var statusBarBackground = ColorRGB(r: 0x00, g: 0x7a, b: 0xcc)
        var statusBarForeground = ColorRGB(r: 0xff, g: 0xff, b: 0xff)
        var titleBarBackground = ColorRGB(r: 0x32, g: 0x32, b: 0x32)
        var titleBarForeground = ColorRGB(r: 0xcc, g: 0xcc, b: 0xcc)
    }

    var keybindingMode: KeybindingMode = .nano
    var wrapLines = false
    var treeWidth = 30
    var theme = Theme()

    static func load() -> KittyConfig {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".kittycode.json")
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(KittyConfig.self, from: data) {
            return config
        }
        return KittyConfig()
    }
}