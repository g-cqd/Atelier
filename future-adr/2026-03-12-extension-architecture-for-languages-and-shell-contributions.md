# Future ADR: Extension Architecture for Languages and Shell Contributions

Status: Proposed
Date: 2026-03-12

## Goal

Enable a coherent extension architecture for:

- adding new languages
- registering grammar and syntax-highlighting resources
- exposing richer language compatibility tiers over time
- creating new sidebar panes reachable from the activity bar
- contributing status bar components

The main objective is to move KittyCode from hardcoded built-ins to a typed contribution model that can express built-in and third-party features the same way.

## Scope

This ADR covers:

- language detection and registration
- syntax artifact discovery and loading
- grammar and highlight resource extension
- activity bar and sidebar pane contributions
- status bar component contributions
- contribution manifests, registries, and config integration

This ADR does not include:

- networked extension marketplaces
- untrusted arbitrary code execution
- implementation work

## Current Codebase Findings

### Language compatibility is currently bundle-centric

`Sources/KittySyntax/BundledLanguageManifest.swift` loads `Sources/KittySyntax/Grammars/languages.json` from the bundled resources and resolves language support by bundled manifest entries only.

`Sources/KittySyntax/LanguageHighlighter.swift` directly depends on that bundled manifest for:

- file extension to language detection
- language resource discovery
- artifact loading eligibility

This means the runtime language system is currently built around one specific resource bundle shape.

### Language support is compile-time and resource-copy based

`Package.swift` copies `Sources/KittySyntax/Grammars` into `KittySyntax` resources.

The bundled manifest currently lists 19 languages in `Sources/KittySyntax/Grammars/languages.json`.

This is straightforward, but it means adding a language today requires editing the main package resources rather than registering a new language contribution.

### `GrammarRegistry` exists, but runtime highlighting does not use it

`Sources/KittySyntax/GrammarRegistry.swift` already provides:

- `register(_:)`
- `loadManifest(from:)`
- `entry(forExtension:)`
- grammar loading and parse-table compilation caches

`rg` shows this registry is exercised by tests, but not by `LanguageHighlighter` in runtime code.

This is the clearest already-developed but unwired extension seam on the language side.

### Grammar-backed highlighting has a hard compatibility boundary

`LanguageHighlighter` loads grammar-backed artifacts only if:

- a bundled `grammar.json` exists
- a bundled `highlights.scm` exists
- `grammar.externals.isEmpty`

That last condition appears in `Sources/KittySyntax/LanguageHighlighter.swift`.

This means languages that require external scanners are currently excluded from the grammar-backed pipeline.

### Language detection is narrow

Current detection is based on filename extension only.

There is no support for:

- filename aliases like `Makefile`
- shebang detection
- modelines
- user language overrides
- workspace-local language registration

`Tests/KittyCodeTests/DetectLanguageTests.swift` and `Tests/KittySyntaxTests/HighlighterTests.swift` confirm the existing extension-based behavior.

### Sidebar support is structurally narrow and shell-hardcoded

`Sources/KittyCode/EditorStateCore.swift` models only:

- `.explorer`
- `.openDocuments`

`Sources/KittyCode/Render.swift` switches on those two panels only.

`Sources/KittyCode/MouseInput.swift` switches activity bar clicks to those two panels only.

So the shell has a sidebar concept, but not a pane contribution model.

### The activity bar widget is more generic than the shell integration

`Sources/KittyWidgets/ActivityBar.swift` already renders generic items identified by `id`.

`Sources/KittyCode/RenderActivityBar.swift` converts config ids into icons using a hardcoded switch:

- `"explorer"`
- `"openDocuments"`

Unknown ids currently render as `"?"`.

That means the widget is contribution-friendly, but the shell is not.

### Status bar items are enum-locked

`Sources/KittyCode/Config.swift` defines `StatusBarConfig.Item` as a closed enum.

`Sources/KittyCode/StatusBarContent.swift` resolves those items through one switch.

This means new status bar items require editing app code and config decoding rather than registering a component.

### The status bar widget is presentation-light

`Sources/KittyWidgets/StatusBar.swift` renders:

- `left`
- `center`
- `right`

as strings with one shared style.

So even if the shell supported contributed status items, the current widget would still be too narrow for richer component behavior.

### Symbol roles are also hardcoded to built-ins

`Sources/KittySymbols/TerminalSymbolTheme.swift` has dedicated roles for:

- `.explorer`
- `.openDocuments`

That is fine for built-ins, but it does not scale to contributed panes without either:

- a dynamic glyph registry
- or pane-specific icon text supplied directly by the contribution

### Generic widgets already exist and are reusable

The codebase already has useful generic pieces:

- `ActivityBar`
- `ListView`
- `TreeView`
- `StatusBar`

The missing piece is not basic rendering primitives. The missing piece is a contribution host above them.

## Gaps and Missing Features

### 1. No unified contribution registry

There is no central host that can register and resolve:

- languages
- pane contributions
- status bar contributions

### 2. No runtime distinction between built-ins and extensions

Built-in features are implemented directly in shell enums and switches. There is no "built-ins are first-party extensions" model.

### 3. No typed language provider abstraction

The app has no first-class protocol boundary for:

- language detection
- lexical highlighters
- grammar-backed highlighters
- future semantic or language-service providers

### 4. No resource discovery outside the main bundle

There is no architecture today for:

- compile-time extension targets registering resources
- workspace-local language packs
- user-local extension bundles

### 5. No pane lifecycle or focus contract

Even if a new sidebar pane existed, there is no contribution API for:

- pane state
- pane rendering
- pane commands
- pane input handling
- pane focus behavior

### 6. No status bar component contract

There is no way for a feature to contribute:

- a measured component
- a priority
- a compact or expanded representation
- a style or icon

### 7. No config namespace for extensions

Current config supports built-ins only.

There is no stable shape for:

- extension enablement
- extension-specific settings
- contributed activity bar order
- contributed status bar item placement

### 8. No API versioning or capability negotiation

There is no way to express:

- host API version
- required capabilities
- optional features
- compatibility boundaries

That would become necessary as soon as nontrivial extensions are introduced.

## Already Developed But Unwired or Underused

- `GrammarRegistry` exists but is not part of runtime highlighting or detection.
- `ActivityBar` already accepts generic string ids, but the shell only recognizes two.
- `ListView` and `TreeView` are reusable pane widgets, but pane rendering is still shell-owned.
- `StatusBar` already exists as a widget, but shell item resolution is a closed enum switch.

## Decision

### 1. Introduce a first-class contribution model

KittyCode should define a typed contribution system for:

- languages
- sidebar panes
- status bar items

Built-ins should be re-expressed through this same system.

### 2. Support compile-time contributions first

The first milestone should prioritize in-repo and package-level contributions, not dynamic arbitrary code loading.

This gives:

- better safety
- better testability
- lower integration risk

### 3. Define tiered language compatibility

Language support should not be all-or-nothing.

Suggested tiers:

- `detectionOnly`
- `lexicalHighlighting`
- `grammarHighlighting`
- `parserEnhanced`
- `semanticServices` in future

This allows the system to accept useful contributions even when full parser-backed highlighting is unavailable.

### 4. Separate contribution registration from shell rendering

The shell should resolve pane and status item contributions from registries, not from hardcoded switches.

### 5. Keep configuration string-addressable

Config should reference contributed items by stable ids, not by closed enums.

That is necessary for third-party contributions and for first-party features that should not require config schema churn every time.

## Proposed Architecture

### New target

Add a new target:

- `Sources/KittyExtensions`

Suggested dependencies:

- `KittySyntax`
- `KittyWidgets`
- `KittySymbols`
- `KittySync`

Keep language engines in `KittySyntax` and UI widgets in `KittyWidgets`. Use `KittyExtensions` as the contribution and host layer.

### Core types

Suggested shared types:

- `ContributionID`
- `ContributionKind`
- `ContributionManifest`
- `ContributionRegistry`
- `ContributionCapability`
- `ContributionHostContext`
- `ContributionAPILevel`

### Language contribution model

Suggested types:

- `LanguageContribution`
- `LanguageDetectionRule`
- `LanguageSupportTier`
- `LanguageHighlightProvider`
- `LanguageArtifactProvider`
- `LanguageFeatureProvider`

Suggested detection sources:

- extension list
- exact filename match
- shebang match
- explicit user override

Suggested provider lanes:

- `RegexOrLexicalHighlighter`
- `GrammarQueryHighlighter`
- `ParserEnhancedProvider`

This keeps the system open to multiple compatibility paths instead of forcing every language through the same artifact path.

### Resource model

A language contribution should be able to declare resources such as:

- `grammar.json`
- `highlights.scm`
- optional comment pattern metadata
- optional icon or display metadata

The host should support these sources in phases:

1. built-in bundle contributions
2. compile-time package contributions
3. optional external extension directories later

### Sidebar pane contribution model

Suggested types:

- `SidebarPaneContribution`
- `SidebarPaneDescriptor`
- `SidebarPaneState`
- `SidebarPaneController`
- `SidebarPaneViewFactory`

Each pane contribution should provide:

- stable id
- activity bar title or label
- icon or glyph text
- optional symbol role or direct glyph
- default order
- focus contract
- render or view factory
- optional command handlers

This lets panes own their content without forcing shell-wide switches.

### Status bar contribution model

Suggested types:

- `StatusBarItemContribution`
- `StatusBarSegmentModel`
- `StatusBarMeasurement`
- `StatusBarRenderPolicy`

Each item should declare:

- stable id
- preferred placement
- compact and expanded text or segment model
- measurement rules
- visibility predicate
- optional styles or severity roles

This replaces the current closed enum with an open registry while still allowing built-ins to remain first-class.

### Built-in migration path

The existing built-ins should become contributions:

- language bundles become built-in `LanguageContribution`s
- `explorer` and `openDocuments` become built-in `SidebarPaneContribution`s
- existing status fields become built-in `StatusBarItemContribution`s

That is the cleanest way to validate the architecture without creating a separate parallel system.

### Config design

Config should move toward string-addressable contribution ids.

Examples:

- `activityBar.items = ["explorer", "search", "git", "outline"]`
- `statusBar.leftItems = ["path", "status", "diagnostics"]`
- `statusBar.rightItems = ["visibility", "language", "git", "position"]`

Add extension config sections such as:

- `extensions.enabled`
- `extensions.paths`
- `extensions.allowedKinds`
- `extensions.settings.<contribution-id>`
- `languages.overrides`

### Compatibility and versioning

Every contribution manifest should declare:

- contribution id
- API level
- contribution kinds
- required capabilities
- optional capabilities

This allows the host to reject unsupported extensions predictably rather than failing inside runtime code.

## Recommended Phasing

### Phase 1: Introduce registries and re-express built-ins

- Add contribution registries.
- Re-express built-in languages, panes, and status items through them.
- Keep behavior unchanged for users.

### Phase 2: Wire runtime highlighting through registered language providers

- Move detection off direct bundled-manifest calls.
- Route artifact loading through registered contributions.
- Make `GrammarRegistry` part of runtime rather than test-only support.

### Phase 3: Open compile-time extensibility

- Allow new package targets to register language and pane contributions.
- Add config-driven inclusion and ordering.

### Phase 4: Optional external extension bundles

- Add trusted extension directories.
- Add manifest validation and compatibility checks.
- Add resource discovery outside the built-in bundle.

## Testing Recommendations

- Add registry tests for contribution lookup and override ordering.
- Add migration tests proving built-ins still work when resolved through registries.
- Add language tests for filename, extension, and shebang detection.
- Add pane tests for activity bar id resolution and pane rendering selection.
- Add status bar tests for open item resolution and placement.
- Add compatibility tests for unsupported API levels and missing capabilities.

## Recommendation Summary

KittyCode already has many of the leaf primitives needed for extensibility, but the shell still owns the integration points directly. The right next step is not to bolt ad hoc hooks onto the existing switches. The right next step is to introduce a contribution registry and make built-ins use it first.

The strongest near-term wins are:

- wiring `GrammarRegistry` into runtime language support
- replacing closed sidebar and status bar switches with contribution lookups
- making config refer to stable contribution ids instead of closed enums

## Deep Technical Analysis

### Codebase Impact Assessment

#### Full Extension API Surface Design

KittyCode's extension system must expose every editor feature as a programmable surface. The current codebase has multiple hardcoded seams that each need to become an extension point. The full API surface covers these categories:

**Commands.** Commands are the atomic unit of editor functionality. Every action a user can trigger — opening a file, toggling a sidebar, formatting a selection, running a terminal command — is a command. Commands have a unique string identifier (`kittycode.editor.selectAll`, `myExtension.runLinter`), a human-readable title, an optional keybinding, and an execution handler. The command system is the foundation that keybindings, menus, the command palette, and inter-extension communication all build on. Today, actions are scattered across `KeyInput.swift`, `MouseInput.swift`, `ContextMenuAction` (11 hardcoded cases), and various direct method calls on `EditorState`. All of these must converge into command registrations.

**Menus and context menus.** `ContextMenuAction` is a closed enum with 11 cases (`.cut`, `.copy`, `.paste`, `.selectAll`, `.undo`, `.redo`, `.toggleLineNumbers`, `.toggleMinimap`, `.toggleWordWrap`, `.toggleWhitespace`, `.commandPalette`). Extensions must be able to contribute menu items to context menus, the command palette, and any future menu bar. Each menu contribution references a command ID, declares a group for ordering, and optionally specifies a `when` condition (e.g., `"editorHasSelection"`, `"resourceLangId == swift"`).

**Status bar items.** `StatusBarConfig.Item` is a closed enum with 9 cases. Extensions contribute status bar items with alignment (left/right), priority (sort order), dynamic text resolved from editor state, optional click commands, and optional tooltip text. The current `StatusBarContent.statusBarText(for:)` switch becomes a registry lookup.

**Sidebar panes.** `SidebarPanel` is a closed enum with 2 cases (`.explorer`, `.openDocuments`). Extensions contribute new sidebar panes with an icon for the activity bar, a title, a tree or list data model, rendering logic, and input handling. The search pane (from the search ADR) would be the first extension-contributed pane. Future panes could include: git changes, symbols outline, extension marketplace, debug console.

**Keybindings.** The current `keybindings` config section maps key combos to a fixed set of actions. Extensions contribute default keybinding mappings for their commands. User keybindings override extension defaults. Keybinding contributions declare a command ID, a default key, and an optional `when` context (so a keybinding can be active only when a specific sidebar is focused, or only in a specific mode).

**Themes.** The current config supports 45+ theme colors across editor, statusBar, tabRibbon, activityBar, syntax, git, and whitespace sections. Extensions contribute complete color themes as named theme objects. A theme contribution declares all color values; the theme switcher lists built-in and extension-contributed themes. Theme extensions can also contribute syntax token color overrides and semantic highlighting rules.

**Language services.** Beyond grammar registration, extensions provide language intelligence: auto-completion, hover information, go-to-definition, find-references, signature help, symbol search, rename support, and code actions. These map to LSP capabilities. An extension can either implement these directly (for simple languages) or delegate to an external LSP server by providing a server configuration (command, args, initialization options).

**Diagnostics providers.** Extensions contribute diagnostics (errors, warnings, info, hints) associated with document URIs and ranges. Diagnostics appear as editor decorations (underlines, gutter markers), in the status bar (error/warning counts), and in a future diagnostics pane. The `DiagnosticProvider` protocol pushes diagnostics asynchronously as documents change.

**File decorations.** The existing `FileStatusProvider` and `GitLineDecorationProvider` protocols are already extension-shaped. Extensions contribute file decorations (icons, badges, color tints on the file explorer), line decorations (git blame, coverage markers, lint annotations), and range decorations (inline error highlights, bracket pair colorization).

**Editor decorations (virtual text and gutter markers).** Extensions can inject virtual text (text rendered in the editor that is not part of the document content) — useful for inline type hints, parameter names, ghost text completions, and code lens annotations. Gutter markers allow extensions to place icons or colored indicators in the gutter column next to specific lines.

**Document transformers and formatters.** Extensions contribute formatters that can format an entire document or a selection on demand or on save. Document transformers are a more general concept: an extension can register a transformer that processes document content on specific triggers (e.g., auto-import organization on save, trailing whitespace removal, encoding normalization).

**Linters.** A linter is a specific kind of diagnostic provider that runs on document save or document change and produces diagnostics. The distinction from a raw diagnostic provider is that linters are explicitly user-configurable (enable/disable per language, configure rules via settings) and have a well-defined execution trigger.

**Terminal integration.** The existing `TerminalConnection` protocol is an extension point. Extensions contribute terminal profiles (named configurations for shell type, environment, working directory) and terminal link providers (patterns that make terminal output clickable — e.g., file paths, URLs, error locations).

**Workspace events.** Extensions subscribe to workspace lifecycle events: file open, file close, file save (before and after), file rename, file delete, file create, buffer content change, active editor change, configuration change, focus gained, focus lost, sidebar visibility change. The `InputEvent` enum (`.key`, `.mouse`, `.resize`, `.paste`, `.focusIn`, `.focusOut`, `.refresh`) needs a parallel workspace event system at a higher semantic level.

#### Extension Host Architecture

**In-process Swift extensions (compile-time).** The initial extension model is compile-time: extensions are Swift packages that depend on `KittyExtensionAPI` and register their contributions at application startup. This is analogous to how IntelliJ plugins are loaded — they run in the same process, have full type safety, and incur zero serialization overhead. The tradeoff is that extensions must be compiled with the editor and cannot be installed at runtime without recompilation. This is acceptable for Phase 1-3.

**Extension manifest format.** Every extension — built-in or third-party — declares its identity and contributions in a typed manifest. For compile-time extensions, the manifest is a Swift struct conforming to `ExtensionManifest`. For future external bundles, it is a JSON file (`extension.json`) in the bundle root. The manifest contains:

```swift
struct ExtensionManifest: Codable, Sendable {
    let id: String                          // "com.kittycode.git"
    let displayName: String                 // "Git Integration"
    let version: String                     // "1.0.0"
    let apiLevel: Int                       // minimum KittyCode API version
    let activationEvents: [ActivationEvent] // when to activate
    let contributions: ContributionDeclaration
}

struct ContributionDeclaration: Codable, Sendable {
    var commands: [CommandDeclaration]?
    var languages: [LanguageDeclaration]?
    var themes: [ThemeDeclaration]?
    var menus: [MenuDeclaration]?
    var keybindings: [KeybindingDeclaration]?
    var sidebarViews: [SidebarViewDeclaration]?
    var statusBarItems: [StatusBarItemDeclaration]?
    var diagnosticProviders: [DiagnosticProviderDeclaration]?
    var formatters: [FormatterDeclaration]?
    var configuration: ConfigurationSchema?
}
```

