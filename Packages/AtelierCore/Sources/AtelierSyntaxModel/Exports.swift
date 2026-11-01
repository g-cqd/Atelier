// The language, role, modifier and line token vocabulary is AemiLexers' (aemi ADR 0022), re-exported type by type so
// that importing the model does not also bring in the scanners and their `Token`, `LexState` and `SyntaxHighlighter`.

@_exported public import struct AemiLexers.HighlightModifierSet
@_exported public import enum AemiLexers.HighlightRole
@_exported public import enum AemiLexers.Language
@_exported public import struct AemiLexers.LineToken
@_exported public import enum AemiLexers.UTF16Offsets
