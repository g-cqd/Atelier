// The app's diff, lexing and language vocabulary now live in AtelierCore; this module keeps `import DiffCore`
// meaning the same thing for every app target until they import the core products directly. The swift-syntax
// provider is deliberately not re-exported: only the renderer links it.
@_exported public import AtelierDiff
@_exported public import AtelierLexers
@_exported public import AtelierSyntaxModel
