import Foundation

// MARK: - ColorRGB

public struct ColorRGB: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public var color: Color { .rgb(r: r, g: g, b: b) }

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init?(hex: String) {
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

// MARK: - Codable

extension ColorRGB: Codable {
    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "#%02x%02x%02x", r, g, b))
    }

    private enum CodingKeys: String, CodingKey {
        case r
        case g
        case b
    }
}
