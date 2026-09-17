import Foundation
import Testing

@testable import KittyCodecs

@Suite
struct GraphicsEncoderTests {
    @Test
    func `Small payload fits in single chunk`() {
        let cmd = GraphicsCommand(
            action: .transmitAndDisplay,
            format: .png,
            transmission: .direct,
            payload: [0x89, 0x50, 0x4E, 0x47]  // PNG magic bytes
        )
        let bytes = GraphicsEncoder.encode(cmd)
        // Should contain APC start (ESC _), 'G', control params, ';', base64 payload, ST (ESC \)
        #expect(bytes.first == 0x1b)
        #expect(bytes[1] == 0x5f)  // _ (APC)
        #expect(bytes[2] == 0x47)  // G
        // Should end with ESC \ (ST)
        #expect(bytes[bytes.count - 2] == 0x1b)
        #expect(bytes[bytes.count - 1] == 0x5c)
        // Should NOT contain m=1 (no continuation)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(!asString.contains("m=1"))
    }

    @Test
    func `Control part includes action format transmission`() {
        let cmd = GraphicsCommand(
            action: .query,
            format: .rgb,
            transmission: .file,
            payload: [1, 2, 3]
        )
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(asString.contains("a=q"))
        #expect(asString.contains("f=24"))
        #expect(asString.contains("t=f"))
    }

    @Test
    func `Control includes id width height when nonzero`() {
        let cmd = GraphicsCommand(
            action: .transmitAndDisplay,
            format: .rgba,
            transmission: .direct,
            id: 42,
            width: 100,
            height: 50,
            payload: [0xFF]
        )
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(asString.contains("i=42"))
        #expect(asString.contains("s=100"))
        #expect(asString.contains("v=50"))
    }

    @Test
    func `Control omits id width height when zero`() {
        let cmd = GraphicsCommand(payload: [0xFF])
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        #expect(!asString.contains("i="))
        #expect(!asString.contains("s="))
        #expect(!asString.contains("v="))
    }

    @Test
    func `Large payload produces multiple chunks with m=1 continuation`() {
        // Create a payload that will exceed 4096 bytes when base64-encoded
        // Base64 expands 3 bytes to 4 chars, so 3073 bytes → 4100 chars (> 4096)
        let cmd = GraphicsCommand(payload: Array(repeating: 0xAB, count: 3073))
        let bytes = GraphicsEncoder.encode(cmd)
        let asString = String(bytes: bytes, encoding: .ascii) ?? ""
        // Should contain m=1 for continuation
        #expect(asString.contains("m=1"))
        // Should contain multiple APC sequences (multiple ESC _ G ... ESC \)
        let apcCount = asString.components(separatedBy: "\u{1B}_G").count - 1
        #expect(apcCount >= 2)
    }

    @Test
    func `Empty payload produces valid single chunk`() {
        let cmd = GraphicsCommand(payload: [])
        let bytes = GraphicsEncoder.encode(cmd)
        #expect(bytes.first == 0x1b)
        #expect(bytes.last == 0x5c)
    }
}

/// Placement and deletion controls, the commands the pixel chrome layer relies on.
struct GraphicsPlacementEncodingTests {
    private func control(_ command: GraphicsCommand) -> String {
        let text = String(decoding: GraphicsEncoder.encode(command), as: UTF8.self)
        return String(text.dropFirst(3).prefix { $0 != ";" })
    }

    @Test
    func `a placement names the image and placement, its z-index, offsets and cursor policy`() {
        let placement = GraphicsCommand.Placement(id: 7, zIndex: -1, xOffset: 3, yOffset: 0, keepsCursor: true)
        #expect(
            control(GraphicsCommand(action: .placement, id: 42, placement: placement, isQuiet: true))
                == "a=p,i=42,p=7,z=-1,X=3,C=1,q=2")
    }

    @Test
    func `deletions free data only when asked`() {
        #expect(control(GraphicsCommand(action: .delete, deletion: .allPlacements(freeingData: false))) == "a=d,d=a")
        #expect(
            control(GraphicsCommand(action: .delete, deletion: .allPlacements(freeingData: true), isQuiet: true))
                == "a=d,d=A,q=2")
        #expect(control(GraphicsCommand(action: .delete, deletion: .image(id: 9, freeingData: true))) == "a=d,d=I,i=9")
    }

    @Test
    func `a transmit keeps its format and dimensions`() {
        let command = GraphicsCommand(
            action: .transmit, format: .rgba, transmission: .direct, id: 5, width: 1, height: 2, payload: [1, 2, 3, 4],
            isQuiet: true)
        #expect(control(command) == "a=t,f=32,t=d,i=5,s=1,v=2,q=2")
    }
}
