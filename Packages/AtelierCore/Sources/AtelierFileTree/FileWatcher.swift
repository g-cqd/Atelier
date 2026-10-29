public import AemiIO

/// The file watcher, promoted to AemiIO with its tests (aemi ADR 0016): one FSEvents stream over watched directories
/// and the parents of watched files, files followed by path through atomic saves, history replayed across restarts.
/// The names stay the ones Atelier's apps already use.
public typealias FileWatcher = AemiIO.FileWatcher

/// What a watcher offers, whichever backend: AemiIO's `FileWatcher` (FSEvents) or `KqueueWatcher` (kqueue).
public typealias FileWatching = AemiIO.FileWatching
