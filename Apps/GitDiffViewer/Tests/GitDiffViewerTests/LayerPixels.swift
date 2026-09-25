import AppKit
import Metal
import QuartzCore
import Testing

/// Core Animation's renderer, the texture it draws into and the queue it encodes on, one for each size of window.
///
/// Making a renderer loads Core Animation's Metal shaders, which took tens of milliseconds on the main actor for each
/// frame read, so the suite makes one per size and reuses it, as the window server composites every frame with one.
@MainActor
private final class Compositor {
    let renderer: CARenderer
    let texture: any MTLTexture
    let queue: any MTLCommandQueue

    private static var bySize: [SIMD2<Int>: Compositor] = [:]

    /// The compositor for a window of `width` by `height` points, made the first time one is asked for.
    static func shared(width: Int, height: Int) throws -> Compositor {
        let size = SIMD2(width, height)
        if let compositor = bySize[size] { return compositor }
        let compositor = try Compositor(width: width, height: height)
        bySize[size] = compositor
        return compositor
    }

    private init(width: Int, height: Int) throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        queue = try #require(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        texture = try #require(device.makeTexture(descriptor: descriptor))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        renderer = CARenderer(
            mtlTexture: texture, options: [kCARendererColorSpace: colorSpace, kCARendererMetalCommandQueue: queue])
    }
}

extension LayerPixels {
    /// `root`'s pixels as its layers hold them: Core Animation composites the layer tree into a texture, and no view
    /// is asked to draw.
    @MainActor
    static func composite(_ root: CALayer) throws -> LayerPixels {
        let width = Int(root.bounds.width)
        let height = Int(root.bounds.height)
        let compositor = try Compositor.shared(width: width, height: height)
        let renderer = compositor.renderer
        let region = MTLRegionMake2D(0, 0, width, height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // The texture starts each frame empty, so that nothing an earlier pane left in it shows through.
        compositor.texture.replace(region: region, mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        renderer.layer = root
        renderer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        // The renderer draws what was committed.
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // The renderer encodes on the compositor's queue, so a buffer committed after its work completes after it.
        let fence = try #require(compositor.queue.makeCommandBuffer())
        fence.commit()
        fence.waitUntilCompleted()
        renderer.layer = nil
        compositor.texture.getBytes(&bytes, bytesPerRow: width * 4, from: region, mipmapLevel: 0)
        return LayerPixels(width: width, height: height, bytes: bytes)
    }
}

/// BGRA pixels at one per point, the bottom row first, as window coordinates count.
struct LayerPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// How many pixels inside `rect`, in window coordinates, differ from `other`'s by more than rounding does.
    ///
    /// A row whose bytes match in both holds no such pixel, so only the rows that differ are read pixel by pixel. This
    /// is a main-actor suite: reading every pixel of the window, as most counts here do, held the main actor for
    /// seconds, and every main-actor test in the run waited behind it.
    func differing(from other: LayerPixels, in rect: NSRect) -> Int {
        let rows = Self.clamped(rect.minY, rect.maxY, to: height)
        let columns = Self.clamped(rect.minX, rect.maxX, to: width)
        let rowBytes = columns.count * 4
        return bytes.withUnsafeBytes { mine in
            other.bytes.withUnsafeBytes { theirs in
                guard rowBytes > 0, let mineStart = mine.baseAddress, let theirsStart = theirs.baseAddress else {
                    return 0
                }
                var count = 0
                for y in rows {
                    let start = (y * width + columns.lowerBound) * 4
                    guard memcmp(mineStart + start, theirsStart + start, rowBytes) != 0 else { continue }
                    for index in stride(from: start, to: start + rowBytes, by: 4)
                    where (0 ..< 3).contains(where: { abs(Int(mine[index + $0]) - Int(theirs[index + $0])) > 8 }) {
                        count += 1
                    }
                }
                return count
            }
        }
    }

    /// The whole pixels from `lower` to `upper` that lie within `0 ..< limit`; empty for a span outside it.
    private static func clamped(_ lower: CGFloat, _ upper: CGFloat, to limit: Int) -> Range<Int> {
        let start = min(max(Int(lower.rounded(.down)), 0), limit)
        return start ..< min(max(Int(upper.rounded(.up)), start), limit)
    }
}
