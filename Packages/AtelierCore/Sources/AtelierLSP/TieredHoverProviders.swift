public import AtelierSyntaxModel

/// Composes several ``HoverProvider`` tiers into one: tries each in order, returning the first non-`nil`
/// result. A tier that throws ``CancellationError`` aborts the whole composite immediately (the caller itself
/// was cancelled, so no later tier should run either); any other error from a tier is treated the same as a
/// `nil` result -- move on to the next tier -- since a ``HoverProvider`` is documented to prefer `nil` over
/// throwing when it simply has nothing to show, and a misbehaving tier shouldn't take the whole composite down.
public struct TieredHoverProviders: HoverProvider {
    private let providers: [any HoverProvider]

    public init(_ providers: [any HoverProvider]) {
        self.providers = providers
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        for provider in providers {
            try Task.checkCancellation()
            do {
                if let result = try await provider.hover(query) {
                    return result
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
        return nil
    }
}
