public import AtelierDiagnostics

/// Whether sourcekit-lsp discovery should run at all, given its persisted ``ToolLocation`` (nil when it was never
/// configured, which defaults to enabled like every other tool). Both call sites that discover sourcekit-lsp --
/// per-workspace sessions and the SDK documentation tier -- share this so disabling it gates discovery itself
/// instead of merely clearing its custom path, which workspace and toolchain discovery would still happily search
/// past.
public func sourceKitLSPDiscoveryEnabled(_ location: ToolLocation?) -> Bool {
    location?.isEnabled ?? true
}
