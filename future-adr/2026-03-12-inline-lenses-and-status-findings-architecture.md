# Future ADR: Async Inline Findings, Diagnostics, and Status Bar Architecture

Status: Proposed
Date: 2026-03-12

## Goal

Investigate how to engineer asynchronous, non-blocking inline error, warning, and info lenses with status bar reporting, plus configurable default findings for comment and documentation markers such as:

- `TODO`
- `WARNING`
- `FIXME`

The system should remain responsive during editing, avoid blocking the main render path, and make the default behavior configurable through the app config.

This ADR also adds an explicit interoperability goal:

- make the diagnostics and findings architecture easy to extend with new parsers
- make it easy to ingest common report formats and tool outputs
- make it easy to integrate tool-specific config files and suppression rules
- make it easy to emit findings to multiple reporting surfaces
- stay compatible with common ecosystem shapes used by Android Studio, Visual Studio Code, Xcode, JetBrains IDEs, and language tooling

## Product Target

The desired feature set is:

- async background computation
- non-blocking updates while typing
- inline findings or lenses near the affected line
- gutter and line-level severity cues
- status bar components for finding counts and summary
- configurable defaults and opt-in behavior
- default comment and documentation scanning for `TODO`, `WARNING`, and `FIXME`
- pluggable importers for external diagnostic formats
- pluggable config adapters for tool-specific configuration
- pluggable reporting sinks beyond the inline editor and status bar

This ADR treats "diagnostics" as the broader category and "findings" as a source within it.

## Interoperability Target

The architecture should not be tightly coupled to one tool's schema.

It should instead normalize around a KittyCode-native findings model and provide adapters for:

- live push diagnostics
- batch report imports
- compiler and linter output parsing
- tool-specific config discovery
- tool-specific severity and suppression mapping
- multiple reporting sinks

The practical interoperability baselines should be:

- LSP-style live diagnostics for VS Code style integrations
- SARIF for static-analysis interchange and archival exchange
- Android lint configuration and report formats
- Xcode result bundles and `xcresulttool`-extractable findings
- JetBrains SARIF and legacy inspection exports
- compiler-style text streams such as Clang, Swift, GCC, and MSBuild diagnostics

## Current Codebase Findings

### There is already a usable async pattern for background editor work

Two existing systems provide the right shape:

- `Sources/KittyCode/EditorStateFileSystem.swift`
  - `schedulePostLoadProcessing(for:content:)`
- `Sources/KittyWorkspace/GitDecorationManager.swift`

Both already use:

- cancellable `Task`s
- version checks against `documentVersion`
- background work followed by guarded main-thread apply

This is the strongest architectural precedent for a diagnostics manager.

### The editor already supports non-text overlays, but not inline text lenses

`Sources/KittyWidgets/TextEditor.swift` supports:

- `gutterDecorations`
- `lineStyleOverlays`
- `selectionRanges`

`Sources/KittyWidgets/TextStyleOverlay.swift` only supports:

- foreground color overlay
- background color overlay

There is no text payload in the overlay model.

### The layout engine has no concept of virtual text

`Sources/KittyWidgets/TextEditorLayout.swift` computes:

- cursor placement
- hit testing
- scroll metrics
- wrapped rows

all from real buffer text only.

This means true inline lenses cannot be added correctly as a rendering trick. A real virtual-text or adornment layer is required.

### Render integration points already exist for line and gutter state

`Sources/KittyCode/RenderEditor.swift` already composes:

- `activeGutterDecorations(...)`
- `activeLineStyleOverlays(...)`
- `activeSelectionRanges(...)`

This is enough for a first phase with:

- severity gutter marks
- line background or foreground emphasis

It is not enough for inline message text.

### Status bar rendering is currently plain-string only

`Sources/KittyCode/StatusBarContent.swift` builds a left string and right string from configured items.

`Sources/KittyWidgets/StatusBar.swift` renders:

- `left`
- `center`
- `right`
- one shared `style`

There are no:

- per-segment styles
- severity-colored counters
- diagnostic-specific segment models

### Config and theme do not yet model diagnostics

`Sources/KittyCode/Config.swift` has no diagnostics or findings config section.

The status bar item enum has no entries for diagnostics or findings counts.

The theme has no dedicated:

