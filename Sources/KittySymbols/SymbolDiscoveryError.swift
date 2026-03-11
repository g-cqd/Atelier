import Foundation

enum SymbolDiscoveryError: Error, CustomStringConvertible, Sendable {
    case missingSimulatorRuntime
    case invalidPropertyList(String)

    var description: String {
        switch self {
        case .missingSimulatorRuntime:
            return "An iOS simulator runtime with SFSymbols.framework could not be located."
        case let .invalidPropertyList(path):
            return "Invalid property list at \(path)."
        }
    }
}
