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
    case rust
    case go
    case ruby
    case lua
    case plain

    public init(fileExtension: String) {
        self = Self.byExtension[fileExtension.lowercased()] ?? .plain
    }

    /// The language a grammar manifest or a language server names, such as `swift`, `cpp` or `bash`; nil when the
    /// name is not one the lexers know. Case-insensitive, and common aliases (`c++`, `sh`, `objc`, `js`) resolve.
    public init?(name: String) {
        guard let language = Self.byName[name.lowercased()] else { return nil }
        self = language
    }

    /// The canonical lowercase name, the one ``init(name:)`` accepts without an alias.
    public var name: String {
        switch self {
            case .swift: "swift"
            case .objectiveC: "objective-c"
            case .kotlin: "kotlin"
            case .java: "java"
            case .javascript: "javascript"
            case .typescript: "typescript"
            case .c: "c"
            case .cpp: "cpp"
            case .python: "python"
            case .shell: "shell"
            case .fish: "fish"
            case .html: "html"
            case .css: "css"
            case .json: "json"
            case .yaml: "yaml"
            case .toml: "toml"
            case .rust: "rust"
            case .go: "go"
            case .ruby: "ruby"
            case .lua: "lua"
            case .plain: "plain"
        }
    }

    private static let byName: [String: Language] = {
        var names = Dictionary(uniqueKeysWithValues: Language.allCases.map { ($0.name, $0) })
        names["objc"] = .objectiveC
        names["objective-c"] = .objectiveC
        names["objectivec"] = .objectiveC
        names["js"] = .javascript
        names["ts"] = .typescript
        names["c++"] = .cpp
        names["py"] = .python
        names["bash"] = .shell
        names["sh"] = .shell
        names["zsh"] = .shell
        names["yml"] = .yaml
        names["rs"] = .rust
        names["golang"] = .go
        names["rb"] = .ruby
        names["text"] = .plain
        names["plaintext"] = .plain
        return names
    }()

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
        "rs": .rust,
        "go": .go,
        "rb": .ruby, "rake": .ruby, "gemspec": .ruby,
        "lua": .lua,
        "txt": .plain, "md": .plain, "markdown": .plain, "strings": .plain, "gitignore": .plain, "env": .plain
    ]
}