- error colors
- warning colors
- info colors
- TODO or FIXME colors
- lens styles

### Comment-aware infrastructure already exists

There are already several strong building blocks:

- `Sources/KittyGrammar/ParseTable.swift`
  - `CommentPattern`
- `Sources/KittyGrammar/LexTableCompiler.swift`
  - extracts comment patterns from grammar extras
- `Sources/KittyParser/GLRParser.swift`
  - inserts extra `comment` nodes into the syntax tree
- `Sources/KittyParser/SyntaxNode.swift`
  - exposes `text(from:)` and `pointRange`

This means comment-aware finding extraction is already feasible without building parsing infrastructure from scratch.

### There are already tests proving comment extraction and matching primitives

Relevant tests already exist:

- `Tests/KittyGrammarTests/LexTableCompilerCommentPatternsTests.swift`
- `Tests/KittyParserTests/GLRParserCommentNodesTests.swift`
- `Tests/KittyQueryTests/QueryMatcherTests.swift`
- `Tests/KittyQueryTests/QueryParserTests.swift`

The codebase can already identify comments and match `TODO`-style strings in parser or query layers.

### Some useful diagnostic-adjacent assets are present but unused

- `Sources/KittySymbols/TerminalSymbolTheme.swift` already includes a `warning` symbol role.
- `Sources/KittyParser/GLRParser.swift` already creates error nodes.
- `Sources/KittySyntax/Grammars/swift/grammar.json` contains `diagnostic_statement` for `#warning` and `#error`.

These are concrete examples of already-developed pieces that are not yet wired into editor findings or status reporting.

### The wider tooling ecosystem already converges on a few transport shapes

The external ecosystem is not uniform, but it is also not random. The strongest recurring shapes are:

- push-style live diagnostics with file URI plus ranges, as in LSP and VS Code
- SARIF logs for static analysis interchange
- tool-specific XML, JSON, or YAML config files for severity and suppression policy
- compiler-like line-oriented text streams
- Apple result bundles for build and test result extraction

That means KittyCode should not build one hardcoded parser per tool directly into editor code. It should build an adapter substrate.

## Gaps and Missing Features

### 1. No diagnostics or findings model exists at the editor level

There is no first-class type for:

- severity
- source
- range
- message
- inline lens text
- grouped status summary

### 2. No async manager exists for findings

There is no equivalent today of:

- `DiagnosticsManager`
- `FindingsManager`
- `DocumentFindingSnapshot`

Nothing currently schedules, caches, or applies editor findings.

### 3. No inline text rendering path exists

This is the main hard constraint.

Without a virtual text or adornment system, KittyCode can only do:

- gutter symbols
- line overlays
- status bar counts

True inline lenses require new editor rendering and layout primitives.

### 4. No status bar component model exists for diagnostics

Even if counts were computed today, the current status bar API would force them into plain text with a single shared style.

### 5. No config-backed defaults exist

There is no way today to configure:

- whether TODO scanning is enabled
- which patterns count as findings
- which severities show in the status bar
- whether inline lenses are enabled
- whether documentation comments are included
- debounce thresholds or performance limits

### 6. Comment extraction is available but not exposed as a feature API

The syntax and grammar layers already know a lot about comments, but KittyCode does not yet expose a clean service that editor features can call.

### 7. There is no fallback severity taxonomy

The app needs a consistent classification model that can unify:

- parser errors
- comment findings
- native language diagnostics like Swift `#warning`
- future external tool diagnostics

### 8. There is no interop layer for external producers, configs, or exporters

There is no current architecture for:

- importing SARIF or similar machine-readable reports
- ingesting LSP-style diagnostics
- parsing compiler-style stderr or log output
- loading tool-specific config like `lint.xml`
- exporting normalized findings to standard formats
- routing normalized findings to multiple reporting sinks

## Decision

### 1. Build a first-class asynchronous findings pipeline

KittyCode should own an in-house findings pipeline instead of bolting diagnostics directly into render code.

This pipeline should be:

- cancellable
- document-version-aware
- incremental where practical
- isolated from the main render path

### 2. Separate finding extraction from presentation

The system should distinguish:

- extraction
- aggregation
- rendering
- status reporting

That keeps comment scanners, parser diagnostics, and future external providers reusable.