**Capability declaration.** Each extension declares its required capabilities up front. The host validates that the running KittyCode version supports the requested API level and capabilities before activating the extension. This prevents runtime crashes from API mismatches and enables clear error messages ("Extension X requires KittyCode API level 3, but this version provides API level 2").

**Lifecycle management.** Extensions follow a strict lifecycle:

1. **Discovery** — the host scans registered extension packages (compile-time) or extension directories (runtime).
2. **Manifest validation** — the host parses the manifest, checks API level compatibility, and validates contribution declarations against known schemas.
3. **Registration** — the host registers the extension's declared contributions (commands, languages, themes, etc.) in the `ContributionRegistry`. Contributions are registered but not yet active.
4. **Activation** — when an activation event fires (e.g., a file with a matching language is opened), the host calls the extension's `activate()` method. The extension receives an `ExtensionContext` providing access to the extension API.
5. **Active operation** — the extension responds to events, provides diagnostics, resolves commands, etc.
6. **Deactivation** — when the extension is no longer needed (e.g., the user disables it, or the editor shuts down), the host calls `deactivate()`. The extension must release resources, cancel async tasks, and remove any transient state.
7. **Unregistration** — the host removes the extension's contributions from the registry.

**Activation events.** Lazy activation is critical for startup performance. Extensions declare the conditions under which they should be activated:

```swift
enum ActivationEvent: Codable, Sendable {
    case onLanguage(String)                // "swift", "python"
    case onCommand(String)                 // "myExtension.doThing"
    case workspaceContains(String)         // glob: "**/*.rs"
    case onFileSystem(String)              // scheme: "git", "ftp"
    case onStartup                         // activate immediately
    case onConfigurationChange(String)     // "extensions.myExt.settings"
}
```

An extension with `.onLanguage("swift")` is not activated until a Swift file is opened. An extension with `.onCommand("myExtension.doThing")` is activated only when that command is first invoked. The `onStartup` event should be used sparingly — it is reserved for extensions that provide globally needed services (e.g., the built-in theme provider).

**Deactivation and cleanup.** The `deactivate()` method is `async` to allow extensions to flush state, close network connections, or terminate child processes. The host enforces a deactivation timeout (e.g., 5 seconds) — if the extension does not return within the timeout, the host forcibly deallocates its resources.

**Sandboxing considerations.** In-process Swift extensions have full access to the process memory space. This is acceptable for trusted, compile-time extensions (similar to IntelliJ plugins). For Phase 5 (external untrusted extensions), WASM sandboxing would provide memory isolation, deterministic resource limits, and capability-based access control. The extension API should be designed from the start so that it can be projected into a WASM guest environment via host function imports, even though WASM execution is not implemented initially.

#### Extension API Protocol Design

The extension system is built on a set of provider protocols. An extension implements the protocols matching its capabilities. This is a protocol-based contribution model, not a callback registration soup. Each protocol has a focused responsibility.

**Core `Extension` protocol:**

```swift
protocol Extension: Sendable {
    var manifest: ExtensionManifest { get }
    func activate(context: ExtensionContext) async throws
    func deactivate() async
}
```

`ExtensionContext` is the extension's gateway to the editor API. It provides methods to register providers, subscribe to events, access configuration, read workspace state, and interact with the UI.

```swift
protocol ExtensionContext: Sendable {
    var extensionId: String { get }
    var workspacePath: String? { get }
    var storagePath: String { get }  // per-extension persistent storage

    // Registration
    func registerCommand(_ command: CommandRegistration) async
    func registerProvider<P: Provider>(_ provider: P) async
    func registerEventListener(_ listener: WorkspaceEventListener) async

    // State access
    func getConfiguration<T: Decodable>(section: String) async -> T?
    func getActiveDocument() async -> DocumentSnapshot?
    func getOpenDocuments() async -> [DocumentSnapshot]

    // UI interaction
    func showInformationMessage(_ message: String) async
    func showWarningMessage(_ message: String) async
    func showInputPrompt(_ prompt: EditorPrompt) async -> String?
    func setStatusBarMessage(_ text: String, timeout: Duration?) async
}
```

**`CommandProvider`** — contributes executable commands:

```swift
protocol CommandProvider: Sendable {
    var commands: [CommandDescriptor] { get }
    func execute(command: String, args: [String: Any]) async throws -> CommandResult
}

struct CommandDescriptor: Sendable {
    let id: String              // "myExtension.formatDocument"
    let title: String           // "Format Document"
    let category: String?       // "Formatting"
    let enablement: String?     // condition expression: "editorHasSelection"
}
```

**`LanguageProvider`** — contributes language intelligence:

```swift
protocol LanguageProvider: Sendable {
    var languageId: String { get }
    var capabilities: LanguageCapabilities { get }

    func provideCompletions(document: DocumentSnapshot, position: Position) async -> [CompletionItem]
    func provideHover(document: DocumentSnapshot, position: Position) async -> HoverInfo?
    func provideDefinition(document: DocumentSnapshot, position: Position) async -> [Location]
    func provideReferences(document: DocumentSnapshot, position: Position) async -> [Location]
    func provideSymbols(document: DocumentSnapshot) async -> [DocumentSymbol]
    func provideSignatureHelp(document: DocumentSnapshot, position: Position) async -> SignatureHelp?
    func provideCodeActions(document: DocumentSnapshot, range: Range) async -> [CodeAction]
    func provideRename(document: DocumentSnapshot, position: Position, newName: String) async -> WorkspaceEdit?
}
```

The `capabilities` field declares which methods the provider actually implements. Methods for unsupported capabilities return empty results by default (via protocol extension defaults). This avoids forcing every language provider to stub out every method.

**`DiagnosticProvider`** — pushes diagnostics:

```swift
protocol DiagnosticProvider: Sendable {
    var id: String { get }
    var supportedLanguages: [String] { get }

    func provideDiagnostics(document: DocumentSnapshot) async -> [Diagnostic]
    func onDocumentChanged(document: DocumentSnapshot) async
    func onDocumentSaved(document: DocumentSnapshot) async
}

struct Diagnostic: Sendable {
    let range: TextRange
    let message: String
    let severity: DiagnosticSeverity  // .error, .warning, .info, .hint
    let code: String?
    let source: String                // "swiftlint", "eslint"
    let relatedInformation: [DiagnosticRelatedInfo]?
    let fixes: [CodeAction]?          // quick-fix actions
}
```

**`ThemeProvider`** — contributes color themes:

```swift
protocol ThemeProvider: Sendable {
    var themes: [ThemeDescriptor] { get }
    func resolveTheme(id: String) async -> ResolvedTheme?
}

struct ThemeDescriptor: Sendable {
    let id: String              // "monokai-pro"
    let displayName: String     // "Monokai Pro"
    let kind: ThemeKind         // .dark, .light, .highContrast
}

struct ResolvedTheme: Sendable {
    let editor: EditorColors
    let statusBar: StatusBarColors
    let tabRibbon: TabRibbonColors
    let activityBar: ActivityBarColors
    let sidebar: SidebarColors
    let syntax: SyntaxColors
    let git: GitColors
    let diagnostic: DiagnosticColors
    let terminal: TerminalColors
}
```

This maps directly to KittyCode's existing 45+ theme color configuration sections. Built-in themes become `ThemeProvider` implementations that return the current default color values.

**`SidebarProvider`** — contributes sidebar panes:

```swift
protocol SidebarProvider: Sendable {
    var panes: [SidebarPaneDescriptor] { get }
    func createPaneController(id: String, context: ExtensionContext) async -> SidebarPaneController?
}

protocol SidebarPaneController: Sendable {
    var id: String { get }
    var title: String { get }
    var icon: String { get }
    func render(to buffer: inout ScreenBuffer, in rect: Rect, context: RenderContext)
    func handleKey(_ key: KeyEvent) -> EventResult
    func handleClick(row: Int, col: Int) -> EventResult
    func focusTargets() -> [FocusTarget]
}
```

**`StatusBarProvider`** — contributes status bar items:

```swift
protocol StatusBarProvider: Sendable {
    var items: [StatusBarItemDescriptor] { get }
    func resolve(itemId: String, state: StatusBarContext) async -> StatusBarSegment?
}

struct StatusBarItemDescriptor: Sendable {
    let id: String
    let alignment: StatusBarAlignment   // .left, .right
    let priority: Int                   // sort order within alignment group
    let command: String?                // command to execute on click
}
```

**`KeybindingProvider`** — contributes default keybindings:

```swift
protocol KeybindingProvider: Sendable {
    var keybindings: [KeybindingDescriptor] { get }
}

struct KeybindingDescriptor: Sendable {
    let key: String             // "ctrl+shift+p"
    let command: String         // "kittycode.commandPalette"
    let when: String?           // context condition
    let args: [String: String]? // arguments passed to the command
}
```

**`MenuProvider`** — contributes menu items:

```swift
protocol MenuProvider: Sendable {
    var menuContributions: [MenuContribution] { get }
}

struct MenuContribution: Sendable {
    let location: MenuLocation          // .contextMenu, .commandPalette, .editorTitle
    let group: String                   // "navigation", "modification", "1_edit"
    let command: String                 // command ID
    let when: String?                   // condition expression
}
```

**`DecorationProvider`** — contributes visual decorations:

```swift
protocol DecorationProvider: Sendable {
    var id: String { get }

    // File tree decorations (icons, badges, colors in explorer)
    func provideFileDecorations(uri: String) async -> [FileDecoration]

    // Inline editor decorations (virtual text, highlights)
    func provideEditorDecorations(document: DocumentSnapshot) async -> [EditorDecoration]

    // Gutter decorations (markers next to line numbers)
    func provideGutterDecorations(document: DocumentSnapshot) async -> [GutterDecoration]
}

struct EditorDecoration: Sendable {
    let range: TextRange
    let kind: EditorDecorationKind      // .highlight, .virtualText, .border
    let style: DecorationStyle          // colors, font style
    let hoverMessage: String?
    let virtualText: String?            // text to render inline (for .virtualText kind)
    let virtualTextPosition: VirtualTextPosition  // .after, .before, .overlay
}
```

This subsumes the existing `GitLineDecorationProvider` and `FileStatusProvider` protocols — they become specific `DecorationProvider` implementations.

**`FormatterProvider`** — contributes document formatters:

```swift
protocol FormatterProvider: Sendable {
    var id: String { get }
    var supportedLanguages: [String] { get }
    var formattingTriggers: [FormattingTrigger] { get }  // .onSave, .onPaste, .onType, .manual

    func formatDocument(document: DocumentSnapshot) async throws -> [TextEdit]
    func formatRange(document: DocumentSnapshot, range: TextRange) async throws -> [TextEdit]
    func formatOnType(document: DocumentSnapshot, position: Position, character: String) async throws -> [TextEdit]
}
```

**`WorkspaceEventListener`** — subscribes to workspace events:

```swift
protocol WorkspaceEventListener: Sendable {
    func onFileOpened(document: DocumentSnapshot) async
    func onFileClosed(uri: String) async
    func onFileSaved(document: DocumentSnapshot) async
    func onFileWillSave(document: DocumentSnapshot) async -> [TextEdit]?  // pre-save transforms
    func onFileCreated(uri: String) async
    func onFileDeleted(uri: String) async
    func onFileRenamed(oldUri: String, newUri: String) async
    func onActiveEditorChanged(document: DocumentSnapshot?) async
    func onConfigurationChanged(section: String) async
    func onBufferContentChanged(document: DocumentSnapshot, changes: [ContentChange]) async
}
```

All methods have default empty implementations via protocol extension, so listeners only implement the events they care about.

**`DocumentTransformer`** — transforms document content on triggers:

```swift
protocol DocumentTransformer: Sendable {
    var id: String { get }
    var supportedLanguages: [String] { get }
    var trigger: TransformTrigger { get }  // .onSave, .onPaste, .onOpen

    func transform(document: DocumentSnapshot) async throws -> [TextEdit]
}
```

Document transformers are distinct from formatters in that they perform semantic transformations (e.g., organizing imports, removing unused variables, normalizing line endings) rather than purely stylistic formatting.

#### Command System as Extension Foundation

The command system is the single most important architectural component. Every user-facing action in KittyCode — built-in or extension-contributed — must be a command. This is the principle that makes VS Code's extension model so powerful: commands are the universal glue between keybindings, menus, the command palette, toolbar buttons, and programmatic invocation.

**Current state.** Today, KittyCode has no command system. Actions are directly wired:
- Key presses in `KeyInput.swift` call methods on `EditorState` directly.
- Mouse clicks in `MouseInput.swift` dispatch through switch statements.
- Context menu actions are a closed enum (`ContextMenuAction`) with a switch in the handler.
- `EditorPrompt.Kind` (7 cases) represents a fixed set of prompt types.
- There is no command palette, no way to invoke an action by name, and no way for extensions to add new actions.

**Target architecture.** A `CommandRegistry` holds all registered commands. Commands are identified by string IDs following a reverse-domain convention: `kittycode.editor.copy`, `kittycode.editor.paste`, `kittycode.file.save`, `git.stageFile`, `myLinter.runCheck`.

```swift
actor CommandRegistry {
    func register(_ command: CommandRegistration) async
    func unregister(id: String) async
    func execute(id: String, args: CommandArgs?) async throws -> CommandResult
    func commands() async -> [CommandDescriptor]
    func commands(matching filter: String) async -> [CommandDescriptor]
}

struct CommandRegistration: Sendable {
    let descriptor: CommandDescriptor
    let handler: @Sendable (CommandArgs?) async throws -> CommandResult
}

enum CommandResult: Sendable {
    case void
    case value(Any & Sendable)
    case cancelled
}
```

**Migration path.** Every existing action in `KeyInput.swift`, `MouseInput.swift`, and `ContextMenuAction` is refactored into a command registration. For example:

- `ContextMenuAction.copy` becomes command `kittycode.editor.copy`
- `ContextMenuAction.toggleLineNumbers` becomes command `kittycode.editor.toggleLineNumbers`
- The save prompt flow becomes command `kittycode.file.save`
- Mode toggling becomes commands `kittycode.editor.enterInsertMode`, `kittycode.editor.enterNormalMode`

The `ContextMenuAction` enum is replaced by `[MenuContribution]` entries referencing command IDs. The `EditorPrompt.Kind` enum is replaced by a prompt service that commands invoke through `ExtensionContext`.

**Keybinding resolution.** The keybinding system resolves key events to command IDs. When a key is pressed:

1. The keybinding resolver looks up the key combo in the active keybinding map.
2. It evaluates the `when` condition against the current context (active mode, focused element, language, etc.).
3. If a match is found, it calls `CommandRegistry.execute(id:args:)`.
4. If no match is found, the key event falls through to the default input handler (text insertion in insert mode, etc.).

This replaces the current direct dispatch in `KeyInput.swift` with an indirection through the command registry. The performance cost is negligible (a dictionary lookup per keystroke), and the flexibility gain is enormous.

**Command palette.** The command palette is a UI component that lists all registered commands (filtered by their `enablement` condition), supports fuzzy search by title, and executes the selected command. It is itself triggered by a command (`kittycode.commandPalette.show`), which is bound to a keybinding (e.g., `Ctrl+Shift+P`). Every command automatically appears in the command palette — extensions get discoverability for free.

#### Extension Configuration and Settings

Extensions contribute settings schemas that integrate with KittyCode's existing JSON configuration system (`~/.kittycode.json`). Extension settings live under the `extensions` namespace in the config hierarchy.

**Settings schema declaration.** Each extension declares its configurable settings in the manifest:

```swift
struct ConfigurationSchema: Codable, Sendable {
    let properties: [String: ConfigurationProperty]
}

struct ConfigurationProperty: Codable, Sendable {
    let type: ConfigValueType           // .string, .number, .boolean, .array, .enum
    let defaultValue: AnyCodable
    let description: String
    let enumValues: [String]?           // for .enum type
    let minimum: Double?                // for .number type
    let maximum: Double?                // for .number type
}
```

**Config namespace.** Extension settings appear in the config file under `extensions.<extensionId>.settings`:

```json
{
    "editor": { ... },
    "theme": { ... },
    "extensions": {
        "com.kittycode.git": {
            "settings": {
                "enableGutterDecorations": true,
                "fetchOnStartup": false,
                "maxBlameAge": 365
            }
        },
        "com.example.swiftlint": {
            "settings": {
                "enabled": true,
                "configPath": ".swiftlint.yml",
                "lintOnSave": true,
                "lintOnType": false
            }
        }
    }
}
```

**Typed settings access.** Extensions read their settings through a typed API on `ExtensionContext`:

```swift
extension ExtensionContext {
    func getSetting<T: Decodable>(_ key: String) async -> T?
    func getSetting<T: Decodable>(_ key: String, default: T) async -> T
    func onSettingChanged(_ key: String, handler: @Sendable (Any) async -> Void) async
}
```

The host validates setting values against the declared schema on config load. Invalid values are reported as warnings and replaced with defaults. Setting changes trigger `.onConfigurationChange` events, which extensions can listen for to reconfigure themselves at runtime.

**Settings cascade.** Settings resolve in priority order: workspace-level config (`.kittycode/config.json` in the project root) > user-level config (`~/.kittycode.json`) > extension-declared defaults. This matches the existing config hierarchy and extends it seamlessly to extension-contributed settings.

#### GrammarRegistry Integration

`GrammarRegistry` (GrammarRegistry.swift:6-129) is a fully functional `actor` with `register()`, `loadManifest()`, `entry(forExtension:)`, `grammar()`, and `compiledResult()` methods with built-in memory and disk caching. It is exercised by tests but completely bypassed at runtime.

The runtime path instead goes through:
1. `BundledLanguageManifest.entry(forFilename:)` — extension-only detection using a cached JSON manifest
2. `SyntaxArtifactsCache.artifacts(for:)` — loads grammar.json + highlights.scm from the bundled resources
3. `LanguageHighlighter.Session.init()` — creates a highlighting session from cached artifacts

To wire `GrammarRegistry` into the runtime:

1. **Replace `BundledLanguageManifest` calls with `GrammarRegistry` lookups**: `LanguageHighlighter` should receive a `GrammarRegistry` reference and call `entry(forExtension:)` instead of `BundledLanguageManifest.entry(forFilename:)`.
2. **Bootstrap built-in languages as registrations**: On startup, load `languages.json` and register each entry via `GrammarRegistry.register()`. This makes built-in languages indistinguishable from contributed languages at the registry level.
3. **Keep `SyntaxArtifactsCache` as an optimization layer**: The cache can sit above the registry, caching compiled artifacts by language name. The registry provides language resolution; the cache provides artifact compilation caching.
4. **The externals check** (`grammar.externals.isEmpty` at LanguageHighlighter.swift ~line 275) should move into the registry's `compiledResult()` method. Languages with externals should still register — they just receive a lower `LanguageSupportTier` (e.g., `.lexicalHighlighting` instead of `.grammarHighlighting`).

