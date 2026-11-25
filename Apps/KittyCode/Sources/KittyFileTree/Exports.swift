/// The file tree model lives in the core; this target keeps the FSEvents watcher, which needs an app-tier task
/// provider, and re-exports the model so the app's imports stay put.
@_exported public import AtelierFileTree