### 3. Ship in phases, not all at once

The right staged approach is:

1. async findings model and status summary
2. gutter plus line-level visual surfacing
3. true inline lenses after virtual text exists

### 4. Hardcode sensible defaults, then make them configurable

The default finding patterns should ship as:

- `TODO`
- `FIXME`
- `WARNING`

These should map to default severities and be configurable through the app config.

### 5. Treat comment findings as one source inside a broader diagnostics system

This avoids painting the architecture into a corner. TODO scanning is valuable, but the same pipeline should later accept:

- parser-derived errors
- native language warnings
- external linter results

### 6. Make interoperability a first-class design objective

The system should be easy to extend for:

- new input formats
- new config formats
- new tool adapters
- new output sinks

This should be achieved with stable protocols and a normalized internal schema, not with feature-specific branches inside editor code.

### 7. Normalize around KittyCode's model, not one external schema

KittyCode should not adopt SARIF, LSP, Android lint XML, or `.xcresult` as its internal storage model.

Instead:

- use a KittyCode-native normalized model internally
- provide import and export adapters for common external formats

This preserves internal clarity while still enabling interoperability.

### 8. Use LSP and SARIF as the primary interoperability baselines

If KittyCode supports only two major external shapes first, they should be:

- LSP-style diagnostics for live editor interoperability
- SARIF for batch interchange and persisted analysis exchange

This gives strong coverage across VS Code, JetBrains tooling, CI systems, GitHub code scanning, Android lint SARIF outputs, and various static analyzers.

## Proposed Architecture

### New target

Add a new target:

- `Sources/KittyDiagnostics`

Suggested dependencies:

- `KittySyntax`
- `KittyParser`
- `KittyGrammar`
- `KittyText`
- `KittySync`

Keep render integration in `KittyCode`.

### Core types

Suggested model types:

- `FindingSeverity`
- `FindingSource`
- `FindingKind`
- `FindingPattern`
- `DocumentFinding`
- `DocumentFindingSummary`
- `DocumentFindingsSnapshot`
- `InlineLensModel`
- `DiagnosticsConfig`

Suggested interop-facing model types:

- `DiagnosticAdapterID`
- `DiagnosticTransportKind`
- `DiagnosticOrigin`
- `DiagnosticRuleDescriptor`
- `DiagnosticLocation`
- `DiagnosticRelatedLocation`
- `DiagnosticFix`
- `DiagnosticCodeFlow`
- `DiagnosticFingerprint`
- `NormalizedDiagnosticEnvelope`

Suggested severity set:

- `error`
- `warning`
- `info`
- `task`

`task` is useful for TODO-like comment markers without pretending they are parser warnings.

### Normalized schema requirements

The internal normalized model should be rich enough to represent what common IDEs and analysis tools expose.

Minimum fields should include:

- tool id
- source kind
- rule id
- severity
- message
- primary location
- optional range
- related locations
- optional quick fixes
- tags or category
- stable fingerprint when available
- raw metadata payload for adapter-specific details

This is the minimum needed to map cleanly from:

- LSP diagnostics
- SARIF results
- Android lint findings
- Xcode build or test failures
- JetBrains inspection results
- compiler stderr parsers

### Extraction lanes

#### Comment finding lane

Primary goal:

- scan comments and documentation comments for configured markers

Preferred order:

1. parser-backed comment nodes when grammar artifacts are available
2. grammar-derived comment-pattern scan when parser-backed extraction is unavailable
3. plain text fallback only for unknown languages or disabled grammar loading

This gives the feature a good accuracy/performance tradeoff without blocking on universal AST support.

#### Parser diagnostic lane

Use parser information to detect:

- syntax error nodes
- language-specific diagnostic constructs where easy and reliable

Examples:

- Swift `#warning`
- Swift `#error`

#### Future external-provider lane

Reserve an interface for future integrations such as:

- compiler diagnostics
- linter output
- language server output

This ADR does not require those integrations now.

### Interop adapter layer

Add a formal adapter boundary inside `KittyDiagnostics`.

Suggested protocols:

- `DiagnosticProducer`
  - produces live findings from in-process or async analyzers
- `DiagnosticImporter`
  - ingests file-based or stream-based external reports
