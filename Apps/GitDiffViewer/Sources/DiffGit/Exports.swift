// Git and process tracing now live in AtelierCore; this module keeps the app's names for them.
@_exported import AtelierGit
@_exported import AtelierProcess

/// A file inside a source: the same record git's tree listing produces, which the other sources fill in themselves.
package typealias SourceEntry = GitTreeEntry
