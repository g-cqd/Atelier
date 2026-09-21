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

/// Describes a tool's discovered status for display, independent of any view: fed a nil status when the tool has
/// not been probed yet, and `pinned` when a custom path was configured, so a pinned-but-unusable path reads as
/// broken rather than simply missing. Lives here, rather than in the app target's Settings view, so the Settings
/// window's Tools tab and its tests can both reach it without an app-target test dependency.
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
