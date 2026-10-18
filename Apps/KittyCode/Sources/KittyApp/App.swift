public import KittyWidgets
import TerminalKitCodecs
import TerminalKitIO
import TerminalKitInput
import TerminalKitRender

// MARK: - App Protocol

public protocol App: Sendable {
    associatedtype RootBody: View
    @ViewBuilder var body: RootBody { get }
    init()
}

// MARK: - App Error

public enum AppError: Error, Sendable, Equatable {
    case terminalSetupFailed(String)
    case unexpectedShutdown
}
