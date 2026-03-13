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