**Language detection enrichment.** The current detection at `BundledLanguageManifest.entry(forFilename:)` only checks file extension. The enriched detection stack supports: exact filename matching (`Makefile`, `Dockerfile`, `.gitignore`), shebang detection (`#!/usr/bin/env python3`), first-line pattern matching (Emacs/Vim modelines), and user overrides via `"languageOverrides"` in config. Detection priority: user override > exact filename > extension > shebang > first-line pattern > plain text default.

**Extension-contributed languages.** Language extensions register their grammars, highlight queries, and language configuration (comment tokens, bracket pairs, auto-closing pairs, indentation rules) through the `LanguageProvider` protocol. The `GrammarRegistry` becomes the single source of truth for all language resolution — built-in and contributed.

#### Contribution Manifest Format

The contribution manifest is the declarative contract between an extension and the host. It enables the host to register contributions before activating the extension, validate compatibility, and provide discoverability (e.g., listing available themes or commands without loading extension code).

For compile-time Swift extensions, the manifest is a static property:

```swift
extension MyExtension: Extension {
    var manifest: ExtensionManifest {
        ExtensionManifest(
            id: "com.example.swiftSupport",
            displayName: "Swift Language Support",
            version: "1.2.0",
            apiLevel: 1,
            activationEvents: [.onLanguage("swift")],
            contributions: ContributionDeclaration(
                commands: [
                    CommandDeclaration(id: "swift.buildProject", title: "Build Swift Project", category: "Swift"),
                    CommandDeclaration(id: "swift.runTests", title: "Run Swift Tests", category: "Swift")
                ],
                languages: [
                    LanguageDeclaration(
                        id: "swift",
                        extensions: [".swift"],
                        filenames: ["Package.swift"],
                        configuration: LanguageConfiguration(
                            lineComment: "//",
                            blockComment: ("/*", "*/"),
                            brackets: [("{", "}"), ("[", "]"), ("(", ")")],
                            autoClosingPairs: [("{", "}"), ("[", "]"), ("(", ")"), ("\"", "\"")]
                        )
                    )
                ],
                keybindings: [
                    KeybindingDeclaration(key: "ctrl+shift+b", command: "swift.buildProject", when: "resourceLangId == swift")
                ],
                statusBarItems: [
                    StatusBarItemDeclaration(id: "swift.buildStatus", alignment: .left, priority: 50, command: "swift.buildProject")
                ],
                configuration: ConfigurationSchema(properties: [
                    "buildOnSave": ConfigurationProperty(type: .boolean, defaultValue: .bool(false), description: "Automatically build on save"),
                    "toolchainPath": ConfigurationProperty(type: .string, defaultValue: .string(""), description: "Path to Swift toolchain")
                ])
            )
        )
    }
}
```

For future external extension bundles, the same structure is expressed as JSON in `extension.json`:

```json
{
    "id": "com.example.swiftSupport",
    "displayName": "Swift Language Support",
    "version": "1.2.0",
    "apiLevel": 1,
    "activationEvents": ["onLanguage:swift"],
    "contributions": {
        "commands": [
            { "id": "swift.buildProject", "title": "Build Swift Project", "category": "Swift" },
            { "id": "swift.runTests", "title": "Run Swift Tests", "category": "Swift" }
        ],
        "languages": [
            {
                "id": "swift",
                "extensions": [".swift"],
                "filenames": ["Package.swift"],
                "configuration": {
                    "lineComment": "//",
                    "blockComment": ["/*", "*/"],
                    "brackets": [["{", "}"], ["[", "]"], ["(", ")"]],
                    "autoClosingPairs": [["{", "}"], ["[", "]"], ["(", ")"], ["\"", "\""]]
                }
            }
        ],
        "keybindings": [
            { "key": "ctrl+shift+b", "command": "swift.buildProject", "when": "resourceLangId == swift" }
        ],
        "statusBarItems": [
            { "id": "swift.buildStatus", "alignment": "left", "priority": 50, "command": "swift.buildProject" }
        ],
        "configuration": {
            "properties": {
                "buildOnSave": { "type": "boolean", "default": false, "description": "Automatically build on save" },
                "toolchainPath": { "type": "string", "default": "", "description": "Path to Swift toolchain" }
            }
        }
    }
}
```

The host parses the manifest, validates all referenced command IDs are declared by the same extension (or are well-known built-in commands), checks the API level, and registers contributions into the `ContributionRegistry`.

### State of the Art: Editor Extension Architectures

#### VS Code Extension Model

VS Code has the most comprehensive editor extension system in production. Its architecture decisions are deeply informative for KittyCode.

**Extension Host process isolation.** Extensions run in a separate Node.js process called the Extension Host. The renderer (Electron main process) and the Extension Host communicate via JSON-RPC over IPC. This isolation prevents extensions from blocking the UI thread, provides crash isolation (a failing extension does not crash the editor), and enables the remote development model (extensions can run on a remote machine while the UI runs locally). The cost is serialization overhead on every API call crossing the process boundary.

**JSON manifest (`package.json`).** Every VS Code extension declares its contributions in a `contributes` section of `package.json`. This is parsed before the extension's JavaScript is loaded, enabling the editor to register commands, menus, keybindings, themes, languages, and views without activating the extension. This manifest-driven approach is key to VS Code's startup performance with thousands of installed extensions.

**Activation events.** Extensions specify when they should be activated: `onLanguage:python`, `onCommand:extension.run`, `workspaceContains:**/Cargo.toml`, `onFileSystem:sftp`, `onView:myTreeView`, `*` (always). The host evaluates these events and lazily activates extensions only when needed. Most extensions are never activated in a given session.

**Extension API surface.** The `vscode` namespace exposes a massive API:
- `vscode.workspace` — file system access, configuration, text documents, file watching, workspace folders
- `vscode.window` — editors, terminals, tree views, webview panels, status bar items, output channels, input boxes, quick picks
- `vscode.commands` — command registration and execution
- `vscode.languages` — language features (completion, hover, diagnostics, formatting, code actions, rename, etc.)
- `vscode.debug` — debug adapter protocol integration
- `vscode.extensions` — access to other installed extensions
- `vscode.env` — environment information (shell, app name, remote name)
- `vscode.tasks` — task system for build/run configurations
- `vscode.tests` — test runner integration

**Contributes system.** The declarative `contributes` fields include: `commands`, `menus`, `keybindings`, `languages`, `grammars`, `themes`, `iconThemes`, `productIconThemes`, `snippets`, `views`, `viewsContainers`, `viewsWelcome`, `configuration`, `configurationDefaults`, `taskDefinitions`, `debuggers`, `breakpoints`, `customEditors`, `notebookRenderer`, `terminal`, `typescriptServerPlugins`, `walkthroughs`, and more. Each has a JSON schema that VS Code validates at install time.

**Key lesson for KittyCode.** The manifest-driven contributes system and the separation between declarative registration and imperative activation are the most valuable patterns. Process isolation is less relevant for a terminal editor (no Electron renderer to protect), but the API surface design is an excellent blueprint.

#### Neovim Lua Plugin Ecosystem

Neovim's extension model is powerful but convention-driven rather than manifest-driven.

**`vim.api` and `vim.fn`.** The Lua API provides direct access to Neovim's internal API (`vim.api.nvim_buf_set_lines()`, `vim.api.nvim_create_autocmd()`). There is no abstraction layer — plugins call the same API that Neovim's core uses. This gives maximum flexibility but no safety guarantees.

**`vim.lsp`.** Neovim has a built-in LSP client. Plugins configure it per-language by specifying the server command, initialization options, and capability handlers. The `lspconfig` plugin provides pre-configured setups for hundreds of language servers. Extensions do not implement language features directly — they delegate to LSP servers.

**`vim.diagnostic`.** The diagnostic system is decoupled from LSP. Any plugin can push diagnostics via `vim.diagnostic.set(namespace, bufnr, diagnostics)`. Diagnostics are rendered as virtual text, signs, and underlines. This is a clean, provider-agnostic diagnostic model.

**`vim.treesitter`.** Neovim exposes Tree-sitter as a first-class Lua API. Plugins can query syntax trees (`vim.treesitter.query.parse()`), navigate nodes, and build features on top of structural code understanding. Tree-sitter grammars are installed as shared libraries (`.so` files) via `:TSInstall`.

**Autocommands and user commands.** Plugins hook into editor events via `vim.api.nvim_create_autocmd()` (file open, save, buffer enter, etc.) and register custom commands via `vim.api.nvim_create_user_command()`. There is no manifest — everything is imperative.

**Key lesson for KittyCode.** The separation of diagnostics from LSP is a good pattern — diagnostics should be a generic system that any provider (LSP, linter, custom logic) can feed into. The imperative, convention-driven model is less suitable for KittyCode, which benefits from typed, manifest-driven contributions for discoverability and validation.

#### Zed WASM Extensions

Zed's extension model is the newest and most security-conscious.

**Sandboxed WASM execution.** Extensions compile to WebAssembly and run in a Wasmtime runtime with capability-based access control. Extensions cannot access the file system, network, or process APIs unless explicitly granted by the host. This provides strong isolation guarantees, making it safe to install untrusted extensions.

**`extension.toml` manifest.** Extensions declare their contributions in a TOML manifest: languages (with Tree-sitter grammar WASM binaries and highlight queries), themes (as JSON/TOML color definitions), and slash commands (for the AI assistant). The contribution surface is intentionally narrow.

**Language and theme contributions.** Language extensions provide Tree-sitter grammars compiled to WASM, highlight and injection queries, and LSP server configurations. Theme extensions provide color theme files. Slash command extensions provide custom commands for Zed's AI chat interface.

**No arbitrary UI.** Zed deliberately does not allow extensions to contribute arbitrary UI panels, views, or editor decorations. This keeps the UI consistent and prevents the "extension UI soup" problem that VS Code suffers from. The tradeoff is reduced flexibility.

**Key lesson for KittyCode.** WASM sandboxing is the right long-term answer for untrusted extensions, but it requires significant runtime infrastructure. Zed's narrow contribution surface is too restrictive for KittyCode's goals — KittyCode should aim for VS Code-breadth contributions with Zed-quality sandboxing as a future phase. The manifest-driven approach is consistent with the VS Code and KittyCode patterns.

#### JetBrains IntelliJ Plugin SDK

IntelliJ's extension model is the most mature and architecturally rich.

**Extension points.** IntelliJ defines hundreds of typed extension points. Each extension point is a named slot where plugins register implementations. For example: `com.intellij.completion.contributor`, `com.intellij.codeInsight.lineMarkerProvider`, `com.intellij.toolWindow`, `com.intellij.statusBarWidgetFactory`. Plugins declare their extension point implementations in `plugin.xml`.

**Service system.** Plugins register services at application, project, or module scope. Services are lazily instantiated and dependency-injected. This provides clean lifecycle management and testability.

**PSI (Program Structure Interface).** IntelliJ's language support is built on PSI, a typed AST framework. Each language plugin defines its PSI element types, parser, and lexer. Higher-level features (completion, navigation, refactoring) are expressed in terms of PSI queries. This is analogous to Tree-sitter but with a richer type system.

**Inspections and intentions.** Code analysis is expressed through inspections (diagnostic providers) and intentions (quick-fix code actions). Each is a class implementing a specific interface, registered via extension points.

**Actions.** The IntelliJ action system is equivalent to VS Code's command system. Every menu item, toolbar button, and keyboard shortcut resolves to an `AnAction` subclass. Actions declare their placement in menus, their keyboard shortcut, and their enablement condition.

**Tool windows.** Plugins contribute tool windows (equivalent to sidebar panes) that appear in the IDE's peripheral panels. Each tool window is a named registration with an icon, position preference, and a factory that creates the window content.

**Key lesson for KittyCode.** The extension point model — typed slots where plugins register implementations — is architecturally equivalent to the provider protocol model proposed for KittyCode. IntelliJ's approach validates that protocol-based contributions scale to hundreds of extension surfaces. The service system's lifecycle management (application/project scoping, lazy instantiation) is worth adopting.

#### Helix Static Model

Helix represents the opposite end of the extensibility spectrum.

**`languages.toml` configuration.** All language support is declared in a single TOML file: file types, comment tokens, indentation rules, LSP server command, formatter command, Tree-sitter grammar source, and query paths. Users customize language support by editing this file.

**No runtime extension loading.** Grammars are compiled at build time via `hx --grammar fetch && hx --grammar build`. There is no plugin system, no extension host, no activation events. Every capability is either built-in or compiled-in.

**Simplicity as a feature.** Helix's model is deterministic, fast, and requires zero extension management. The editor starts instantly, never crashes due to extensions, and behaves identically across machines with the same configuration.

**Limitations.** Users cannot add new UI panels, status bar items, commands, or editor features without modifying Helix's source code. The editor's capability set is fixed at compile time. This is acceptable for a focused modal editor but insufficient for a platform that aspires to broad extensibility.

