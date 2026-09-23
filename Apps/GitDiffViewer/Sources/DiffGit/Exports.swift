// Re-exports AtelierCore's git, source loading and process tracing under the app's own module name.
@_exported public import AtelierGit
@_exported public import AtelierProcess
@_exported public import AtelierSources

/// A file inside a source: the same record git's tree listing produces, which the other sources fill in themselves.
public typealias SourceEntry = GitTreeEntry