- `DiagnosticConfigAdapter`
  - discovers and parses external configuration files
- `DiagnosticExporter`
  - writes normalized findings to external formats
- `DiagnosticSink`
  - consumes normalized findings for UI or machine-facing presentation

Suggested registry types:

- `DiagnosticAdapterRegistry`
- `DiagnosticAdapterManifest`
- `DiagnosticCapabilitySet`

Each adapter should declare capabilities such as:

- supports live updates
- supports workspace scope
- supports file scope
- supports fixes
- supports code flows
- supports config discovery
- supports severity remapping
- supports export

### Recommended first-party adapters

The first extensibility targets should be:

- `LSPDiagnosticAdapter`
- `SARIFImporter`
- `SARIFExporter`
- `CompilerOutputAdapter`
- `AndroidLintConfigAdapter`
- `AndroidLintReportAdapter`
- `XCResultAdapter`
- `JetBrainsInspectCodeAdapter`

Not all need to ship in the same milestone, but the architecture should make each of them straightforward to add.

### Config adapter model

Tool configuration should not be baked into core finding extraction.

Instead, config adapters should normalize tool configuration into a KittyCode policy layer such as:

- severity overrides
- rule enables or disables
- suppression scopes
- include or exclude paths
- category toggles

This makes it possible to interpret external config files like:

- `lint.xml`
- tool JSON or YAML rule config
- future `.editorconfig`-style diagnostic keys
- future project-local diagnostics config files

### Path and URI normalization

Interop is fragile unless file references normalize consistently.

The adapter layer therefore needs:

- workspace-root-relative path mapping
- URI to local path mapping
- symlink-aware canonicalization
- line and column normalization
- source-root remapping for imported reports

Without this, imported findings from external tools will not anchor reliably to the open buffer model.

### Execution model

Use a manager patterned after `GitDecorationManager` and `schedulePostLoadProcessing(...)`.

Suggested behavior:

- cancel prior task on edit
- debounce short bursts of typing
- capture `documentVersion`
- compute findings off the main actor
- apply only if the buffer path and version still match

Suggested manager names:

- `DiagnosticsManager`
- `DocumentFindingsCoordinator`

For imported or external reports, the manager should also support:

- report snapshot ingestion
- merge or replace policy per tool
- workspace-level summary recomputation
- stale-provider eviction

### Rendering strategy

#### Phase 1 presentation

Support:

- gutter severity markers
- line style overlays
- status bar counts

This can ship on the current editor widget stack.

#### Phase 2 presentation

Add a true virtual text layer to `TextEditor`.

Suggested new concepts:

- `InlineAdornment`
- `VirtualTrailingText`
- `LineAdornmentLayout`

The layout rules need to preserve:

- cursor model coordinates against real buffer text
- hit testing against real buffer text
- wrap calculations that are aware of optional displayed adornments

If this layer is not added, the feature should not claim to support real inline lenses.

### Reporting sinks

The architecture should support more than one presentation target.

Recommended sinks:

- inline lens sink
- gutter sink
- line overlay sink
- status bar sink
- future problems list sink
- export sink for machine-readable reports
- terminal log sink for command-driven workflows

This matters because Android Studio, VS Code, Xcode, and JetBrains products all expose diagnostics through more than one surface:

- in-editor markers
- summaries
- issue lists
- navigable problem panes
- machine-readable output

### Status bar evolution

The current `StatusBar` string API is too narrow for proper diagnostic reporting.

Recommended next-step model:

- `StatusBarSegment`
- `StatusBarSegmentStyle`
- `StatusBarPayload`

This enables:

- colored severity counters
- compact or expanded summaries
- optional warning symbol usage

Config item additions could include:

- `.diagnostics`
- `.tasks`
- `.warnings`

### Config design

Add a diagnostics section to `KittyConfig`, for example:

- `diagnostics.enabled`
- `diagnostics.inlineLenses.enabled`
- `diagnostics.statusBar.enabled`
- `diagnostics.statusBar.compact`
- `diagnostics.commentFindings.enabled`
- `diagnostics.commentFindings.includeDocumentationComments`
- `diagnostics.commentFindings.defaultPatterns`
- `diagnostics.commentFindings.additionalPatterns`
- `diagnostics.debounceMilliseconds`
- `diagnostics.maxFileBytes`

