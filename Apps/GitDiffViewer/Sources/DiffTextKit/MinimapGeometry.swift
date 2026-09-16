import AppKit
import DiffCore
import DiffRendering
import Foundation
import SwiftUI

/// Maps rows of a document onto the height of a minimap strip.
///
/// Rows never take more than `maximumPitch` points, so a short file occupies the top of the strip instead of being
/// stretched. Once rows are denser than a point, they are aggregated into one-point buckets, and past
/// `schematicDensity` rows per point only the change map is drawn.
package struct MinimapGeometry: Equatable {
    package enum Detail: Equatable {
        case full
        case aggregated
        case schematic
    }

    package static let maximumPitch = 3.0
    package static let schematicDensity = 4.0

    package let rowCount: Int
    package let height: Double

    /// Points per row.
    package var pitch: Double {
        guard rowCount > 0, height > 0 else { return 0 }
        return min(height / Double(rowCount), Self.maximumPitch)
    }

    package var detail: Detail {
        guard rowCount > 0, height > 0 else { return .full }
        let density = Double(rowCount) / height
        if density <= 1 { return .full }
        return density <= Self.schematicDensity ? .aggregated : .schematic
    }

    /// Height the rows actually cover.
    package var usedHeight: Double { Double(rowCount) * pitch }

    /// One-point buckets covering the used height.
    package var bucketCount: Int { Int(usedHeight.rounded(.up)) }

    package func y(ofRow row: Int) -> Double { Double(row) * pitch }

    package func bucket(ofRow row: Int) -> Int { min(Int(y(ofRow: row)), max(bucketCount - 1, 0)) }

    package func row(atY y: Double) -> Int {
        guard rowCount > 0, pitch > 0 else { return 0 }
        return min(max(Int(y / pitch), 0), rowCount - 1)
    }
}
