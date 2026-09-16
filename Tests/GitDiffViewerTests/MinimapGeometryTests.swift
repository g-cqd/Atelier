@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
import Testing

struct MinimapGeometryTests {
    @Test
    func `short files use the maximum pitch and keep full detail`() {
        let sut = MinimapGeometry(rowCount: 20, height: 400)
        #expect(sut.pitch == 3)
        #expect(sut.detail == .full)
        #expect(sut.y(ofRow: 10) == 30)
        #expect(sut.row(atY: 31) == 10)
        #expect(sut.usedHeight == 60)
    }

    @Test
    func `files taller than the strip shrink the pitch below a point and aggregate rows`() {
        let sut = MinimapGeometry(rowCount: 1000, height: 400)
        #expect(sut.pitch == 0.4)
        #expect(sut.detail == .aggregated)
        #expect(sut.bucket(ofRow: 999) == 399)
        #expect(sut.bucketCount == 400)
    }

    @Test
    func `very dense files fall back to a schematic map`() {
        let sut = MinimapGeometry(rowCount: 5000, height: 400)
        #expect(sut.detail == .schematic)
        #expect(sut.row(atY: 400) == 4999)
        #expect(sut.row(atY: -5) == 0)
    }

    @Test
    func `an empty file has no pitch and no buckets`() {
        let sut = MinimapGeometry(rowCount: 0, height: 400)
        #expect(sut.pitch == 0)
        #expect(sut.bucketCount == 0)
    }
}