Default patterns should include hardcoded seeds:

- `TODO` -> `task`
- `FIXME` -> `warning`
- `WARNING` -> `warning`

These defaults should be overrideable, not removed from the product.

The config also needs interop-related fields, for example:

- `diagnostics.adapters.enabled`
- `diagnostics.adapters.preferredImportFormats`
- `diagnostics.adapters.autoDiscoverConfigs`
- `diagnostics.adapters.pathMappings`
- `diagnostics.export.defaultFormat`
- `diagnostics.import.replacePolicy`
- `diagnostics.providers.<tool-id>.enabled`
- `diagnostics.providers.<tool-id>.configPath`
- `diagnostics.providers.<tool-id>.severityMap`

### Theme additions

Add theme slots for:

- diagnostic error foreground
- diagnostic warning foreground
- diagnostic info foreground
- task finding foreground
- optional background or lens tint variants

Without this, status bar and inline findings will be visually inconsistent with the rest of the editor.

## Recommended Phasing

### Phase 1: Async findings pipeline and status summary

- Introduce core finding models.
- Add comment and parser extraction lanes.
- Compute counts asynchronously.
- Add status bar summary items.
- Add gutter and line overlay severity cues.
- Define the adapter protocols and normalized schema now, even if only one or two adapters ship immediately.

This phase delivers most of the value and stays within current render constraints.

### Phase 2: True inline lenses

- Add virtual text or adornment support to `TextEditor`.
- Extend `TextEditorLayout` for cursor, wrap, and hit-testing correctness.
- Render inline lens text for active findings.

### Phase 3: Richer providers and interaction

- Add filtering by source and severity.
- Add jump-to-next-finding commands.
- Add future providers for compiler or linter diagnostics.
- Add import and export adapters for SARIF and selected tool-native formats.
- Add a future problems pane or sidebar integration fed by the same normalized model.

## Testing Recommendations

- Add unit tests for comment marker extraction from line and block comments.
- Add tests for documentation comment inclusion policy.
- Add tests for config-controlled severity mapping.
- Add version-guard tests so stale async results never overwrite current buffers.
- Add rendering tests for gutter and line overlays.
- Add layout and cursor tests once virtual text exists.
- Add golden fixtures for SARIF import and export.
- Add tests for LSP-style diagnostic normalization.
- Add tests for Android lint config and report mapping.
- Add tests for compiler-output parsers.
- Add tests for path remapping and workspace-root normalization.

## Recommendation Summary

KittyCode already has most of the hard prerequisites for an async findings engine:

- cancellable background task patterns
- comment-aware grammar and parser infrastructure
- line and gutter visual hooks

The main missing pieces are:

- a diagnostics data model
- a versioned async findings manager
- status bar segment support
- a real virtual text layer for true inline lenses
- an adapter substrate for config formats, report formats, and reporting sinks

The right path is phased. Build the async findings pipeline and status reporting first, ship gutter and line cues on top of the current renderer, then add a genuine inline lens system once `TextEditor` and `TextEditorLayout` support virtual text correctly.

Interoperability should be designed in from the start:

- normalize once into a KittyCode-native diagnostics model
- add adapters for live, file-based, and log-based sources
- add config adapters for external tool policy
- add multiple sinks so the same findings can feed the editor, the status bar, and future problems views

## External References

- VS Code programmatic diagnostics and `publishDiagnostics`:
  - https://code.visualstudio.com/api/language-extensions/programmatic-language-features
- SARIF standard:
  - https://github.com/oasis-tcs/sarif-spec
- SARIF overview:
  - https://github.com/sarif-standard
- Android lint and `lint.xml`:
  - https://developer.android.com/studio/write/lint.html
- Android Gradle lint SARIF report path:
  - https://developer.android.com/reference/tools/gradle-api/7.0/com/android/build/api/dsl/Lint
- JetBrains InspectCode SARIF output:
  - https://www.jetbrains.com/help/rider/InspectCode.html
- Xcode `.xcresult` environment and result bundles:
  - https://developer.apple.com/documentation/Xcode/Environment-Variable-Reference
- Xcode `xcresulttool` for extracting build and test failures:
  - https://developer.apple.com/videos/play/wwdc2019/413/
