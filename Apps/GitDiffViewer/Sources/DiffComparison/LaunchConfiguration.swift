package import Foundation

/// What a window was asked to compare: from the command line, the welcome window or the recents.
package enum LaunchConfiguration: Hashable, Codable, Sendable {
    case patch(URL)
    case files(left: URL, right: URL)
    case repository(URL, leftRef: String, rightRef: String?)
}
