public import AtelierDiagnostics

/// Whether sourcekit-lsp discovery runs at all, given its persisted ``ToolLocation``; a nil location, never
/// configured, counts as enabled.
public func sourceKitLSPDiscoveryEnabled(_ location: ToolLocation?) -> Bool {
    location?.isEnabled ?? true
}