**Key lesson for KittyCode.** Helix demonstrates that the compile-time extension model (Phase 1-2 of KittyCode's plan) is viable and high-quality. KittyCode should start with Helix-level simplicity (compile-time contributions, typed registrations) and grow toward VS Code-level flexibility incrementally. The `languages.toml` model is a good reference for KittyCode's grammar registry and language configuration format.

### Recommended Technical Approach for KittyCode

This section defines a complete extensibility platform for KittyCode. The goal is not merely to wire grammars into a registry — it is to make every feature of the editor expressible through a typed extension API, so that a third-party developer has the same power as a core contributor. Every sidebar pane, every status bar segment, every keybinding, every context menu entry, every code action, every hover tooltip, every gutter decoration — all of these must be contributable by extensions, using the same mechanisms the built-in features use.

The platform is organized into four layers:

1. **Extension Host Architecture** — how extensions are discovered, loaded, isolated, and lifecycle-managed.
2. **Provider Protocol Surface** — the 16 typed provider protocols that extensions implement to contribute features.
3. **Extension API Surface** — what the host exposes to extensions (document access, UI primitives, configuration, commands, event subscriptions).
4. **Infrastructure** — the contribution manifest, event bus, capability-based security, WASM sandboxing roadmap, hot reload, and extension discovery.

---

#### 1. Extension Host Architecture

The Extension Host is the runtime that manages extension lifecycles. It is responsible for discovery, manifest validation, capability negotiation, lazy activation, active operation, deactivation, and cleanup. The host is an actor to ensure thread-safe extension management in Swift's structured concurrency model.

##### ExtensionHost Actor

```swift
public actor ExtensionHost {
    private var registry: ExtensionRegistry = ExtensionRegistry()
    private var activatedExtensions: [String: ActiveExtension] = [:]
    private var contributionRegistry: ContributionRegistry = ContributionRegistry()
    private var commandRegistry: CommandRegistry = CommandRegistry()
    private var eventBus: EventBus = EventBus()
    private var contextFactory: ExtensionContextFactory

    public init(editorBridge: EditorBridge) {
        self.contextFactory = ExtensionContextFactory(
            commandRegistry: commandRegistry,
            contributionRegistry: contributionRegistry,
            eventBus: eventBus,
            editorBridge: editorBridge
        )
    }

    // Discovery phase: scan all extension sources
    public func discover() async throws {
        let sources: [ExtensionSource] = [
            CompileTimeExtensionSource(),                              // SPM targets in the binary
            UserDirectoryExtensionSource("~/.kittycode/extensions/"),  // user-installed bundles
            WorkspaceExtensionSource(".kittycode/extensions/"),        // workspace-local bundles
        ]
        for source in sources {
            let manifests = try await source.discover()
            for manifest in manifests {
                try await registry.register(manifest)
            }
        }
    }

    // Pre-activation: register declarative contributions from manifests
    // without loading extension code. This is what makes commands, themes,
    // and languages discoverable before the extension is activated.
    public func registerDeclarativeContributions() async {
        for manifest in await registry.allManifests() {
            await contributionRegistry.registerFromManifest(manifest)
        }
    }

    // Lazy activation: activate an extension in response to an activation event
    public func activate(extensionId: String) async throws {
        guard activatedExtensions[extensionId] == nil else { return }
        guard let entry = await registry.entry(for: extensionId) else {
            throw ExtensionHostError.unknownExtension(extensionId)
        }
        try validateCapabilities(entry.manifest)
        let context = await contextFactory.createContext(for: entry.manifest)
        let ext = try await entry.factory()
        try await ext.activate(context: context)
        activatedExtensions[extensionId] = ActiveExtension(
            extension: ext, context: context, manifest: entry.manifest
        )
    }

    // Activation event dispatch: evaluate whether any dormant extension
    // should be activated in response to an editor event
    public func handleActivationEvent(_ event: ActivationEvent) async {
        for manifest in await registry.allManifests() {
            guard activatedExtensions[manifest.id] == nil else { continue }
            if manifest.activationEvents.contains(where: { $0.matches(event) }) {
                try? await activate(extensionId: manifest.id)
            }
        }
    }

    // Graceful shutdown: deactivate all extensions in reverse activation order
    public func deactivateAll() async {
        for (id, active) in activatedExtensions.reversed() {
            await active.extension.deactivate()
            await active.context.dispose()
            activatedExtensions.removeValue(forKey: id)
        }
    }
}
```

##### Extension Lifecycle States

Each extension moves through a well-defined state machine:

```
 [Discovered] --> [ManifestRegistered] --> [Activating] --> [Active] --> [Deactivating] --> [Deactivated]
       |                  |                     |                              |
       |                  |                     v                              v
       |                  |               [ActivationFailed]             [Deactivated]
       v                  v
  [InvalidManifest]  [CapabilityDenied]
```

- **Discovered**: the host found the extension on disk or in the compile-time registry.
- **ManifestRegistered**: the manifest was parsed, validated, and its declarative contributions were registered into the `ContributionRegistry` without loading any extension code.
- **Activating**: an activation event fired, the host is calling `activate(context:)`.
- **Active**: the extension is running, its providers are registered and responding to queries.
- **ActivationFailed**: `activate(context:)` threw an error. The extension is quarantined. The host logs the error and does not retry unless the user explicitly requests it.
- **Deactivating / Deactivated**: the host called `deactivate()`, the extension cleaned up its resources.
- **InvalidManifest**: the manifest failed validation (missing required fields, unsupported API level, malformed contribution declarations).
- **CapabilityDenied**: the extension requested capabilities that the user declined to grant.

##### Activation Events

Activation events determine when extensions are lazily loaded. This is critical for startup performance — an editor with 50 installed extensions should not load all 50 at startup. Most extensions are activated only when their specific trigger fires.

```swift
public enum ActivationEvent: Codable, Sendable {
    case onLanguage(String)                    // file with this languageId is opened
    case onCommand(String)                     // a command registered by this extension is invoked
    case onFileSystem(String)                  // a file matching this glob is opened
    case workspaceContains(String)             // the workspace contains a file matching this glob
    case onView(String)                        // a view contributed by this extension becomes visible
    case onStartupFinished                     // after the editor has fully started
    case always                                // activate immediately (use sparingly)

    func matches(_ event: ActivationEvent) -> Bool { ... }
}
```

The host evaluates activation events at specific moments: `onLanguage` is checked when `BufferManager` opens a new file and the language is detected; `onCommand` is checked when `CommandRegistry.execute()` is called for a command whose descriptor was registered from a manifest but whose extension is not yet active; `workspaceContains` is checked once at workspace open; `onView` is checked when the sidebar or panel switches to a contributed view.

##### Extension Isolation Model

**Phase 1-3 (compile-time and trusted bundles):** Extensions run in-process on the same Swift actor executor as the host. Isolation is achieved through API boundaries — extensions interact with the editor exclusively through `ExtensionContext`, never through direct access to `EditorState` or other internal types. The `KittyExtensionAPI` SPM target exports only the protocol definitions and value types that form the API surface; it does not export internal editor types. Extensions depend on `KittyExtensionAPI`, not on `KittyCode` or `KittyWidgets`.

**Phase 4-5 (untrusted extensions):** Extensions run in WASM sandboxes (see WASM Sandboxing Roadmap below). The API surface is projected into the WASM guest via host function imports. Calls cross the sandbox boundary through serialized messages. The in-process and WASM paths share identical protocol definitions — the difference is the transport, not the API.

##### EditorBridge: The Host-to-Editor Interface

The `ExtensionHost` does not depend on `EditorState` directly. Instead, it communicates with the editor through an `EditorBridge` protocol. This decouples the extension system from the god object and makes the extension host testable in isolation.

```swift
public protocol EditorBridge: Sendable {
    // Document access
    func activeDocument() async -> DocumentSnapshot?
    func openDocuments() async -> [DocumentSnapshot]
    func documentContent(uri: String) async -> String?
    func openDocument(uri: String) async throws
    func closeDocument(uri: String) async throws

    // Document mutation
    func applyEdits(uri: String, edits: [TextEdit]) async throws
    func setSelection(uri: String, ranges: [TextRange]) async throws

    // Workspace
    func workspacePath() async -> String?
    func workspaceFiles(matching glob: String) async -> [String]

    // UI
    func showInformationMessage(_ message: String) async
    func showWarningMessage(_ message: String) async
    func showErrorMessage(_ message: String) async
    func showInputPrompt(_ prompt: InputPromptDescriptor) async -> String?
    func showQuickPick(_ items: [QuickPickItem]) async -> QuickPickItem?
    func setStatusBarMessage(_ text: String, timeout: Duration?) async

    // Configuration
    func getConfiguration<T: Decodable>(section: String) async -> T?
    func onConfigurationChanged(section: String) -> AsyncStream<Void>

    // Rendering
    func requestRender() async
    func requestFocusUpdate() async
}
```

In the current codebase, a concrete `EditorStateBridge` implementation wraps `EditorState` and translates calls into the existing imperative API. As the codebase evolves and `EditorState` is decomposed, the bridge implementation changes but the protocol remains stable.

---

#### 2. Provider Protocol Surface

The provider protocols are the typed contribution points where extensions plug into the editor. Each protocol represents a single capability axis. An extension may implement any combination of protocols. The host discovers which protocols an extension implements via Swift's runtime conformance checking (`extension is CommandProvider`, `extension is SidebarProvider`, etc.) during activation.

All provider protocols conform to `Sendable`. All methods are `async` to support both in-process and future WASM execution. All data types crossing the provider boundary are `Codable & Sendable` to ensure they can be serialized across a WASM sandbox boundary in the future.

##### Provider Protocol 1: CommandProvider

Commands are the universal glue. Every user-facing action — built-in or extension-contributed — is a command. Keybindings resolve to commands. Context menus reference commands. The command palette lists commands. Toolbar buttons invoke commands. Extensions invoke other extensions' commands.

```swift
public protocol CommandProvider: Sendable {
    /// Descriptors for all commands this provider contributes.
    /// Returned once during registration; the host caches them.
    var commands: [CommandDescriptor] { get }

    /// Execute a command by ID with optional arguments.
    func execute(command: String, args: CommandArgs?) async throws -> CommandResult
}

public struct CommandDescriptor: Codable, Sendable {
    public let id: String                // "myExtension.formatDocument"
    public let title: String             // "Format Document"
    public let category: String?         // "Formatting" — used for command palette grouping
    public let enablement: ContextExpression?  // when is this command available?
    public let icon: String?             // symbol name for toolbar/menu rendering
}

public struct CommandArgs: Codable, Sendable {
    public let values: [String: AnyCodable]

    public func get<T: Decodable>(_ key: String) -> T? {
        values[key]?.decode()
    }
}

public enum CommandResult: Sendable {
    case void
    case value(AnyCodable)
    case cancelled
}

/// Context expressions evaluate against the current editor state to determine
/// command availability. They are a simple predicate language.
/// Examples: "editorFocused", "resourceLangId == swift", "editorHasSelection && !editorReadonly"
public struct ContextExpression: Codable, Sendable {
    public let expression: String

    public func evaluate(against context: ContextKeySet) -> Bool { ... }
}
```

**Migration from current codebase.** Today, `EditorStateCore.swift` defines `ContextMenuAction` as a closed 13-case enum (`openSelected`, `openSelectedPinned`, `toggleSelectedDirectory`, `beginCreateFile`, `beginCreateDirectory`, `beginSavePrompt`, `beginRename`, `beginDuplicate`, `beginMove`, `beginDelete`, `saveFile`, `focusTree`, `closeTab`). Each case is handled by a `switch` in `EditorContextMenu.swift`. The 24 hardcoded keyboard shortcuts in `EventHandling.swift` directly call methods on `EditorState`. Under the extension model, each of these becomes a `CommandDescriptor` registered by the built-in core extension (`com.kittycode.core`), and each switch arm becomes the body of the corresponding `execute()` handler. The `ContextMenuAction` enum is deleted. The keyboard handler in `EventHandling.swift` is replaced by a keybinding resolver that maps key events to command IDs through the `CommandRegistry`.

##### Provider Protocol 2: LanguageProvider

Language support encompasses grammar registration, syntax highlighting, language detection, bracket pairs, comment tokens, indentation rules, and auto-closing pairs. This subsumes and extends the existing `GrammarRegistry` actor and `BundledLanguageManifest`.

```swift
public protocol LanguageProvider: Sendable {
    var languageDescriptor: LanguageDescriptor { get }
    var capabilities: LanguageCapabilities { get }

    // Grammar and highlighting
    func grammarDefinition() async throws -> GrammarPayload?
    func highlightQueries() async throws -> HighlightQuerySet?

    // Language intelligence (optional — default implementations return nil/empty)
    func provideCompletions(document: DocumentSnapshot, position: Position) async -> [CompletionItem]
    func provideHover(document: DocumentSnapshot, position: Position) async -> HoverInfo?
    func provideDefinition(document: DocumentSnapshot, position: Position) async -> [Location]
    func provideReferences(document: DocumentSnapshot, position: Position, includeDeclaration: Bool) async -> [Location]
    func provideDocumentSymbols(document: DocumentSnapshot) async -> [DocumentSymbol]
    func provideSignatureHelp(document: DocumentSnapshot, position: Position) async -> SignatureHelp?
    func provideCodeActions(document: DocumentSnapshot, range: TextRange, context: CodeActionContext) async -> [CodeAction]
    func provideRename(document: DocumentSnapshot, position: Position, newName: String) async -> WorkspaceEdit?
    func prepareRename(document: DocumentSnapshot, position: Position) async -> PrepareRenameResult?
    func provideInlayHints(document: DocumentSnapshot, range: TextRange) async -> [InlayHint]
    func provideFoldingRanges(document: DocumentSnapshot) async -> [FoldingRange]
    func provideSelectionRanges(document: DocumentSnapshot, positions: [Position]) async -> [[TextRange]]
}

public struct LanguageDescriptor: Codable, Sendable {
    public let id: String                    // "swift", "python", "markdown"
    public let aliases: [String]             // ["Swift", "swift"]
    public let extensions: [String]          // [".swift"]
    public let filenames: [String]           // ["Package.swift"]
    public let filenamePatterns: [String]    // ["Dockerfile.*"]
    public let firstLinePattern: String?     // regex for shebang/modeline detection
    public let configuration: LanguageConfiguration
}

public struct LanguageConfiguration: Codable, Sendable {
    public let lineComment: String?          // "//"
    public let blockComment: (String, String)?  // ("/*", "*/")
    public let brackets: [(String, String)]  // [("{", "}"), ("[", "]"), ("(", ")")]
    public let autoClosingPairs: [AutoClosingPair]
    public let surroundingPairs: [(String, String)]
    public let indentationRules: IndentationRules?
    public let wordPattern: String?          // regex defining word boundaries
    public let onEnterRules: [OnEnterRule]   // rules for automatic indentation on Enter
}

public struct AutoClosingPair: Codable, Sendable {
    public let open: String
    public let close: String
    public let notIn: [AutoClosingContext]   // .string, .comment, .regex

    public enum AutoClosingContext: String, Codable, Sendable {
        case string, comment, regex
    }
}

/// Capabilities bitset: the host only calls methods for declared capabilities.
/// Methods for undeclared capabilities have default empty implementations via protocol extension.
public struct LanguageCapabilities: OptionSet, Codable, Sendable {
    public let rawValue: UInt32
    public static let grammar               = LanguageCapabilities(rawValue: 1 << 0)
    public static let completion            = LanguageCapabilities(rawValue: 1 << 1)
    public static let hover                 = LanguageCapabilities(rawValue: 1 << 2)
    public static let definition            = LanguageCapabilities(rawValue: 1 << 3)
    public static let references            = LanguageCapabilities(rawValue: 1 << 4)
    public static let documentSymbols       = LanguageCapabilities(rawValue: 1 << 5)
    public static let signatureHelp         = LanguageCapabilities(rawValue: 1 << 6)
    public static let codeActions           = LanguageCapabilities(rawValue: 1 << 7)
    public static let rename                = LanguageCapabilities(rawValue: 1 << 8)
    public static let formatting            = LanguageCapabilities(rawValue: 1 << 9)
    public static let inlayHints            = LanguageCapabilities(rawValue: 1 << 10)
    public static let foldingRanges         = LanguageCapabilities(rawValue: 1 << 11)
    public static let selectionRanges       = LanguageCapabilities(rawValue: 1 << 12)
}

/// Grammar payload: either an inline grammar definition or a path to grammar resources.
public enum GrammarPayload: Sendable {
    case inline(GrammarDefinition)                    // compile-time grammar
    case bundle(grammarPath: String, queriesPath: String)  // external resource bundle
    case treeSitterWasm(Data)                         // future: WASM-compiled tree-sitter grammar
}
```

**GrammarRegistry integration.** The existing `GrammarRegistry` actor (`Sources/KittySyntax/GrammarRegistry.swift`) has `register()`, `loadManifest()`, `entry(forExtension:)`, `grammar()`, and `compiledResult()` methods with built-in memory and disk caching, but it is completely bypassed at runtime. The runtime instead goes through `BundledLanguageManifest.entry(forFilename:)` -> `SyntaxArtifactsCache.artifacts(for:)` -> `LanguageHighlighter.Session.init()`. Under the extension model, `GrammarRegistry` becomes the single source of truth for language resolution:

1. On startup, the built-in language extension (`com.kittycode.languages`) loads `languages.json` and registers each entry via `GrammarRegistry.register()`, making built-in languages indistinguishable from contributed ones.
2. When a `LanguageProvider` extension activates, the host calls `grammarDefinition()` and registers the result with `GrammarRegistry`.
3. `LanguageHighlighter` receives a `GrammarRegistry` reference and calls `entry(forExtension:)` instead of `BundledLanguageManifest.entry(forFilename:)`.
4. The `externals` check (`grammar.externals.isEmpty` in `LanguageHighlighter.swift`) moves into `GrammarRegistry.compiledResult()`. Languages with externals register with a lower `LanguageSupportTier`.
5. `SyntaxArtifactsCache` remains as an optimization layer above the registry.

**Language detection stack.** Detection priority: user override (from config `languageOverrides`) > exact filename match (`Makefile`, `Dockerfile`, `.gitignore`) > file extension (`.swift`, `.py`) > shebang detection (`#!/usr/bin/env python3`) > first-line pattern (Emacs/Vim modelines) > plain text default. All language providers contribute their detection rules through `LanguageDescriptor`, and the `LanguageDetector` evaluates them in priority order.

##### Provider Protocol 3: DiagnosticProvider

Diagnostics are decoupled from language intelligence. Any extension can push diagnostics — linters, compilers, custom analysis tools, AI-powered code review. The diagnostic system is inspired by Neovim's `vim.diagnostic` model: a generic, provider-agnostic pipeline.

```swift
public protocol DiagnosticProvider: Sendable {
    var diagnosticDescriptor: DiagnosticProviderDescriptor { get }

    /// Compute diagnostics for a document. Called on document open, save, or content change
    /// depending on the trigger configuration.
    func provideDiagnostics(document: DocumentSnapshot) async -> [Diagnostic]
}

public struct DiagnosticProviderDescriptor: Codable, Sendable {
    public let id: String                        // "swiftlint", "eslint", "myCustomChecker"
    public let displayName: String               // "SwiftLint"
    public let supportedLanguages: [String]      // ["swift"] — empty means all languages
    public let triggers: DiagnosticTriggerSet     // when to recompute diagnostics
}

public struct DiagnosticTriggerSet: OptionSet, Codable, Sendable {
    public let rawValue: UInt8
    public static let onOpen    = DiagnosticTriggerSet(rawValue: 1 << 0)
    public static let onSave    = DiagnosticTriggerSet(rawValue: 1 << 1)
    public static let onChange  = DiagnosticTriggerSet(rawValue: 1 << 2)  // debounced
    public static let manual    = DiagnosticTriggerSet(rawValue: 1 << 3)
}

public struct Diagnostic: Codable, Sendable {
    public let range: TextRange
    public let message: String
    public let severity: DiagnosticSeverity      // .error, .warning, .information, .hint
    public let code: DiagnosticCode?
    public let source: String                    // "swiftlint", "eslint"
    public let relatedInformation: [DiagnosticRelatedInfo]
    public let tags: [DiagnosticTag]             // .unnecessary, .deprecated
    public let data: AnyCodable?                 // extension-specific data for code actions
}

public enum DiagnosticSeverity: Int, Codable, Sendable {
    case error = 1, warning = 2, information = 3, hint = 4
}

public struct DiagnosticCode: Codable, Sendable {
    public let value: String                     // "SA1001", "no-unused-vars"
    public let target: String?                   // URL to documentation
}

public enum DiagnosticTag: String, Codable, Sendable {
    case unnecessary    // grayed-out rendering
    case deprecated     // strikethrough rendering
}
```

The host manages a `DiagnosticCollection` per provider per document. When diagnostics change, the host notifies the rendering pipeline, which renders them as underlines, gutter markers, and virtual text annotations. The diagnostic system is the input for `CodeActionProvider` — code actions can reference diagnostics by their code and range.

##### Provider Protocol 4: ThemeProvider

Themes control the visual appearance of the entire editor. The 45+ color properties in `Config.swift` (`ColorScheme` struct, syntax attributes, git colors, diagnostic colors) are all theme-controlled.

```swift
public protocol ThemeProvider: Sendable {
    var themes: [ThemeDescriptor] { get }
    func resolveTheme(id: String) async throws -> ResolvedTheme
}

public struct ThemeDescriptor: Codable, Sendable {
    public let id: String                    // "monokai-pro"
    public let displayName: String           // "Monokai Pro"
    public let kind: ThemeKind               // .dark, .light, .highContrast
    public let extensionId: String           // owning extension
}

public enum ThemeKind: String, Codable, Sendable {
    case dark, light, highContrast, highContrastLight
}

public struct ResolvedTheme: Codable, Sendable {
    // Editor chrome
    public let editor: EditorColors
    public let statusBar: StatusBarColors
    public let tabRibbon: TabRibbonColors
    public let activityBar: ActivityBarColors
    public let sidebar: SidebarColors
    public let scrollbar: ScrollbarColors
    public let contextMenu: ContextMenuColors
    public let prompt: PromptColors

    // Content
    public let syntax: SyntaxTokenColors       // per-token-type colors
    public let semanticTokens: SemanticTokenColors?  // semantic highlighting overrides

    // Decoration
    public let git: GitColors
    public let diagnostic: DiagnosticColors
    public let diff: DiffColors
    public let search: SearchHighlightColors
    public let bracket: BracketColors          // bracket pair colorization

    // Terminal (for integrated terminal, future)
    public let terminal: TerminalColors
}

public struct SyntaxTokenColors: Codable, Sendable {
    public let keyword: TerminalColor
    public let string: TerminalColor
    public let number: TerminalColor
    public let comment: TerminalColor
    public let type: TerminalColor
    public let function: TerminalColor
    public let variable: TerminalColor
    public let constant: TerminalColor
    public let operator_: TerminalColor
    public let punctuation: TerminalColor
    public let attribute: TerminalColor
    public let tag: TerminalColor
    public let namespace: TerminalColor
    public let property: TerminalColor
    public let enumMember: TerminalColor
    public let macro: TerminalColor
    public let regex: TerminalColor
    public let escape: TerminalColor

    // Extensible: additional token types via dictionary
    public let custom: [String: TerminalColor]
}
```

**Migration.** The existing `EditorStateCore.ColorScheme` struct and the `Theme` type in `Sources/KittySyntax/Theme.swift` become the default theme extension (`com.kittycode.defaultTheme`). The `theme.setStyle()` calls scattered through `EditorStateTheme.swift` are replaced by a single `applyTheme(_ theme: ResolvedTheme)` method that propagates colors to all rendering components. Theme switching becomes: user selects theme ID -> host calls `ThemeProvider.resolveTheme(id:)` -> host calls `applyTheme()` -> render pipeline invalidates all cells.

##### Provider Protocol 5: SidebarProvider

Sidebar panes are full UI surfaces with their own rendering, input handling, and focus management. Today, `SidebarPanel` is a closed enum with exactly two cases (`.explorer`, `.openDocuments`). The extension model opens this to arbitrary contributions.

```swift
public protocol SidebarProvider: Sendable {
    var panes: [SidebarPaneDescriptor] { get }
    func createPaneController(id: String, context: ExtensionContext) async throws -> SidebarPaneController
}

public struct SidebarPaneDescriptor: Codable, Sendable {
    public let id: String                    // "git.changes", "search.results"
    public let title: String                 // "Changes"
    public let icon: String                  // symbol name for the activity bar
    public let order: Int                    // position in activity bar (lower = higher)
    public let defaultVisibility: PaneVisibility  // .visible, .hidden, .collapsed
    public let activationEvent: ActivationEvent?  // when to activate the owning extension
    public let contextMenuCommands: [String] // command IDs for the pane's title bar menu
}

/// The controller is the imperative counterpart to the declarative descriptor.
/// It handles rendering, input, and state for a single sidebar pane instance.
public protocol SidebarPaneController: Sendable {
    var id: String { get }

    // Rendering: the host allocates a rectangular region and calls render()
    // each frame. The controller writes into the provided ScreenBuffer.
    func render(to buffer: inout ScreenBuffer, in rect: Rect, context: RenderContext)

    // Input: key events routed to this pane when it has focus
    func handleKey(_ key: KeyEvent) -> KeyHandlerResult

    // Mouse: click/scroll events within this pane's rect
    func handleMouse(_ mouse: MouseEvent, at localPosition: Position) -> KeyHandlerResult

    // Focus: what focusable targets exist within this pane?
    // Integrates with FocusEngine's ring buffer for tab navigation.
    func focusTargets() -> [FocusTarget]
    func onFocusGained(target: FocusTarget)
    func onFocusLost()

    // Lifecycle
    func onPaneVisible() async
    func onPaneHidden() async
    func dispose() async
}

public enum KeyHandlerResult: Sendable {
    case handled            // event consumed, do not propagate
    case unhandled          // event not consumed, propagate to parent
    case executeCommand(String, CommandArgs?)  // delegate to command system
}
```

**Migration.** The `SidebarPanel` enum is deleted. `EditorStateCore`'s `activeSidebarPanel` property changes from `SidebarPanel?` to `String?` (a pane ID). The activity bar rendering in `RenderActivityBar.swift` iterates over `ContributionRegistry.sidebarPanes()` instead of switching on an enum. The file explorer pane in `RenderTree.swift` and `TreeInput.swift` becomes a `SidebarPaneController` implementation registered by `com.kittycode.explorer`. The open documents pane in `RenderOpenFiles.swift` becomes another controller in the same extension. The `FocusEngine` struct (currently unused in `Sources/KittyWidgets/FocusEngine.swift`) is finally wired in — sidebar pane controllers declare their `focusTargets()`, and the `FocusEngine` manages tab-order navigation across panes.

##### Provider Protocol 6: StatusBarProvider

Status bar segments are the individually-rendered units in the status bar. Today, `StatusBarConfig.Item` is a closed 9-case enum (`path`, `file`, `status`, `language`, `size`, `lineEnding`, `git`, `position`, `visibility`). The extension model replaces this with dynamic registration.

```swift
public protocol StatusBarProvider: Sendable {
    var items: [StatusBarItemDescriptor] { get }

    /// Resolve the current content for a status bar item.
    /// Called each render cycle for visible items.
    func resolve(itemId: String, context: StatusBarResolveContext) async -> StatusBarSegment?
}

public struct StatusBarItemDescriptor: Codable, Sendable {
    public let id: String                        // "git.branch", "editor.position"
    public let alignment: StatusBarAlignment      // .left, .right
    public let priority: Int                      // sort order within alignment group (higher = more left/right)
    public let command: String?                   // command to execute on click
    public let tooltip: String?                   // hover text
    public let showWhen: ContextExpression?       // when is this item visible?
}

public enum StatusBarAlignment: String, Codable, Sendable {
    case left, right
}

public struct StatusBarSegment: Sendable {
    public let text: String                      // the displayed text
    public let foreground: TerminalColor?
    public let background: TerminalColor?
    public let bold: Bool
    public let icon: String?                     // prepended symbol
}

public struct StatusBarResolveContext: Sendable {
    public let activeDocument: DocumentSnapshot?
    public let mode: String                      // "normal", "insert", "visual"
    public let workspacePath: String?
    public let focusedElement: String?
}
```

**Migration.** The `StatusBarConfig.Item` enum is deleted. The `StatusBar` widget in `Sources/KittyWidgets/StatusBar.swift` changes from switching on `Item` cases to iterating over `ContributionRegistry.statusBarItems(alignment:)` and calling `StatusBarProvider.resolve()` for each. The built-in items (`path`, `file`, `status`, `language`, `size`, `lineEnding`, `git`, `position`, `visibility`) become nine `StatusBarItemDescriptor` entries registered by `com.kittycode.core`, with their `resolve()` implementations reading from the same state they read today.

##### Provider Protocol 7: KeybindingProvider

Keybindings map key combinations to commands. Today, `EventHandling.swift` has 24 hardcoded shortcut handlers that directly call `EditorState` methods. The extension model replaces this with a declarative keybinding system.

```swift
public protocol KeybindingProvider: Sendable {
    var keybindings: [KeybindingDescriptor] { get }
}

public struct KeybindingDescriptor: Codable, Sendable {
    public let key: String                       // "ctrl+shift+p", "g g" (multi-key sequence)
    public let command: String                   // "kittycode.commandPalette.show"
    public let args: CommandArgs?                // arguments to pass to the command
    public let when: ContextExpression?          // context condition for this binding
    public let priority: KeybindingPriority      // resolution order for conflicts
}

public enum KeybindingPriority: Int, Codable, Sendable {
    case `default` = 0       // extension-contributed
    case builtin = 100       // built-in editor keybindings
    case user = 200          // user overrides in config
}
```

**Keybinding resolution.** When a key event arrives via `InputEvent.key(KeyEvent)`:

1. The `KeybindingResolver` looks up all `KeybindingDescriptor` entries matching the key combination.
2. For multi-key sequences (e.g., `g g` in vim normal mode), it maintains a pending-key buffer with a timeout.
3. It evaluates each matching descriptor's `when` condition against the current `ContextKeySet` (which includes: `editorMode` = "normal"/"insert", `editorFocused`, `sidebarFocused`, `resourceLangId`, `editorHasSelection`, `editorReadonly`, etc.).
4. Among matching descriptors whose `when` evaluates to true, it selects the highest-priority one.
5. It calls `CommandRegistry.execute(id:args:)` with the winning descriptor's command and args.
6. If no descriptor matches, the key event falls through to the default input handler (text insertion in insert mode, motion in normal mode).

This replaces the `switch` ladder in `EventHandling.swift` and the shallow vim emulation in `EditorInput.swift`. The 24 existing shortcuts become 24 `KeybindingDescriptor` entries in the built-in core extension. The vim normal-mode motions (`h`, `j`, `k`, `l`, `w`, `b`, `e`, `0`, `$`, `gg`, `G`, etc.) become keybindings with `when: "editorMode == normal"`.

**User keybinding overrides.** Users customize keybindings in `~/.kittycode.json` under a `"keybindings"` section. User keybindings have `priority: .user` and override all extension and built-in bindings. Negative keybindings (e.g., `{ "key": "ctrl+k", "command": "-" }`) unbind a key.

##### Provider Protocol 8: MenuProvider

Menus contribute items to context menus, the command palette, and any future menu surfaces (editor title bar, tab context menu, gutter context menu).

```swift
public protocol MenuProvider: Sendable {
    var menuContributions: [MenuContribution] { get }
}

public struct MenuContribution: Codable, Sendable {
    public let location: MenuLocation
    public let group: String                     // "navigation", "1_modification", "z_other"
    public let command: String                   // command ID
    public let when: ContextExpression?          // visibility condition
    public let order: Int                        // sort within group
}

public enum MenuLocation: String, Codable, Sendable {
    case editorContext           // right-click in editor
    case explorerContext         // right-click in file explorer
    case tabContext              // right-click on tab
    case editorTitle             // icons in editor title bar
    case commandPalette          // items in command palette (all commands appear automatically; this is for overrides)
    case gutterContext           // right-click in gutter
    case statusBarContext        // right-click on status bar
    case sidebarTitle            // icons in sidebar pane title
}
```

**Migration.** The `ContextMenuItem` struct and the `ContextMenuAction` enum in `EditorStateCore.swift` are deleted. The context menu rendering code switches from a hardcoded `[ContextMenuItem]` array to `ContributionRegistry.menuItems(for: .editorContext, context: currentContextKeys)`, which evaluates `when` conditions and returns sorted, grouped menu items. Each item references a command ID; clicking it calls `CommandRegistry.execute()`.

##### Provider Protocol 9: DecorationProvider

Decorations are visual annotations layered on top of the editor content: gutter markers, line highlights, inline virtual text, bracket colorization, file tree badges.

```swift
public protocol DecorationProvider: Sendable {
    var decorationDescriptor: DecorationProviderDescriptor { get }

    /// Editor decorations: inline highlights, virtual text, underlines
    func provideEditorDecorations(document: DocumentSnapshot) async -> [EditorDecoration]

    /// Gutter decorations: markers in the line number column
    func provideGutterDecorations(document: DocumentSnapshot) async -> [GutterDecoration]

    /// File decorations: badges, colors, icons on file tree entries
    func provideFileDecorations(uri: String) async -> FileDecoration?
}

public struct DecorationProviderDescriptor: Codable, Sendable {
    public let id: String
    public let supportedLanguages: [String]      // empty means all
    public let triggers: DecorationTriggerSet    // when to recompute
}

public struct DecorationTriggerSet: OptionSet, Codable, Sendable {
    public let rawValue: UInt8
    public static let onOpen     = DecorationTriggerSet(rawValue: 1 << 0)
    public static let onSave     = DecorationTriggerSet(rawValue: 1 << 1)
    public static let onChange   = DecorationTriggerSet(rawValue: 1 << 2)
    public static let onScroll   = DecorationTriggerSet(rawValue: 1 << 3)
    public static let onInterval = DecorationTriggerSet(rawValue: 1 << 4)  // periodic refresh
}

public struct EditorDecoration: Codable, Sendable {
    public let range: TextRange
    public let kind: EditorDecorationKind
    public let style: DecorationStyle
    public let hoverMessage: String?
}

public enum EditorDecorationKind: String, Codable, Sendable {
    case highlight                // background color on a range
    case underline                // underline (wavy, solid, dashed)
    case border                   // border around a range
    case virtualTextInline        // text inserted inline (e.g., inlay hints)
    case virtualTextAfterLine     // text appended after end of line (e.g., git blame)
    case virtualTextBeforeLine    // text prepended before start of line
    case wholeLine                // entire line background
}

public struct DecorationStyle: Codable, Sendable {
    public let foreground: TerminalColor?
    public let background: TerminalColor?
    public let bold: Bool?
    public let italic: Bool?
    public let underlineStyle: UnderlineStyle?   // .solid, .wavy, .dashed, .dotted
    public let underlineColor: TerminalColor?
    public let opacity: Double?                  // for dimming (e.g., unused code)
}

public struct GutterDecoration: Codable, Sendable {
    public let line: Int
    public let icon: String?                     // symbol in gutter
    public let color: TerminalColor?
    public let tooltip: String?
    public let command: String?                  // command on click
}

public struct FileDecoration: Codable, Sendable {
    public let badge: String?                    // "M", "U", "!" — short text badge
    public let badgeColor: TerminalColor?
    public let labelColor: TerminalColor?        // color of the filename text
    public let propagate: Bool                   // propagate to parent directories
}
```

**Migration.** The existing `FileStatusProvider` protocol (in `Sources/KittyFileTree/FileStatusProvider.swift`) and `GitLineDecorationProvider` (in `Sources/KittyGit/GitLineDecorations.swift`) become `DecorationProvider` implementations in the `com.kittycode.git` extension. The rendering code in `RenderTree.swift` (file tree badges) and the editor view (git line decorations) switches from directly calling these protocols to querying `ContributionRegistry.decorationProviders(for: document)`.

##### Provider Protocol 10: FormatterProvider

Formatters transform document text for stylistic purposes — indentation, spacing, line length, brace placement.

```swift
public protocol FormatterProvider: Sendable {
    var formatterDescriptor: FormatterDescriptor { get }

    func formatDocument(document: DocumentSnapshot, options: FormattingOptions) async throws -> [TextEdit]
    func formatRange(document: DocumentSnapshot, range: TextRange, options: FormattingOptions) async throws -> [TextEdit]
    func formatOnType(document: DocumentSnapshot, position: Position, character: String, options: FormattingOptions) async throws -> [TextEdit]
}

public struct FormatterDescriptor: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let supportedLanguages: [String]
    public let triggers: FormattingTriggerSet
}

public struct FormattingTriggerSet: OptionSet, Codable, Sendable {
    public let rawValue: UInt8
    public static let onSave   = FormattingTriggerSet(rawValue: 1 << 0)
    public static let onPaste  = FormattingTriggerSet(rawValue: 1 << 1)
    public static let onType   = FormattingTriggerSet(rawValue: 1 << 2)
    public static let manual   = FormattingTriggerSet(rawValue: 1 << 3)
}

public struct FormattingOptions: Codable, Sendable {
    public let tabSize: Int
    public let insertSpaces: Bool
    public let trimTrailingWhitespace: Bool
    public let insertFinalNewline: Bool
    public let trimFinalNewlines: Bool
}
```

When multiple formatters are registered for the same language, the user's config determines which one is active (`"editor.defaultFormatter": "com.example.swiftformat"`). The host invokes only the active formatter for each trigger.

##### Provider Protocol 11: WorkspaceEventListener

Workspace events are the semantic event layer. Extensions subscribe to the events they care about. All methods have default empty implementations via protocol extension.

```swift
public protocol WorkspaceEventListener: Sendable {
    func onFileOpened(document: DocumentSnapshot) async
    func onFileClosed(uri: String) async
    func onFileSaved(document: DocumentSnapshot) async
    func onFileWillSave(document: DocumentSnapshot) async -> [TextEdit]?
    func onFileCreated(uri: String) async
    func onFileDeleted(uri: String) async
    func onFileRenamed(oldUri: String, newUri: String) async
    func onActiveEditorChanged(document: DocumentSnapshot?) async
    func onConfigurationChanged(section: String) async
    func onBufferContentChanged(document: DocumentSnapshot, changes: [ContentChange]) async
    func onSelectionChanged(document: DocumentSnapshot, selections: [TextRange]) async
    func onVisibleRangesChanged(document: DocumentSnapshot, ranges: [TextRange]) async
    func onEditorModeChanged(oldMode: String, newMode: String) async
    func onFocusChanged(element: String) async
    func onWorkspaceOpened(path: String) async
    func onWorkspaceClosed() async
    func onExtensionActivated(extensionId: String) async
    func onExtensionDeactivated(extensionId: String) async
}

public struct ContentChange: Codable, Sendable {
    public let range: TextRange
    public let rangeLength: Int
    public let text: String
}
```

The `onFileWillSave` event is special: it is synchronous from the save operation's perspective. The host collects `[TextEdit]` results from all listeners, applies them in order, then completes the save. This enables format-on-save, import organization, and other pre-save transformations. A timeout (configurable, default 1500ms) prevents a misbehaving extension from blocking saves indefinitely.

##### Provider Protocol 12: DocumentTransformer

Document transformers intercept and modify document content at specific trigger points. They are distinct from formatters in that they perform semantic transformations (auto-pairs, snippet expansion, import sorting) rather than stylistic ones.

```swift
public protocol DocumentTransformer: Sendable {
    var transformerDescriptor: DocumentTransformerDescriptor { get }

    func transformOnType(document: DocumentSnapshot, position: Position, character: String) async -> [TextEdit]?
    func transformOnPaste(document: DocumentSnapshot, range: TextRange, pastedText: String) async -> [TextEdit]?
    func transformOnOpen(document: DocumentSnapshot) async -> [TextEdit]?
    func transformOnSave(document: DocumentSnapshot) async -> [TextEdit]?
}

public struct DocumentTransformerDescriptor: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let supportedLanguages: [String]
    public let priority: Int                     // execution order among transformers
    public let triggers: TransformTriggerSet
}

public struct TransformTriggerSet: OptionSet, Codable, Sendable {
    public let rawValue: UInt8
    public static let onType   = TransformTriggerSet(rawValue: 1 << 0)
    public static let onPaste  = TransformTriggerSet(rawValue: 1 << 1)
    public static let onOpen   = TransformTriggerSet(rawValue: 1 << 2)
    public static let onSave   = TransformTriggerSet(rawValue: 1 << 3)
}
```

**Transformer chaining.** When multiple transformers are registered for the same trigger, they execute in priority order. Each transformer receives the document state after the previous transformer's edits have been applied. This is the mechanism for composable editing behaviors: an auto-pair transformer inserts the closing bracket, then a snippet transformer checks if the typed text matches a snippet prefix.

**Relationship to Emacs advice.** This is KittyCode's equivalent of Emacs's advice system (`before-advice`, `after-advice`, `around-advice`). Document transformers are "before-advice" on document mutations — they intercept a change and can modify it before it is committed. The `WorkspaceEventListener.onFileWillSave` is "before-advice" on saves. Future work could add `around`-style interception for commands (wrapping a command's execution with pre/post logic), but that is not needed for the initial design.

##### Provider Protocol 13: CompletionProvider

Autocompletion suggestions powered by any source — keyword lists, snippets, LSP servers, AI models.

```swift
public protocol CompletionProvider: Sendable {
    var completionDescriptor: CompletionProviderDescriptor { get }

    func provideCompletions(document: DocumentSnapshot, position: Position, context: CompletionContext) async -> CompletionList

    /// Resolve additional detail for a completion item (lazy-loaded).
    /// Called when the user highlights an item in the completion menu.
    func resolveCompletionItem(_ item: CompletionItem) async -> CompletionItem
}

public struct CompletionProviderDescriptor: Codable, Sendable {
    public let id: String
    public let supportedLanguages: [String]
    public let triggerCharacters: [String]       // [".", ":", "<", "/"]
    public let priority: Int                     // ordering among providers
}

public struct CompletionContext: Codable, Sendable {
    public let triggerKind: CompletionTriggerKind  // .invoked, .triggerCharacter, .triggerForIncompleteCompletions
    public let triggerCharacter: String?
}

public enum CompletionTriggerKind: Int, Codable, Sendable {
    case invoked = 1                             // explicitly invoked (Ctrl+Space)
    case triggerCharacter = 2                    // triggered by a trigger character
    case triggerForIncompleteCompletions = 3     // re-triggered for incomplete results
}

public struct CompletionList: Codable, Sendable {
    public let isIncomplete: Bool                // if true, requery on further typing
    public let items: [CompletionItem]
}

public struct CompletionItem: Codable, Sendable {
    public let label: String
    public let kind: CompletionItemKind          // .keyword, .function, .variable, .snippet, etc.
    public let detail: String?                   // type signature or short description
    public let documentation: MarkupContent?     // full documentation (lazy-resolved)
    public let sortText: String?                 // custom sort key
    public let filterText: String?               // custom filter key (if different from label)
    public let insertText: String?               // text to insert (if different from label)
    public let insertTextFormat: InsertTextFormat // .plainText, .snippet
    public let textEdit: TextEdit?               // precise edit to apply
    public let additionalTextEdits: [TextEdit]   // other edits (e.g., add import)
    public let command: String?                  // command to execute after insertion
    public let data: AnyCodable?                 // extension-specific data for resolve()
}

public enum CompletionItemKind: Int, Codable, Sendable {
    case text = 1, method = 2, function = 3, constructor = 4, field = 5, variable = 6
    case `class` = 7, interface = 8, module = 9, property = 10, unit = 11, value = 12
    case `enum` = 13, keyword = 14, snippet = 15, color = 16, file = 17, reference = 18
    case folder = 19, enumMember = 20, constant = 21, `struct` = 22, event = 23
    case `operator` = 24, typeParameter = 25
}

public enum InsertTextFormat: Int, Codable, Sendable {
    case plainText = 1
    case snippet = 2   // supports $1, $2 tabstops and ${1:placeholder} syntax
}
```

When multiple `CompletionProvider`s are registered for the same language, the host merges their results into a single completion menu, sorted by provider priority and then by `sortText`. The host manages the completion UI lifecycle: showing the popup, filtering as the user types, selecting an item, applying the `textEdit`, executing the post-insertion `command`, and dismissing the popup.

##### Provider Protocol 14: HoverProvider

Hover information appears when the cursor rests on a symbol — type information, documentation, diagnostics.

```swift
public protocol HoverProvider: Sendable {
    var hoverDescriptor: HoverProviderDescriptor { get }

    func provideHover(document: DocumentSnapshot, position: Position) async -> HoverResult?
}

public struct HoverProviderDescriptor: Codable, Sendable {
    public let id: String
    public let supportedLanguages: [String]
}

public struct HoverResult: Codable, Sendable {
    public let contents: [MarkupContent]         // multiple sections (type, docs, diagnostics)
    public let range: TextRange?                 // range that the hover applies to (highlighted)
}

public struct MarkupContent: Codable, Sendable {
    public let kind: MarkupKind                  // .plaintext, .markdown
    public let value: String
}

public enum MarkupKind: String, Codable, Sendable {
    case plaintext, markdown
}
```

When multiple hover providers are registered, the host merges their results vertically — each provider's content appears as a section in the hover popup. In a terminal environment, markdown is rendered as styled text (bold, italic, code spans) using terminal escape sequences.

##### Provider Protocol 15: CodeActionProvider

Code actions are quick fixes, refactoring operations, and source actions that appear as suggestions (lightbulb icon in GUI editors, inline prompt in terminal editors) associated with a code range or diagnostic.

```swift
public protocol CodeActionProvider: Sendable {
    var codeActionDescriptor: CodeActionProviderDescriptor { get }

    func provideCodeActions(document: DocumentSnapshot, range: TextRange, context: CodeActionContext) async -> [CodeAction]
    func resolveCodeAction(_ action: CodeAction) async -> CodeAction
}

public struct CodeActionProviderDescriptor: Codable, Sendable {
    public let id: String
    public let supportedLanguages: [String]
    public let providedCodeActionKinds: [CodeActionKind]
}

public struct CodeActionContext: Codable, Sendable {
    public let diagnostics: [Diagnostic]         // diagnostics at the requested range
    public let only: [CodeActionKind]?           // filter by kind (e.g., only quick fixes)
    public let triggerKind: CodeActionTriggerKind // .invoked, .automatic
}

public enum CodeActionTriggerKind: Int, Codable, Sendable {
    case invoked = 1     // user explicitly requested code actions
    case automatic = 2   // automatic (e.g., on save with "source.organizeImports")
}

public struct CodeAction: Codable, Sendable {
    public let title: String                     // "Add missing import"
    public let kind: CodeActionKind
    public let diagnostics: [Diagnostic]?        // diagnostics this action resolves
    public let isPreferred: Bool                 // auto-apply in "fix all" scenarios
    public let edit: WorkspaceEdit?              // text edits to apply
    public let command: String?                  // command to execute after edits
    public let commandArgs: CommandArgs?
    public let data: AnyCodable?                 // for lazy resolution
}

public enum CodeActionKind: String, Codable, Sendable {
    case quickFix = "quickfix"
    case refactor = "refactor"
    case refactorExtract = "refactor.extract"
    case refactorInline = "refactor.inline"
    case refactorRewrite = "refactor.rewrite"
    case source = "source"
    case sourceOrganizeImports = "source.organizeImports"
    case sourceFixAll = "source.fixAll"
}

public struct WorkspaceEdit: Codable, Sendable {
    public let changes: [String: [TextEdit]]     // uri -> edits
    public let documentChanges: [DocumentChange]?  // ordered, for rename/create/delete
}

public enum DocumentChange: Codable, Sendable {
    case textEdit(uri: String, edits: [TextEdit])
    case createFile(uri: String, overwrite: Bool)
    case renameFile(oldUri: String, newUri: String, overwrite: Bool)
    case deleteFile(uri: String, recursive: Bool)
}
```

##### Provider Protocol 16: Extension Protocol (Base)

Every extension implements this base protocol. It is the root of the extension lifecycle.

```swift
public protocol Extension: Sendable {
    /// The static manifest declaring this extension's identity and contributions.
    var manifest: ExtensionManifest { get }

    /// Called when the extension is activated. The context is the extension's
    /// gateway to the editor API. Register providers, commands, and event
    /// listeners here.
    func activate(context: ExtensionContext) async throws

    /// Called when the extension is deactivated. Clean up resources, cancel
    /// background tasks, close file handles.
    func deactivate() async
}
```

The host discovers which provider protocols an extension also conforms to via runtime checks:

```swift
func registerProviders(for ext: any Extension, context: ExtensionContext) async {
    if let provider = ext as? CommandProvider {
        for descriptor in provider.commands {
            await commandRegistry.register(CommandRegistration(
                descriptor: descriptor,
                handler: { args in try await provider.execute(command: descriptor.id, args: args) }
            ))
        }
    }
    if let provider = ext as? LanguageProvider {
        await contributionRegistry.registerLanguageProvider(provider)
    }
    if let provider = ext as? DiagnosticProvider {
        await contributionRegistry.registerDiagnosticProvider(provider)
    }
    if let provider = ext as? ThemeProvider {
        await contributionRegistry.registerThemeProvider(provider)
    }
    if let provider = ext as? SidebarProvider {
        await contributionRegistry.registerSidebarProvider(provider)
    }
    if let provider = ext as? StatusBarProvider {
        await contributionRegistry.registerStatusBarProvider(provider)
    }
    if let provider = ext as? KeybindingProvider {
        await contributionRegistry.registerKeybindingProvider(provider)
    }
    if let provider = ext as? MenuProvider {
        await contributionRegistry.registerMenuProvider(provider)
    }
    if let provider = ext as? DecorationProvider {
        await contributionRegistry.registerDecorationProvider(provider)
    }
    if let provider = ext as? FormatterProvider {
        await contributionRegistry.registerFormatterProvider(provider)
    }
    if let provider = ext as? WorkspaceEventListener {
        await eventBus.subscribe(provider)
    }
    if let provider = ext as? DocumentTransformer {
        await contributionRegistry.registerDocumentTransformer(provider)
    }
    if let provider = ext as? CompletionProvider {
        await contributionRegistry.registerCompletionProvider(provider)
    }
    if let provider = ext as? HoverProvider {
        await contributionRegistry.registerHoverProvider(provider)
    }
    if let provider = ext as? CodeActionProvider {
        await contributionRegistry.registerCodeActionProvider(provider)
    }
}
```

---

#### 3. Extension API Surface

The Extension API Surface is what the host exposes to extensions through `ExtensionContext`. This is the boundary between extension code and editor internals. Extensions never access `EditorState`, `BufferManager`, `RenderPipeline`, or any internal type directly — they interact with the editor exclusively through this API.

##### ExtensionContext

```swift
public protocol ExtensionContext: Sendable {
    // Identity
    var extensionId: String { get }
    var extensionVersion: String { get }
    var storagePath: String { get }              // ~/.kittycode/extension-storage/<extensionId>/
    var workspacePath: String? { get }

    // Command registration
    func registerCommand(_ id: String, handler: @Sendable (CommandArgs?) async throws -> CommandResult) async
    func executeCommand(_ id: String, args: CommandArgs?) async throws -> CommandResult

    // Provider registration (alternative to protocol conformance discovery)
    func registerProvider<P: Sendable>(_ provider: P) async

    // Event subscription
    func subscribe<E: WorkspaceEvent>(_ eventType: E.Type, handler: @Sendable (E) async -> Void) async -> Subscription
    func subscribeToConfigChange(section: String, handler: @Sendable (AnyCodable) async -> Void) async -> Subscription

    // Document access
    func activeDocument() async -> DocumentSnapshot?
    func openDocuments() async -> [DocumentSnapshot]
    func documentContent(uri: String) async -> String?
    func documentLines(uri: String, range: TextRange) async -> [String]
    func openDocument(uri: String) async throws
    func closeDocument(uri: String) async throws

    // Document mutation
    func applyEdits(uri: String, edits: [TextEdit]) async throws
    func setSelection(uri: String, ranges: [TextRange]) async throws
    func revealRange(uri: String, range: TextRange) async

    // Workspace
    func workspaceFiles(matching glob: String) async -> [String]
    func readFile(uri: String) async throws -> Data
    func writeFile(uri: String, data: Data) async throws
    func fileExists(uri: String) async -> Bool
    func watchFiles(glob: String) async -> AsyncStream<FileWatchEvent>

    // Configuration
    func getConfiguration<T: Decodable>(section: String) async -> T?
    func getSetting<T: Decodable>(_ key: String) async -> T?
    func getSetting<T: Decodable>(_ key: String, default: T) async -> T

    // UI
    func showInformationMessage(_ message: String, actions: [String]) async -> String?
    func showWarningMessage(_ message: String, actions: [String]) async -> String?
    func showErrorMessage(_ message: String, actions: [String]) async -> String?
    func showInputPrompt(_ descriptor: InputPromptDescriptor) async -> String?
    func showQuickPick(_ items: [QuickPickItem], options: QuickPickOptions?) async -> QuickPickItem?
    func setStatusBarMessage(_ text: String, timeout: Duration?) async
    func withProgress<T>(_ title: String, task: @Sendable () async throws -> T) async throws -> T

    // Diagnostics
    func createDiagnosticCollection(id: String) async -> DiagnosticCollectionHandle
    func setDiagnostics(collection: DiagnosticCollectionHandle, uri: String, diagnostics: [Diagnostic]) async
    func clearDiagnostics(collection: DiagnosticCollectionHandle) async

    // Output
    func createOutputChannel(name: String) async -> OutputChannelHandle
    func appendToOutput(channel: OutputChannelHandle, text: String) async

    // State
    func getState<T: Codable>(_ key: String) async -> T?
    func setState<T: Codable>(_ key: String, value: T) async
    func getWorkspaceState<T: Codable>(_ key: String) async -> T?
    func setWorkspaceState<T: Codable>(_ key: String, value: T) async

    // Lifecycle
    func dispose() async
}
```

**Key design constraints for WASM compatibility.** Every method is `async`. Every parameter and return type is `Codable & Sendable`. No closures cross the boundary (event handlers are registered through subscription objects, not passed as parameters to other calls). No mutable references. These constraints ensure the entire API surface can be projected into a WASM guest via host function imports without any redesign.

##### DocumentSnapshot

```swift
public struct DocumentSnapshot: Codable, Sendable {
    public let uri: String                       // "file:///path/to/file.swift"
    public let languageId: String                // "swift"
    public let version: Int                      // incremented on each change
    public let lineCount: Int
    public let isDirty: Bool
    public let isReadOnly: Bool
    public let eol: EndOfLine                    // .lf, .crlf

    // The full text is NOT included by default for performance.
    // Extensions call context.documentContent(uri:) or context.documentLines(uri:range:)
    // to access content on demand.
}
```

##### TextEdit and Position Types

```swift
public struct TextEdit: Codable, Sendable {
    public let range: TextRange
    public let newText: String
}

public struct TextRange: Codable, Sendable {
    public let start: Position
    public let end: Position
}

public struct Position: Codable, Sendable {
    public let line: Int         // 0-based
    public let character: Int    // 0-based, UTF-16 offset (LSP compatible)
}

public struct Location: Codable, Sendable {
    public let uri: String
    public let range: TextRange
}
```

---

#### 4. Contribution Manifest

The contribution manifest is the declarative contract between an extension and the host. It enables the host to register contributions *before* activating the extension, validate compatibility, and provide discoverability (listing available themes, commands, and languages without loading extension code).

##### Manifest Structure

For compile-time Swift extensions, the manifest is a static property on the `Extension` type:

```swift
public struct ExtensionManifest: Codable, Sendable {
    public let id: String                        // "com.example.swiftSupport"
    public let displayName: String               // "Swift Language Support"
    public let version: String                   // semver: "1.2.0"
    public let apiLevel: Int                     // minimum host API version required
    public let publisher: String?                // "kittycode" for built-in
    public let description: String?
    public let license: String?
    public let repository: String?

    public let activationEvents: [ActivationEvent]
    public let capabilities: RequiredCapabilities    // see Capability-Based Security
    public let contributions: ContributionDeclaration
    public let configuration: ConfigurationSchema?
    public let extensionDependencies: [String]       // other extensions this one requires
}

public struct ContributionDeclaration: Codable, Sendable {
    public let commands: [CommandDeclaration]
    public let languages: [LanguageDeclaration]
    public let grammars: [GrammarDeclaration]
    public let themes: [ThemeDeclaration]
    public let sidebarPanes: [SidebarPaneDeclaration]
    public let statusBarItems: [StatusBarItemDeclaration]
    public let keybindings: [KeybindingDeclaration]
    public let menus: [MenuContributionDeclaration]
    public let configuration: ConfigurationSchema?
    public let snippets: [SnippetDeclaration]
    public let formatters: [FormatterDeclaration]
    public let decorationTypes: [DecorationTypeDeclaration]
}
```

Each `*Declaration` type is a codable subset of the corresponding provider's descriptor. It contains only the information needed for pre-activation registration — no executable logic.

##### JSON Manifest Format

For external extension bundles, the same structure is expressed as `extension.json`:

```json
{
    "id": "com.example.swiftSupport",
    "displayName": "Swift Language Support",
    "version": "1.2.0",
    "apiLevel": 1,
    "publisher": "example",
    "description": "Full Swift language support for KittyCode",
    "activationEvents": ["onLanguage:swift", "workspaceContains:**/Package.swift"],
    "capabilities": {
        "fileSystem": { "readWrite": ["**/*.swift", "Package.swift", ".build/**"] },
        "process": { "spawn": ["swift", "swiftc", "swift-format", "sourcekit-lsp"] },
        "network": false
    },
    "contributions": {
        "commands": [
            { "id": "swift.build", "title": "Build Swift Project", "category": "Swift", "icon": "hammer" },
            { "id": "swift.test", "title": "Run Swift Tests", "category": "Swift" },
            { "id": "swift.format", "title": "Format Swift File", "category": "Swift" }
        ],
        "languages": [
            {
                "id": "swift",
                "aliases": ["Swift"],
                "extensions": [".swift"],
                "filenames": ["Package.swift"],
                "configuration": {
                    "lineComment": "//",
                    "blockComment": ["/*", "*/"],
                    "brackets": [["{", "}"], ["[", "]"], ["(", ")"]],
                    "autoClosingPairs": [
                        { "open": "{", "close": "}", "notIn": ["string"] },
                        { "open": "[", "close": "]", "notIn": ["string"] },
                        { "open": "(", "close": ")", "notIn": ["string"] },
                        { "open": "\"", "close": "\"", "notIn": ["string"] },
                        { "open": "/*", "close": " */", "notIn": ["string", "comment"] }
                    ],
                    "indentationRules": {
                        "increaseIndentPattern": "^.*\\{[^}\"']*$",
                        "decreaseIndentPattern": "^\\s*\\}"
                    }
                }
            }
        ],
        "grammars": [
            {
                "language": "swift",
                "scopeName": "source.swift",
                "path": "./grammars/swift/grammar.json",
                "highlightQueries": "./grammars/swift/highlights.scm",
                "injectionsQueries": "./grammars/swift/injections.scm"
            }
        ],
        "keybindings": [
            { "key": "ctrl+shift+b", "command": "swift.build", "when": "resourceLangId == swift" },
            { "key": "ctrl+shift+t", "command": "swift.test", "when": "resourceLangId == swift" }
        ],
        "statusBarItems": [
            { "id": "swift.buildStatus", "alignment": "left", "priority": 50, "command": "swift.build" },
            { "id": "swift.lspStatus", "alignment": "right", "priority": 10 }
        ],
        "menus": [
            { "location": "editorContext", "group": "1_build", "command": "swift.build", "when": "resourceLangId == swift" },
            { "location": "editorContext", "group": "1_build", "command": "swift.test", "when": "resourceLangId == swift" }
        ],
        "configuration": {
            "properties": {
                "buildOnSave": { "type": "boolean", "default": false, "description": "Automatically build on save" },
                "toolchainPath": { "type": "string", "default": "", "description": "Path to Swift toolchain" },
                "formatOnSave": { "type": "boolean", "default": true, "description": "Format with swift-format on save" },
                "lspEnabled": { "type": "boolean", "default": true, "description": "Enable SourceKit-LSP integration" }
            }
        },
        "snippets": [
            { "language": "swift", "path": "./snippets/swift.json" }
        ]
    }
}
```

The host parses the manifest at discovery time, validates all referenced command IDs, checks the `apiLevel` against the host's current level, verifies that required capabilities are acceptable, and registers all declarative contributions into the `ContributionRegistry`. The extension's Swift code (or WASM module) is not loaded until an activation event fires.

---

#### 5. Event Bus

The event bus is the publish-subscribe infrastructure for workspace events. It replaces ad-hoc notification patterns and decouples event producers (the editor core) from consumers (extensions).

```swift
public actor EventBus {
    private var listeners: [ObjectIdentifier: any WorkspaceEventListener] = [:]
    private var typedSubscriptions: [String: [(Any) async -> Void]] = [:]
    private let dispatchQueue: TaskGroup<Void>? = nil

    /// Register a WorkspaceEventListener (protocol-based subscription)
    public func subscribe(_ listener: any WorkspaceEventListener) {
        listeners[ObjectIdentifier(listener as AnyObject)] = listener
    }

    /// Unregister a listener
    public func unsubscribe(_ listener: any WorkspaceEventListener) {
        listeners.removeValue(forKey: ObjectIdentifier(listener as AnyObject))
    }

    /// Emit a workspace event to all registered listeners.
    /// Events are dispatched concurrently to all listeners. No listener can
    /// block another. Each listener call has a timeout (configurable, default 5s).
    public func emit(_ event: WorkspaceEventKind) async {
        await withTaskGroup(of: Void.self) { group in
            for (_, listener) in listeners {
                group.addTask {
                    await withTimeout(.seconds(5)) {
                        switch event {
                        case .fileOpened(let doc):
                            await listener.onFileOpened(document: doc)
                        case .fileSaved(let doc):
                            await listener.onFileSaved(document: doc)
                        case .fileClosed(let uri):
                            await listener.onFileClosed(uri: uri)
                        case .activeEditorChanged(let doc):
                            await listener.onActiveEditorChanged(document: doc)
                        case .configurationChanged(let section):
                            await listener.onConfigurationChanged(section: section)
                        case .bufferContentChanged(let doc, let changes):
                            await listener.onBufferContentChanged(document: doc, changes: changes)
                        // ... all other event kinds
                        }
                    }
                }
            }
        }
    }

    /// Emit a pre-save event and collect TextEdit results.
    /// This is a barrier event: the save blocks until all listeners respond or timeout.
    public func emitWillSave(document: DocumentSnapshot) async -> [[TextEdit]] {
        await withTaskGroup(of: [TextEdit]?.self) { group in
            var edits: [[TextEdit]] = []
            for (_, listener) in listeners {
                group.addTask {
                    await withTimeout(.milliseconds(1500)) {
                        await listener.onFileWillSave(document: document)
                    }
                }
            }
            for await result in group {
                if let e = result { edits.append(e) }
            }
            return edits
        }
    }
}

public enum WorkspaceEventKind: Sendable {
    case fileOpened(DocumentSnapshot)
    case fileClosed(String)
    case fileSaved(DocumentSnapshot)
    case fileCreated(String)
    case fileDeleted(String)
    case fileRenamed(oldUri: String, newUri: String)
    case activeEditorChanged(DocumentSnapshot?)
    case configurationChanged(String)
    case bufferContentChanged(DocumentSnapshot, [ContentChange])
    case selectionChanged(DocumentSnapshot, [TextRange])
    case visibleRangesChanged(DocumentSnapshot, [TextRange])
    case editorModeChanged(oldMode: String, newMode: String)
    case focusChanged(String)
    case workspaceOpened(String)
    case workspaceClosed
    case extensionActivated(String)
    case extensionDeactivated(String)
}
```

**Integration with `EditorState`.** The `EditorState` god object, which currently holds `workspace`, `bufferManager`, `config`, `fileStatusProvider`, `gitLineDecorationProvider`, and all UI state, becomes an event emitter. When its internal state changes — file opened, buffer saved, active tab changed, mode switched — it calls `eventBus.emit()`. This is a lightweight addition: one `emit()` call at each state transition. Extensions receive these events asynchronously and cannot block the main input/render loop.

**Activation event integration.** The event bus also notifies the `ExtensionHost` of activation-relevant events. When a `.fileOpened` event fires with a document whose `languageId` is "swift", the host checks if any dormant extension has `activationEvents: [.onLanguage("swift")]` and activates it. This is how lazy activation works.

---

#### 6. Extension Discovery and Loading

Extensions are discovered from three sources, in priority order:

1. **Compile-time extensions** — SPM targets that define `Extension` implementations. Discovered by iterating a static registry populated at build time. This is the primary mechanism for Phases 1-3.

2. **User-installed extensions** — directories under `~/.kittycode/extensions/<extensionId>/`, each containing an `extension.json` manifest and associated resources. Installed manually, via `kittycode ext install`, or via a future marketplace.

3. **Workspace-local extensions** — directories under `<workspace>/.kittycode/extensions/<extensionId>/`. These are project-specific extensions (e.g., a custom linter configuration, project-specific snippets). They are activated only for the workspace they reside in.

4. **SPM package extensions (future)** — a SwiftPM plugin mechanism where a `Package.swift` dependency declares an extension target. The host discovers these by scanning the workspace's `Package.swift` for targets that depend on `KittyExtensionAPI`. This enables extensions distributed as Swift packages.

```swift
public protocol ExtensionSource: Sendable {
    func discover() async throws -> [DiscoveredExtension]
}

public struct DiscoveredExtension: Sendable {
    public let manifest: ExtensionManifest
    public let source: ExtensionSourceKind
    public let factory: @Sendable () async throws -> any Extension
}

public enum ExtensionSourceKind: Sendable {
    case compileTime                             // built into the binary
    case userDirectory(path: String)             // ~/.kittycode/extensions/
    case workspaceLocal(path: String)            // .kittycode/extensions/
    case spmPackage(packageName: String)         // future: SwiftPM dependency
    case wasm(path: String)                      // future: WASM bundle
}
```

**Extension directory structure:**

```
~/.kittycode/extensions/
    com.example.swiftSupport/
        extension.json              # manifest
        grammars/
            swift/
                grammar.json        # tree-sitter grammar definition
                highlights.scm      # highlight queries
                injections.scm      # injection queries
        themes/
            monokai-swift.json      # theme definition
        snippets/
            swift.json              # snippet definitions
        extension.wasm              # future: WASM module
```

---

#### 7. Capability-Based Security

Extensions declare the capabilities they require in their manifest. The host prompts the user to approve capabilities on first activation. Approved capabilities are persisted in `~/.kittycode/extension-permissions.json`.

```swift
public struct RequiredCapabilities: Codable, Sendable {
    public let fileSystem: FileSystemCapability?
    public let process: ProcessCapability?
    public let network: NetworkCapability?
    public let clipboard: Bool?
    public let environment: Bool?                // access to environment variables
}

public struct FileSystemCapability: Codable, Sendable {
    public let readOnly: [String]?               // glob patterns for read access
    public let readWrite: [String]?              // glob patterns for read/write access
}

public struct ProcessCapability: Codable, Sendable {
    public let spawn: [String]?                  // allowed executable names
}

public struct NetworkCapability: Codable, Sendable {
    public let allowedHosts: [String]?           // ["api.github.com", "registry.npmjs.org"]
}
```

**Enforcement.** In Phases 1-3 (compile-time and trusted extensions), capability declarations are informational — the host logs what each extension accesses but does not enforce sandboxing. In Phase 5 (WASM sandboxing), the WASM runtime enforces capabilities at the host function import level: a WASM extension that did not declare `process.spawn: ["swift"]` cannot invoke the process-spawn host function for `swift`.

**Trust levels:**

| Level | Source | Capabilities | Enforcement |
|-------|--------|-------------|-------------|
| Trusted | Compile-time SPM target | Unrestricted | None (same process) |
| Semi-trusted | User-installed bundle with manifest | Declared in manifest | Logged, future: enforced |
| Workspace-local | `.kittycode/extensions/` | Declared in manifest | Logged, user-prompted |
| Untrusted | WASM module (Phase 5) | Declared in manifest | Hard-enforced via WASM sandbox |

---

#### 8. WASM Sandboxing Roadmap

WASM sandboxing is the long-term answer for running untrusted third-party extensions safely. It is not needed until Phase 4 establishes an ecosystem, but the extension API must be designed from Phase 1 to be WASM-projectable.

##### Design Constraints for WASM Compatibility (enforced from Phase 1)

1. **All API calls are `async`.** WASM host function calls are inherently async from the host's perspective — the host calls into the WASM module, which may call back into the host via imported functions.

2. **All data crossing the API boundary is `Codable & Sendable`.** Data must be serializable into WASM linear memory. JSON or MessagePack encoding over the WASM boundary.

3. **No closures cross the API boundary.** Closures cannot be serialized into WASM memory. Event handlers are registered through subscription IDs, not closure parameters.

4. **No mutable references.** WASM guests cannot hold mutable references to host objects. `DocumentSnapshot` is a value type, not a reference to a live buffer.

5. **No inheritance or class-based protocols.** WASM guests implement interfaces via exported functions, not class vtables.

##### WASM Runtime Architecture (Phase 5)

```
 +------------------+     JSON-RPC / MessagePack     +-------------------+
 |  ExtensionHost   | <---------------------------> | WASM Sandbox      |
 |  (Swift actor)   |     over WASM host imports    | (Wasmtime/WAMR)   |
 |                  |                                |                   |
 |  EditorBridge    |     Host-imported functions:   | extension.wasm    |
 |  CommandRegistry |     - kc_getActiveDocument()   | (compiled from    |
 |  EventBus        |     - kc_applyEdits()          |  Swift/Rust/Zig)  |
 |  ContribRegistry |     - kc_executeCommand()      |                   |
 +------------------+     - kc_showMessage()         +-------------------+
                          - kc_getConfig()
                          - kc_emitDiagnostics()

                          Guest-exported functions:
                          - ext_activate()
                          - ext_deactivate()
                          - ext_provideCompletions()
                          - ext_provideHover()
                          - ext_onFileOpened()
                          - ext_executeCommand()
```

The host-imported functions correspond 1:1 to `ExtensionContext` methods. The guest-exported functions correspond to provider protocol methods. A code generator produces the WASM import/export bindings from the Swift protocol definitions, ensuring the in-process and WASM paths are always in sync.

**Resource limits.** Each WASM sandbox has configurable limits: memory (default 64MB), CPU time per call (default 5s), total fuel (instruction count budget), stack depth. Exceeding a limit terminates the call and returns an error to the host. The extension is not killed — it is quarantined and the user is notified.

**Swift-to-WASM compilation.** The Swift toolchain's experimental WASM target (`swift build --triple wasm32-unknown-wasi`) compiles Swift extensions to WASM. A `kittycode ext build` command wraps this workflow. Extension authors write Swift against `KittyExtensionAPI`, compile to WASM, and distribute the `.wasm` binary. The host loads it with Wasmtime.

---

#### 9. Hot Reload for Extension Development

Extension authors need a fast development cycle: edit code, see changes immediately, without restarting the editor.

##### Compile-Time Extensions (Phase 1-3)

For SPM-based extensions compiled into the binary, hot reload works through file watching and incremental compilation:

1. The extension author runs `kittycode --dev-extensions <path-to-extension-target>`.
2. The host watches the extension source directory for changes.
3. On change, the host triggers `swift build` for the extension target (incremental, typically < 2s).
4. The host calls `deactivate()` on the running extension instance.
5. The host loads the recompiled dynamic library (`.dylib`) via `dlopen()`.
6. The host discovers the new `Extension` implementation, creates a fresh instance, and calls `activate()`.

This requires the extension target to be compiled as a dynamic library (`.dynamicLibrary` product type in `Package.swift`). The host links against the extension's protocol conformances, not its concrete types.

##### External Bundle Extensions (Phase 3+)

For extensions that contribute only declarative resources (grammars, themes, snippets), hot reload is trivial:

1. The host watches the extension's directory for file changes.
2. On change, the host re-reads the modified resource and updates the relevant registry (e.g., re-parses a theme JSON, re-loads highlight queries).
3. The host triggers a re-render.

No deactivation/reactivation cycle is needed for pure-resource changes.

##### WASM Extensions (Phase 5)

1. The extension author runs `kittycode ext watch` in their extension project.
2. On source change, `swift build --triple wasm32-unknown-wasi` recompiles the WASM module.
3. The host detects the `.wasm` file change, spins down the old sandbox, and spins up a new one with the updated module.

---

#### 10. ContributionRegistry: The Central Index

The `ContributionRegistry` is the queryable index of all contributions from all extensions — both from parsed manifests (pre-activation) and from registered providers (post-activation). It is the single place the editor core queries to find out what commands exist, what themes are available, what sidebar panes are registered, what status bar items should be rendered, etc.

```swift
public actor ContributionRegistry {
    // Pre-activation: declarative contributions from manifests
    private var declaredCommands: [String: (CommandDeclaration, String)] = [:]    // commandId -> (declaration, extensionId)
    private var declaredThemes: [String: (ThemeDeclaration, String)] = [:]
    private var declaredLanguages: [String: (LanguageDeclaration, String)] = [:]
    private var declaredSidebarPanes: [SidebarPaneDeclaration] = []
    private var declaredStatusBarItems: [StatusBarItemDeclaration] = []
    private var declaredKeybindings: [KeybindingDeclaration] = []
    private var declaredMenuItems: [MenuContributionDeclaration] = []

    // Post-activation: live provider instances
    private var languageProviders: [String: any LanguageProvider] = [:]        // languageId -> provider
    private var diagnosticProviders: [any DiagnosticProvider] = []
    private var themeProviders: [any ThemeProvider] = []
    private var sidebarProviders: [any SidebarProvider] = []
    private var statusBarProviders: [any StatusBarProvider] = []
    private var decorationProviders: [any DecorationProvider] = []
    private var formatterProviders: [String: [any FormatterProvider]] = [:]    // languageId -> providers
    private var completionProviders: [String: [any CompletionProvider]] = [:]  // languageId -> providers
    private var hoverProviders: [String: [any HoverProvider]] = [:]           // languageId -> providers
    private var codeActionProviders: [String: [any CodeActionProvider]] = [:]  // languageId -> providers
    private var documentTransformers: [any DocumentTransformer] = []

    // Registration from manifest (pre-activation)
    public func registerFromManifest(_ manifest: ExtensionManifest) { ... }

    // Registration from live providers (post-activation)
    public func registerLanguageProvider(_ provider: any LanguageProvider) { ... }
    public func registerDiagnosticProvider(_ provider: any DiagnosticProvider) { ... }
    // ... one register method per provider type

    // Queries (used by editor core during rendering and input handling)
    public func allCommands() -> [CommandDeclaration] { ... }
    public func command(id: String) -> (CommandDeclaration, String)? { ... }
    public func allThemes() -> [ThemeDeclaration] { ... }
    public func sidebarPanes() -> [SidebarPaneDescriptor] { ... }
    public func statusBarItems(alignment: StatusBarAlignment) -> [StatusBarItemDescriptor] { ... }
    public func keybindings() -> [KeybindingDescriptor] { ... }
    public func menuItems(for location: MenuLocation, context: ContextKeySet) -> [MenuContribution] { ... }
    public func languageProvider(for languageId: String) -> (any LanguageProvider)? { ... }
    public func diagnosticProviders(for languageId: String) -> [any DiagnosticProvider] { ... }
    public func decorationProviders(for document: DocumentSnapshot) -> [any DecorationProvider] { ... }
    public func completionProviders(for languageId: String) -> [any CompletionProvider] { ... }
    public func hoverProviders(for languageId: String) -> [any HoverProvider] { ... }
    public func codeActionProviders(for languageId: String) -> [any CodeActionProvider] { ... }
    public func formatters(for languageId: String) -> [any FormatterProvider] { ... }
    public func documentTransformers(for languageId: String, trigger: TransformTriggerSet) -> [any DocumentTransformer] { ... }

    // Unregistration (on extension deactivation)
    public func unregisterAll(extensionId: String) { ... }
}
```

---

#### 11. CommandRegistry: The Command System

The command system is the single most important architectural component. Every user-facing action in KittyCode — built-in or extension-contributed — must be a command.

```swift
public actor CommandRegistry {
    private var commands: [String: CommandRegistration] = [:]
    private var pendingCommands: [String: String] = [:]  // commandId -> extensionId (not yet activated)

    /// Register a live command handler
    public func register(_ registration: CommandRegistration) {
        commands[registration.descriptor.id] = registration
        pendingCommands.removeValue(forKey: registration.descriptor.id)
    }

    /// Register a pending command from a manifest (extension not yet activated)
    public func registerPending(commandId: String, extensionId: String) {
        if commands[commandId] == nil {
            pendingCommands[commandId] = extensionId
        }
    }

    /// Unregister all commands from an extension
    public func unregister(extensionId: String) {
        commands = commands.filter { $0.value.extensionId != extensionId }
    }

    /// Execute a command. If the command is pending (extension not activated),
    /// trigger activation first, then execute.
    public func execute(id: String, args: CommandArgs? = nil) async throws -> CommandResult {
        if let registration = commands[id] {
            return try await registration.handler(args)
        }
        if let extensionId = pendingCommands[id] {
            // Trigger lazy activation via the extension host
            await extensionHost.activate(extensionId: extensionId)
            // Retry after activation
            if let registration = commands[id] {
                return try await registration.handler(args)
            }
        }
        throw CommandError.unknownCommand(id)
    }

    /// List all known commands (both live and pending)
    public func allCommands() -> [CommandDescriptor] {
        var descriptors = commands.values.map(\.descriptor)
        // Include pending commands with descriptors from the ContributionRegistry
        return descriptors
    }

    /// Fuzzy search for the command palette
    public func search(query: String) -> [CommandDescriptor] {
        allCommands().filter { fuzzyMatch(query, $0.title) || fuzzyMatch(query, $0.id) }
            .sorted { score($0, query) > score($1, query) }
    }
}

public struct CommandRegistration: Sendable {
    public let descriptor: CommandDescriptor
    public let extensionId: String
    public let handler: @Sendable (CommandArgs?) async throws -> CommandResult
}
```

**Migration path from current codebase.** The 24 hardcoded shortcuts in `EventHandling.swift` become 24 `CommandRegistration` entries. The 13 `ContextMenuAction` cases become 13 more. Every `EditorState` method that represents a user action (`save`, `copy`, `paste`, `undo`, `redo`, `toggleLineNumbers`, `toggleSidebar`, `newFile`, `closeTab`, etc.) is wrapped in a command. The total initial command count is approximately 60-80 commands, all registered by the `com.kittycode.core` built-in extension.

**Command palette.** The command palette is a UI component that:
1. Lists all registered commands filtered by their `enablement` condition evaluated against the current `ContextKeySet`.
2. Supports fuzzy search by title and category.
3. Shows keybinding hints next to each command.
4. Is itself triggered by a command (`kittycode.commandPalette.show`), bound to `Ctrl+Shift+P`.
5. Extensions get discoverability for free — every registered command appears in the palette.

---

#### 12. Extension Configuration and Settings

Extensions contribute settings schemas that integrate with KittyCode's existing JSON configuration system (`~/.kittycode.json`).

**Settings namespace.** Extension settings live under `extensions.<extensionId>.settings`:

```json
{
    "editor": { ... },
    "theme": { ... },
    "extensions": {
        "com.kittycode.git": {
            "settings": {
                "enableGutterDecorations": true,
                "fetchOnStartup": false
            }
        },
        "com.example.swiftlint": {
            "settings": {
                "enabled": true,
                "configPath": ".swiftlint.yml",
                "lintOnSave": true
            }
        }
    }
}
```

**Schema validation.** The host validates setting values against the `ConfigurationSchema` declared in the manifest. Invalid values are replaced with defaults and logged as warnings. Setting changes emit `WorkspaceEventKind.configurationChanged` events.

**Settings cascade.** Resolution priority: workspace config (`.kittycode/config.json`) > user config (`~/.kittycode.json`) > extension-declared defaults. This extends the existing config hierarchy to extension-contributed settings.

**Typed access.** Extensions read settings through `ExtensionContext`:

```swift
// In extension code:
let lintOnSave: Bool = await context.getSetting("lintOnSave", default: true)
await context.subscribeToConfigChange(section: "lintOnSave") { newValue in
    // reconfigure the linter
}
```

---

#### 13. Built-in Features as Extensions

The most important architectural constraint: every existing feature must be re-expressible through the extension API. If a built-in feature cannot be expressed as an extension, the API is incomplete.

**`com.kittycode.core`** — the core editor extension:
- **CommandProvider**: registers all 60-80 built-in commands (save, copy, paste, undo, redo, find, replace, toggle sidebar, toggle line numbers, switch mode, navigate tabs, etc.)
- **KeybindingProvider**: registers all 24 current keyboard shortcuts plus vim normal/insert mode bindings
- **MenuProvider**: registers all context menu entries (replacing the 13-case `ContextMenuAction` enum)

**`com.kittycode.explorer`** — the file explorer extension:
- **SidebarProvider**: provides the file explorer pane (replacing `SidebarPanel.explorer`) and the open documents pane (replacing `SidebarPanel.openDocuments`)
- **CommandProvider**: registers file operations (new file, new folder, rename, delete, duplicate, move)
- **WorkspaceEventListener**: listens for file create/delete/rename to refresh the tree

**`com.kittycode.git`** — the git integration extension:
- **DecorationProvider**: provides file decorations (M/U/A badges in the tree) and gutter decorations (git line status)
- **StatusBarProvider**: provides the git branch status bar item (replacing `StatusBarConfig.Item.git`)
- **CommandProvider**: registers git commands (stage, unstage, commit, diff, blame)
- **WorkspaceEventListener**: refreshes decorations on save, branch switch, etc.

**`com.kittycode.defaultTheme`** — the default theme extension:
- **ThemeProvider**: provides the default dark and light themes (replacing the hardcoded `ColorScheme` in `EditorStateCore.swift` and the 45+ theme color properties)

**`com.kittycode.languages`** — the bundled language pack:
- **LanguageProvider**: registers all languages from `languages.json` via `GrammarRegistry`
- Subsumes the current `BundledLanguageManifest` and `SyntaxArtifactsCache` pipeline

**`com.kittycode.statusBar`** — the built-in status bar items:
- **StatusBarProvider**: registers the 9 default items (`path`, `file`, `status`, `language`, `size`, `lineEnding`, `git`, `position`, `visibility`) as dynamic status bar segments

This decomposition validates the API surface and ensures that the extension system is not a second-class citizen — it is the only way features are expressed.

---

#### 14. Codebase Migration Steps

The migration from the current architecture to the extension platform is executed in a specific order to minimize risk and maintain a working editor at every step.

**Step 1: Create the `KittyExtensionAPI` SPM target.**

Add a new library target to `Package.swift` that exports all provider protocols, value types, and the `Extension` base protocol. This target has zero dependencies on editor internals. It becomes the single import for all extension code.

```
Package.swift targets (current: ~15 targets):
  + KittyExtensionAPI  (protocols, value types, no internal dependencies)
  + KittyExtensionHost (ExtensionHost actor, ContributionRegistry, CommandRegistry, EventBus)
```

**Step 2: Implement `CommandRegistry` and the command palette.**

Create the `CommandRegistry` actor. Wrap every existing action in `EventHandling.swift` (24 shortcuts), `EditorContextMenu.swift` (13 `ContextMenuAction` cases), and other action sites as `CommandRegistration` entries. Replace the `switch` dispatching in `EventHandling.swift` with keybinding resolution through `CommandRegistry`. Delete the `ContextMenuAction` enum. Implement a minimal command palette UI (a filtered list of commands, triggered by `Ctrl+Shift+P`).

**Step 3: Implement `ContributionRegistry` and convert closed enums.**

Replace `SidebarPanel` (2-case closed enum in `EditorStateCore.swift:293`) with `ContributionRegistry.sidebarPanes()`. Replace `StatusBarConfig.Item` (9-case closed enum in `Config.swift:127`) with `ContributionRegistry.statusBarItems()`. Update `RenderActivityBar.swift`, `StatusBar.swift`, and `RenderTree.swift` to iterate over registry entries instead of switching on enums.

**Step 4: Implement `EventBus` and wire workspace events.**

Add `eventBus.emit()` calls at every state transition in `EditorState`: file open (in `WorkspaceFileLoading.swift`), file save (in `EditorStateFileSystem.swift`), active tab change (in `BufferManager`), mode switch (in `EditorInput.swift`), config change (in `Config.swift`). This is additive — it does not change existing behavior, it only adds event emission alongside it.

**Step 5: Define the `Extension` protocol and implement `ExtensionHost`.**

Create the `Extension` protocol, `ExtensionContext` implementation, `ExtensionHost` actor, and `EditorStateBridge` concrete bridge. Package the existing built-in features as extension instances (`com.kittycode.core`, `com.kittycode.explorer`, `com.kittycode.git`, `com.kittycode.defaultTheme`, `com.kittycode.languages`, `com.kittycode.statusBar`). Verify the editor functions identically to before.

**Step 6: Wire `GrammarRegistry` into the runtime.**

Replace `BundledLanguageManifest.entry(forFilename:)` calls in `LanguageHighlighter` with `GrammarRegistry.entry(forExtension:)`. Bootstrap built-in languages as `GrammarRegistry.register()` calls on startup. Move the `externals` check into `GrammarRegistry.compiledResult()`. Keep `SyntaxArtifactsCache` as a caching layer.

**Step 7: Wire `FocusEngine` into sidebar panes.**

The `FocusEngine` struct in `Sources/KittyWidgets/FocusEngine.swift` is currently a minimal ring buffer that is unused. Wire it into the sidebar pane system: each `SidebarPaneController` declares its `focusTargets()`, and the `FocusEngine` manages tab-order navigation across the activity bar, sidebar panes, editor, and status bar. This completes the focus management story that was started but never connected.

**Step 8: Implement external bundle discovery (Phase 3).**

Add `UserDirectoryExtensionSource` and `WorkspaceExtensionSource` implementations. Parse `extension.json` manifests. Support declarative-only contributions initially (languages, themes, keybindings, snippets). No executable code in external bundles yet.

**Step 9: Implement the extension CLI (Phase 4).**

Add `kittycode ext install <id>`, `kittycode ext remove <id>`, `kittycode ext list`, `kittycode ext update` subcommands to the CLI argument parser in `Sources/KittyCode/`. Extensions are downloaded from a registry (initially a Git repository, later a dedicated service) and installed to `~/.kittycode/extensions/`.

**Step 10: WASM sandbox integration (Phase 5).**

Add a SwiftPM dependency on a Wasmtime Swift binding. Implement `WasmExtensionSource` that loads `.wasm` modules. Generate host-import bindings from the `ExtensionContext` protocol. Generate guest-export bindings from the provider protocols. Enforce capability-based security at the host-import level. This is the final step — everything before it is prerequisite infrastructure.

---

#### 15. Phased Rollout Summary

| Phase | Scope | Extension Source | Isolation | Capabilities |
|-------|-------|-----------------|-----------|-------------|
| 1 | Command system, provider protocols, built-in re-expression | Compile-time only | In-process | All 16 provider protocols, command palette, keybinding resolver |
| 2 | Additional compile-time extension packages | SPM targets | In-process | External SPM targets contribute languages, themes, commands |
| 3 | External extension bundles | `~/.kittycode/extensions/`, workspace `.kittycode/extensions/` | In-process, logged capabilities | Declarative contributions (languages, themes, keybindings, snippets) |
| 4 | Extension marketplace/registry | Remote registry + local install | In-process, prompted capabilities | `kittycode ext install/remove/update`, dependency resolution |
| 5 | WASM sandboxing | WASM modules in bundles | Wasmtime sandbox, hard-enforced capabilities | Full API surface projected into WASM guests, resource limits, memory isolation |

**Phase 1 is the hardest phase.** It is a large refactor with zero user-visible change. The editor must function identically to today at the end of Phase 1, but with fully extensible internals. Every subsequent phase builds incrementally on this foundation.

**The critical design invariant across all phases:** the extension API is designed from Phase 1 to be projectable into a WASM guest. All calls are async, all boundary types are `Codable & Sendable`, no closures or mutable references cross the API boundary. If these constraints are maintained, Phase 5 is a change in execution substrate, not an API redesign.

---

### SOTA Review and Accuracy Assessment

This section evaluates the technical claims and architectural decisions in this ADR against current state-of-the-art knowledge from established editor extension systems and relevant industry practice.

#### 1. VS Code Extension Model: Accuracy of Characterization

**Claim in ADR:** Detailed description of VS Code's Extension Host process isolation, JSON manifest, activation events, and API surface.

**Accuracy:** The characterization is **substantially correct**. VS Code's Extension Host is indeed a separate Node.js process communicating via JSON-RPC IPC with the renderer. The activation events listed (`onLanguage`, `onCommand`, `workspaceContains`, `onFileSystem`, `onView`, `*`) are accurate — VS Code also supports `onUri`, `onWebviewPanel`, `onCustomEditor`, `onNotebook`, `onAuthenticationRequest`, and `onStartupFinished` (added in VS Code 1.55). The API surface description is accurate.

**One correction:** The ADR states "Process isolation is less relevant for a terminal editor (no Electron renderer to protect)." This understates the value of process isolation. Even in a terminal editor, a misbehaving extension that blocks the event loop or leaks memory will degrade the entire editor. VS Code's isolation also enables **remote development** (extensions run on a remote machine, UI runs locally), which is increasingly relevant. The claim should be softened to "process isolation provides different tradeoffs for a terminal editor" rather than "less relevant."

#### 2. WASM Performance: "Near-Native" Qualification

**Claim in ADR:** The WASM sandboxing roadmap implies WASM extensions will have competitive performance with in-process extensions.

**Accuracy:** WASM execution via Wasmtime typically incurs **~30-100 microseconds per host function call** due to context switching between the WASM guest and the host. For coarse-grained API calls (e.g., "provide completions for this position"), this overhead is negligible. For fine-grained calls (e.g., per-character syntax queries, per-line decoration computations), the overhead becomes significant.

**Assessment:** The ADR's design — where all provider protocol methods are coarse-grained async calls returning batched results — is **well-suited for WASM projection**. The `provideCompletions()`, `provideHover()`, `provideDiagnostics()` pattern naturally produces calls that are infrequent (user-triggered or debounced) and return bulk data. However, the `DocumentChangeEvent` stream could generate high-frequency calls on rapid typing. The ADR should recommend **batching/debouncing document change events** before delivering them to WASM guests. Zed addresses this by having the WASM guest poll for changes rather than receiving a push stream.

#### 3. Zed WASM Extension Model

**Claim in ADR:** Describes Zed's sandboxed WASM execution, `extension.toml` manifest, and deliberately narrow contribution surface.

**Accuracy:** Correct. Zed uses Wasmtime with capability-based access control. The contribution surface is indeed limited to languages (Tree-sitter grammars + queries), themes, and slash commands. Zed does not support arbitrary UI contributions from extensions.

**Additional context:** As of early 2025, Zed has been expanding its extension API to include context servers (for AI features) and exploring broader extension capabilities, but the core model remains intentionally constrained. Zed's approach validates that a narrow, well-designed extension surface can deliver significant value — most users primarily need language support and themes. The long tail of VS Code-style extensions (custom panels, webviews, decorations) serves power users and enterprise scenarios.

**Assessment:** The ADR's position — "aim for VS Code-breadth contributions with Zed-quality sandboxing" — is ambitious but well-reasoned for a long-term vision. The phased approach (compile-time first, WASM later) correctly defers the hardest problem (WASM host function projection) until the API surface is stabilized through in-process usage.

#### 4. IntelliJ Extension Points Model

**Claim in ADR:** Describes IntelliJ's typed extension points, service system, PSI, and action system.

**Accuracy:** The characterization is accurate. IntelliJ's `com.intellij.extensionPoint` declarations in `plugin.xml` are indeed typed slots with schema validation. The service system does provide application/project/module scoping with lazy instantiation. PSI is correctly characterized as a typed AST framework. The action system is correctly described as the universal command mechanism.

**Additional context:** IntelliJ's extension model has evolved significantly with the introduction of **Extension Points v2** (dynamic extension loading/unloading) and **Light Services** (annotation-based service registration without XML). The move toward annotation-driven registration over XML mirrors the ADR's approach of using Swift protocol conformance for provider discovery — both reduce boilerplate and improve type safety.

#### 5. Helix Static Model

**Claim in ADR:** Describes Helix's `languages.toml` configuration and lack of runtime extension loading.

**Accuracy:** Correct. Helix compiles grammars at build/install time and has no plugin system. The characterization of this as "simplicity as a feature" is apt.

**Additional context:** As of 2025, the Helix community has ongoing discussions about adding a plugin system (potentially Scheme-based, inspired by Guile), but no implementation has landed. The absence of a plugin system remains Helix's most frequently cited limitation in community surveys, validating the ADR's position that extensibility is necessary for KittyCode's broader ambitions.

#### 6. Scope and Ambition Assessment

**Claim in ADR:** 16 provider protocols, 5-phase rollout, full command system, WASM sandboxing.

**Assessment:** This is an **extremely ambitious** design document. The 16 provider protocols cover a surface area comparable to VS Code's extension API, which was developed over ~10 years by a large team. Key risk factors:

- **Phase 1 is correctly identified as the hardest phase.** Re-expressing all built-in features as extension contributions is a massive refactor that touches every subsystem. The ADR lists 10 implementation steps for Phase 1 alone. This is likely **several person-months** of work for a single developer.

- **The 16 provider protocols are well-designed individually** but collectively represent a very large API surface to stabilize. Consider prioritizing: `CommandProvider`, `LanguageProvider`, `ThemeProvider`, `DiagnosticProvider`, and `KeybindingProvider` are essential. `SidebarProvider`, `StatusBarProvider`, and `CompletionProvider` are high-value. The remaining 8 (`HoverProvider`, `FormattingProvider`, `CodeActionProvider`, `SnippetProvider`, `TaskProvider`, `TerminalProvider`, `CodeLensProvider`, `DebugProvider`) could be deferred to later phases without blocking the core extensibility story.

- **WASM sandboxing (Phase 5)** requires a mature Swift-to-Wasmtime binding. As of 2025, the Swift WASM ecosystem is maturing (SwiftWasm, Wasmtime's C API via Swift bridging) but is not yet production-hardened for the bidirectional host-function-import pattern described. This is correctly placed as the final phase.

#### 7. EditorBridge Design

**Claim in ADR:** The `EditorBridge` protocol decouples extensions from `EditorState`.

**Assessment:** This is the **single most important architectural decision** in the ADR and it is well-designed. The bridge pattern (also called "anti-corruption layer" in domain-driven design) is the standard approach for decoupling extension systems from editor internals. VS Code's `ExtHostCommands`, `ExtHostDocuments`, `ExtHostEditors` etc. serve the same role — they are typed bridges between the Extension Host and the renderer.

**One concern:** The `EditorBridge` protocol has 18 methods. As the API grows, consider splitting it into focused sub-protocols (`DocumentBridge`, `WorkspaceBridge`, `UIBridge`, `ConfigurationBridge`) that can be independently evolved and tested. This also enables finer-grained capability control — a language extension needs `DocumentBridge` but not `UIBridge`.

#### 8. EventBus Design

**Claim in ADR:** An event bus for workspace events (file open, save, active tab change, etc.).

**Assessment:** The event bus pattern is standard and appropriate. However, the ADR should address **event ordering guarantees**. In VS Code, events are delivered in a defined order: `onWillSaveTextDocument` fires before the save, allowing extensions to modify the document (e.g., format-on-save); `onDidSaveTextDocument` fires after. The ADR's `WorkspaceEvent` enum includes `.didSave` but not `.willSave`. Consider whether pre-events (will-events) are needed for format-on-save, pre-commit hooks, and similar workflows.

#### 9. Contribution Manifest: JSON vs Swift

**Claim in ADR:** Compile-time extensions use a Swift `manifest` property; external bundles use `extension.json`.

**Assessment:** This dual-format approach is pragmatic. The Swift manifest benefits from type checking and IDE support; the JSON manifest enables external tooling and non-Swift contributions. The ADR correctly notes that both formats express the same `ExtensionManifest` structure.

**Consideration:** VS Code's experience shows that **manifest validation errors are the #1 cause of extension installation failures**. Invest in clear, actionable error messages for malformed `extension.json` files. Consider providing a `kittycode ext validate` command that checks a manifest without installing.

#### Overall Assessment

**Accuracy: HIGH.** The characterizations of VS Code, Neovim, Zed, IntelliJ, and Helix are substantially correct with minor qualifications noted above. The architectural design is well-informed by these precedents.

**Strengths:**
- The phased rollout correctly sequences complexity (compile-time → bundles → WASM)
- The `EditorBridge` decoupling is architecturally sound
- The WASM-projectable design constraint (`Codable & Sendable`, all async) is forward-thinking
- The activation event system correctly mirrors VS Code's proven lazy-loading pattern
- The provider protocol design produces naturally coarse-grained APIs suitable for future IPC/WASM boundaries

**Risk areas:**
- **Scope:** 16 provider protocols + WASM sandboxing is a multi-year effort. Prioritize ruthlessly — ship extensible commands and languages first, add the remaining providers incrementally based on demand.
- **Phase 1 underestimation:** Re-expressing built-in features as extensions while maintaining behavioral parity is historically the most error-prone phase of extension system adoption (VS Code, Eclipse, and IntelliJ all had painful transitions).
- **API stability:** Once external extensions depend on provider protocols, breaking changes become very costly. Consider a formal API stability policy (e.g., `@_spi(Experimental)` for unstable protocols) before Phase 3.
- **Testing surface:** Each provider protocol needs both unit tests (protocol conformance) and integration tests (full activation → provider call → result rendering). The testing infrastructure should be designed alongside the extension system, not retrofitted.
