import Foundation
import KittyCodecs

struct ColorOverlayConfig: Codable, Sendable, Equatable {
    var color: ColorRGB
    var alpha: Double = 1

    init(color: ColorRGB, alpha: Double = 1) {
        self.color = ColorRGB(r: color.r, g: color.g, b: color.b)
        self.alpha = min(1, max(0, alpha * color.alpha))
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let hex = try? singleValue.decode(String.self),
           let parsed = ColorRGB(hex: hex) {
            self.color = ColorRGB(r: parsed.r, g: parsed.g, b: parsed.b)
            self.alpha = parsed.alpha
            return
        }

        if let singleValue = try? decoder.singleValueContainer(),
           let color = try? singleValue.decode(ColorRGB.self) {
            self = ColorOverlayConfig(color: color)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let color = try container.decode(ColorRGB.self, forKey: .color)
        let alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        self = ColorOverlayConfig(color: color, alpha: alpha)
    }

    func encode(to encoder: Encoder) throws {
        if alpha == 1 {
            var singleValue = encoder.singleValueContainer()
            try singleValue.encode(color)
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(alpha, forKey: .alpha)
    }

    private enum CodingKeys: String, CodingKey {
        case color
        case alpha
    }
}
