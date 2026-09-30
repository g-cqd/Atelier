import Foundation
package import SwiftUI

/// The text engine a window's panes use (text-renderer.md §4.3). TextKit 2 is the only one until the CoreText
/// renderer lands (M1); the Develop menu offers the one choice meanwhile.
package enum TextBackendKind: String, CaseIterable, Identifiable, Sendable {
    case textKit2

    package var id: String { rawValue }

    /// The name the Develop menu shows.
    package var title: String {
        switch self {
            case .textKit2: "TextKit 2"
        }
    }

    /// The environment variable that picks a new window's backend, for a developer.
    package static let environmentKey = "GDV_TEXT_BACKEND"
    /// The hidden defaults key that picks a new window's backend, when the environment does not.
    package static let defaultsKey = "developer.textBackend"
    /// The hidden defaults key that shows the Develop menu in a release build.
    package static let showsDevelopMenuKey = "developer.showsDevelopMenu"

    /// The backend a new window starts with: the one `environment` names under ``environmentKey``, else the one
    /// `stored` names, by default the standard defaults' value under ``defaultsKey``, else TextKit 2. A name no
    /// backend has is passed over.
    package static func developerDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        stored: String? = UserDefaults.standard.string(forKey: TextBackendKind.defaultsKey)
    ) -> TextBackendKind {
        environment[environmentKey].flatMap(Self.init(rawValue:))
            ?? stored.flatMap(Self.init(rawValue:))
            ?? .textKit2
    }
}

extension EnvironmentValues {
    /// The text engine the panes of this window use (text-renderer.md §4.3).
    @Entry package var diffTextBackend: TextBackendKind = .textKit2
}
