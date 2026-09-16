// Git and process tracing now live in AtelierCore; this module keeps the app's names for them.
@_exported public import AtelierGit
@_exported public import AtelierProcess

/// A file inside a source: the same record git's tree listing produces, which the other sources fill in themselves.
public typealias SourceEntry = GitTreeEntry
