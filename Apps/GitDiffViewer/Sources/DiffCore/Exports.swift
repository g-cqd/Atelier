// The app's diff, lexing and language vocabulary now live in AtelierCore; this module keeps `import DiffCore`
// meaning the same thing for every app target until they import the core products directly.
@_exported import AtelierDiff
@_exported import AtelierLexers
@_exported import AtelierSwiftSyntax
@_exported import AtelierSyntaxModel
