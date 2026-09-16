/// The languages the lexers and the syntax tier of the diff know; anything else is plain text.
public enum Language: Sendable, Equatable, CaseIterable {
    case swift
    case objectiveC
    case kotlin
    case java
    case javascript
    case typescript
    case c
    case cpp
    case python
    case shell
    case fish
    case html
    case css
    case json
    case yaml
    case toml
    case plain

    public init(fileExtension: String) {
        self = Self.byExtension[fileExtension.lowercased()] ?? .plain
    }

    /// File extensions mapped to their language; anything else is plain text.
    public static let byExtension: [String: Language] = [
        "swift": .swift,
        "m": .objectiveC, "mm": .objectiveC, "h": .objectiveC,
        "kt": .kotlin, "kts": .kotlin,
        "java": .java,
        "js": .javascript, "mjs": .javascript, "cjs": .javascript, "jsx": .javascript,
        "ts": .typescript, "tsx": .typescript, "mts": .typescript, "cts": .typescript,
        "c": .c,
        "cpp": .cpp, "cc": .cpp, "cxx": .cpp, "hpp": .cpp, "hh": .cpp, "hxx": .cpp, "ipp": .cpp,
        "py": .python, "pyi": .python,
        "sh": .shell, "bash": .shell, "zsh": .shell,
        "fish": .fish,
        "html": .html, "htm": .html, "xml": .html, "svg": .html, "plist": .html, "storyboard": .html, "xib": .html,
        "css": .css, "scss": .css, "less": .css,
        "json": .json, "jsonc": .json,
        "yaml": .yaml, "yml": .yaml,
        "toml": .toml,
        "txt": .plain, "md": .plain, "markdown": .plain, "strings": .plain, "gitignore": .plain, "env": .plain
    ]
}
