package import AtelierDiagnostics
import Foundation

/// Human-readable name for where a tool was found, matching ``ToolOrigin``'s cases.
private func originName(_ origin: ToolOrigin) -> String {
    switch origin {
        case .environment: "environment override"
        case .custom: "pinned path"
        case .bundled: "bundled"
        case .toolchain: "toolchain"
        case .wellKnown: "well-known directory"
        case .shellPath: "shell PATH"
    }
}

/// Describes a tool's discovered status for display: a nil `status` means not probed yet, and `pinned` makes an
/// unusable custom path read as broken rather than missing.
package func toolStatusDescription(_ status: ToolStatus?, pinned: Bool) -> String {
    guard let status else { return "Checking…" }
    guard let url = status.url, let origin = status.origin else {
        return pinned ? "Pinned path is missing or not executable" : "Not found"
    }
    let name = url.lastPathComponent
    let location = url.deletingLastPathComponent().path
    let place = "\(location) (\(originName(origin)))"
    if let version = status.version {
        return "\(name) \(version) — \(place)"
    }
    return "\(name) — \(place)"
}
