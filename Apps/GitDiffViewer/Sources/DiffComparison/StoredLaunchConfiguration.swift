import Foundation

/// A ``LaunchConfiguration`` as ``RecentComparisons`` stores it: each URL as its absolute string, the form Foundation's
/// JSON coders give a `URL`, so the stored list keeps the shape it has always had.
enum StoredLaunchConfiguration: Codable {
    case patch(String)
    case files(left: String, right: String)
    case repository(String, leftRef: String, rightRef: String?)

    /// A stored URL that `URL(string:)` does not parse.
    struct InvalidURL: Error {
        let string: String
    }

    init(_ configuration: LaunchConfiguration) {
        switch configuration {
            case .patch(let url):
                self = .patch(url.absoluteString)
            case .files(let left, let right):
                self = .files(left: left.absoluteString, right: right.absoluteString)
            case .repository(let url, let leftRef, let rightRef):
                self = .repository(url.absoluteString, leftRef: leftRef, rightRef: rightRef)
        }
    }

    /// The configuration this entry stores.
    /// - Throws: ``InvalidURL`` when a stored URL does not parse.
    func configuration() throws(InvalidURL) -> LaunchConfiguration {
        switch self {
            case .patch(let url):
                .patch(try Self.url(url))
            case .files(let left, let right):
                .files(left: try Self.url(left), right: try Self.url(right))
            case .repository(let url, let leftRef, let rightRef):
                .repository(try Self.url(url), leftRef: leftRef, rightRef: rightRef)
        }
    }

    private static func url(_ string: String) throws(InvalidURL) -> URL {
        guard let url = URL(string: string) else { throw InvalidURL(string: string) }
        return url
    }
}
