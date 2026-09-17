import Foundation
import KittyStyle

// MARK: - ColorRGB

public struct ColorRGB: Sendable, Equatable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var alpha: Double

    public var color: Color { .rgb(r: r, g: g, b: b) }

    public init(r: UInt8, g: UInt8, b: UInt8, alpha: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.alpha = min(1, max(0, alpha))
    }

    public init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") {
            value = String(value.dropFirst())
        }

        switch value.count {
            case 6:
                guard let rgb = UInt32(value, radix: 16) else { return nil }
                self.r = UInt8((rgb >> 16) & 0xFF)
                self.g = UInt8((rgb >> 8) & 0xFF)
                self.b = UInt8(rgb & 0xFF)
                self.alpha = 1
            case 8:
                guard let rgba = UInt32(value, radix: 16) else { return nil }
                self.r = UInt8((rgba >> 24) & 0xFF)
                self.g = UInt8((rgba >> 16) & 0xFF)
                self.b = UInt8((rgba >> 8) & 0xFF)
                self.alpha = Double(rgba & 0xFF) / 255.0
            default:
                return nil
        }
    }

    // MARK: - HSB Init

    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let h = min(1, max(0, hue))
        let s = min(1, max(0, saturation))
        let v = min(1, max(0, brightness))

        let i = Int(h * 6) % 6
        let f = h * 6 - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)

        let (rd, gd, bd): (Double, Double, Double)
        switch i {
            case 0: (rd, gd, bd) = (v, t, p)
            case 1: (rd, gd, bd) = (q, v, p)
            case 2: (rd, gd, bd) = (p, v, t)
            case 3: (rd, gd, bd) = (p, q, v)
            case 4: (rd, gd, bd) = (t, p, v)
            default: (rd, gd, bd) = (v, p, q)
        }

        self.r = UInt8(min(255, max(0, rd * 255)).rounded())
        self.g = UInt8(min(255, max(0, gd * 255)).rounded())
        self.b = UInt8(min(255, max(0, bd * 255)).rounded())
        self.alpha = min(1, max(0, alpha))
    }

    // MARK: - OKLCH Init

    public init(lightness: Double, chroma: Double, hue: Double, alpha: Double = 1) {
        let l = min(1, max(0, lightness))
        let c = max(0, chroma)
        let hRad = hue * .pi / 180.0

        let a = c * cos(hRad)
        let b = c * sin(hRad)

        let lPrime = l + 0.3963377774 * a + 0.2158037573 * b
        let mPrime = l - 0.1055613458 * a - 0.0638541728 * b
        let sPrime = l - 0.0894841775 * a - 1.2914855480 * b

        let lc = lPrime * lPrime * lPrime
        let mc = mPrime * mPrime * mPrime
        let sc = sPrime * sPrime * sPrime

        let rLinear = +4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let gLinear = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bLinear = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        self.r = UInt8(min(255, max(0, Self.linearToSRGB(rLinear) * 255)).rounded())
        self.g = UInt8(min(255, max(0, Self.linearToSRGB(gLinear) * 255)).rounded())
        self.b = UInt8(min(255, max(0, Self.linearToSRGB(bLinear) * 255)).rounded())
        self.alpha = min(1, max(0, alpha))
    }

    private static func linearToSRGB(_ value: Double) -> Double {
        let clamped = min(1, max(0, value))
        if clamped <= 0.0031308 {
            return 12.92 * clamped
        }
        return 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
    }
}

// MARK: - Codable

extension ColorRGB: Codable {
    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
            let hex = try? container.decode(String.self),
            let color = ColorRGB(hex: hex)
        {
            self = color
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.r = try container.decode(UInt8.self, forKey: .r)
        self.g = try container.decode(UInt8.self, forKey: .g)
        self.b = try container.decode(UInt8.self, forKey: .b)
        self.alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if alpha < 1 {
            let alphaInt = UInt8(min(255, max(0, alpha * 255)).rounded())
            try container.encode(String(format: "#%02x%02x%02x%02x", r, g, b, alphaInt))
        } else {
            try container.encode(String(format: "#%02x%02x%02x", r, g, b))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case r
        case g
        case b
        case alpha
    }
}

// MARK: - Equatable (alpha-aware)

extension ColorRGB {
    public static func == (lhs: ColorRGB, rhs: ColorRGB) -> Bool {
        lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.alpha == rhs.alpha
    }
}

extension ColorRGB {
    /// The RGB value of a true-colour cell colour; nil for the default or an indexed colour.
    public init?(_ color: Color) {
        guard case .rgb(let r, let g, let b) = color else { return nil }
        self.init(r: r, g: g, b: b)
    }
}
