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

## Deep Technical Analysis

### Codebase Impact Assessment

#### Virtual Text Layer Engineering

The core technical challenge for inline lenses is that `TextEditorLayout.swift` computes all layout metrics — cursor position, hit testing, scroll metrics, wrapped rows — exclusively from real buffer text. The `wrappedRowStartColumns()` function (TextEditorLayout.swift:378-399) tracks display width of each character and breaks on content boundary. The `cursorPosition()` function (lines 127-172) computes screen coordinates from buffer row/col through wrap-aware arithmetic. The reverse mapping `textPosition()` (lines 174-235) does screen-to-text coordinate translation.

Adding virtual text (inline lenses) breaks these invariants because:

1. **Extra visual rows**: An inline lens displayed below a source line (like VS Code's "Problems" decorations) adds visual rows that don't correspond to buffer lines. `totalWrappedRowCount()` (lines 317-323) must account for adornment rows, but cursor navigation must skip them.
2. **Extra visual columns**: Trailing text (like Rust's inlay type hints or error messages at end of line) extends the visual width of a line without changing the buffer content. Hit testing must distinguish clicks on real text from clicks on virtual text.
3. **Cursor coordinate space**: The cursor must remain in buffer coordinates. Virtual text should be visually present but not selectable or editable. The `CursorPosition` returned by `cursorPosition()` must still map to real buffer positions.

Recommended approach — **adornment layers separate from text layout**:

1. Define `InlineAdornment` as: `(anchorLine: Int, position: AdornmentPosition, content: StyledTextSpan)` where `AdornmentPosition` is `.trailingOnLine` or `.belowLine`.
2. For `.trailingOnLine`: Render after the last real character on the line, with a gap. Don't alter wrap calculations. The adornment truncates if the line is already at display width.
3. For `.belowLine`: Insert a virtual row after the anchor line's wrapped rows. Increment `totalWrappedRowCount()` by the adornment row count. Adjust `cursorPosition()` to offset screen rows for all lines below the adornment. Adjust `textPosition()` to return `nil` for clicks on adornment rows.
4. Keep cursor navigation ignorant of adornments — pressing Down skips virtual rows automatically because the cursor advances by buffer line, and the screen offset calculation handles the visual gap.

#### Comment Finding Extraction Pipeline

The existing parser infrastructure provides two extraction paths:

**Path 1 — Parser-backed comment nodes** (GLRParser.swift:145-159): After parsing, comment tokens marked `.isExtra` are appended to the root syntax tree as named `"comment"` nodes with `byteRange` and `pointRange`. `SyntaxNode.text(from:)` can extract the comment text. This is the most accurate path because it uses the language grammar to correctly identify comments, avoiding false positives in strings or heredocs.

**Path 2 — Grammar-derived comment patterns** (ParseTable.swift:98-140): The `CommentPattern` type encodes `.line(prefix:)` (e.g., `"//"`) and `.block(open:close:)` (e.g., `"/*"..."*/"`). These are stored in `LexTable.commentPatterns` and extracted from grammar extras by `LexTableCompiler`. A text scanner can use these patterns to find comment regions without full parsing.

**Path 3 — Plain text fallback**: For files with no grammar support, scan for common comment prefixes (`//`, `#`, `--`, `%`) using a heuristic that checks for the prefix at the start of a line (after whitespace). This has false positives but provides basic coverage for unsupported languages.

The recommended extraction flow:

```
if hasParserArtifacts(language) && source.utf8.count <= maxGrammarSourceBytes {
    // Path 1: Parse → walk comment nodes → extract markers
} else if hasCommentPatterns(language) {
    // Path 2: Scan using grammar-derived comment patterns
} else {
    // Path 3: Heuristic plain-text scan
}
```

For each extracted comment, scan for configured marker patterns (default: `TODO`, `FIXME`, `WARNING`) using case-insensitive prefix matching after the comment delimiter. Extract the message text following the marker.

#### Status Bar Segment Model Evolution

The current `StatusBar` widget (StatusBar.swift:5-21) renders three plain strings (`left`, `center`, `right`) with a single shared `Style`. The `StatusBarContent.statusBarSegments()` function (StatusBarContent.swift:6-18) joins items with `" │ "` separators into these strings.

For diagnostics reporting, the status bar needs:

1. **Per-segment styling**: Replace `left: String` with `left: [StatusBarSegment]` where each segment carries its own `Style`. A diagnostic segment showing "2 warnings" should render in the theme's warning color, not the default status bar color.

2. **Segment measurement**: The current `prefixFitting()` and `suffixFitting()` functions (StatusBar.swift:75-103) truncate strings to fit display width. With segments, truncation must be segment-aware — drop low-priority segments entirely rather than clipping mid-segment.

3. **Diagnostic segment format**: Show severity-bucketed counts with icons: `"⚠ 3  ℹ 1"` or compact `"W3 I1"`. Use theme colors: error foreground for error counts, warning foreground for warning counts.

4. **New status bar items**: Add `StatusBarConfig.Item` cases for `.diagnosticSummary`, `.taskCount`, `.warningCount`. These are resolved in `statusBarText(for:)` (StatusBarContent.swift:20-47) by querying the `DiagnosticsManager` for current document findings.

#### Theme Color Additions

`Config.swift` has no diagnostic color slots. The minimum additions:

- `theme.diagnosticError`: foreground for error indicators (default: red)
- `theme.diagnosticWarning`: foreground for warning indicators (default: yellow/orange)
- `theme.diagnosticInfo`: foreground for info indicators (default: blue)
- `theme.diagnosticTask`: foreground for TODO/FIXME markers (default: cyan)
- `theme.diagnosticErrorBackground`: optional background tint for error lines
- `theme.diagnosticWarningBackground`: optional background tint for warning lines

These feed into `GutterDecoration` styles, `TextStyleOverlay` for line backgrounds, `StatusBarSegment` styles, and future `InlineAdornment` styles.

#### Async Manager Pattern

The existing patterns in `EditorStateFileSystem.schedulePostLoadProcessing()` and `GitDecorationManager` establish the async manager contract:

1. Cancel prior task on document change
2. Debounce rapid edits
3. Capture `documentVersion` before background work
4. Compute results off the main actor
5. Guard version match before applying results
6. Invalidate render source on successful apply

The `DiagnosticsManager` should follow this exactly:

```swift
@MainActor
final class DiagnosticsManager {
    private var activeTask: Task<Void, Never>?
    private var lastProcessedVersion: Int = -1

    func scheduleUpdate(for buffer: DocumentBuffer, config: DiagnosticsConfig) {
        activeTask?.cancel()
        let version = buffer.documentVersion
        let source = buffer.textBuffer.lines
        let language = buffer.language

        activeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(config.debounceMilliseconds))
            guard !Task.isCancelled else { return }

            let findings = await Self.extractFindings(
                from: source, language: language, config: config)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self?.lastProcessedVersion != version else { return }
                self?.lastProcessedVersion = version
                self?.applyFindings(findings, for: buffer)
            }
        }
    }
}
```

### State of the Art: Editor Diagnostics and Inline Lens Systems

#### VS Code: Diagnostic API and Inlay Hints

VS Code separates diagnostics from inlay hints:
- **Diagnostics**: Published by language servers via `textDocument/publishDiagnostics`. Stored in `DiagnosticCollection` per extension. Each diagnostic has severity, range, message, source, code, and related information. Rendered as: squiggly underlines, gutter icons, minimap markers, Problems panel entries, and status bar counts.
- **Inlay Hints**: A separate API (`textDocument/inlayHint`) for non-diagnostic virtual text — type annotations, parameter names, etc. Positioned at specific buffer offsets. Rendered as dimmed inline text that the cursor skips.
- **CodeLens**: Another separate API for actionable annotations above lines. Used for "Run Test", "N references", etc. Rendered as clickable virtual lines above the source line.
- **Diagnostic severity**: `Error`, `Warning`, `Information`, `Hint`. Each has distinct rendering (red/yellow/blue/dimmed squiggles, gutter icons, status bar counts).

#### Neovim: Built-in Diagnostics and Virtual Text

Neovim (0.5+) has a built-in diagnostic framework:
- **`vim.diagnostic`**: Module that manages diagnostics per buffer per namespace. Multiple sources can publish diagnostics to the same buffer.
- **Virtual text**: Neovim's `nvim_buf_set_extmark()` API supports `virt_text` — arbitrary styled text appended after a line's content. Also supports `virt_lines` — virtual lines inserted between real lines. This is the terminal editor SOTA for inline lens rendering.
- **Signs**: Gutter icons for diagnostic severity, displayed in the sign column.
- **Diagnostic handlers**: Configurable display handlers for virtual text, signs, underlines, and floating windows. Each can be independently enabled/disabled and styled.
- **Severity filtering**: `vim.diagnostic.config({ severity_sort = true })` sorts diagnostics by severity. `vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })` filters by severity.

#### Helix: Inline Diagnostics

Helix renders diagnostics inline using its built-in virtual text support:
- Diagnostic messages displayed at the end of the affected line in dimmed text
- Gutter severity indicators (colored dots)
- Jump-to-diagnostic commands (`]d`, `[d`) for keyboard navigation
- No separate problems panel — all diagnostics are inline-only
- Severity-based sorting for overlapping diagnostics

#### JetBrains IDEs: Inspection Infrastructure

JetBrains IDEs have the most comprehensive inspection architecture:
- **Inspection profiles**: XML-based configuration files defining which inspections are enabled, their severity, and scope.
- **Inspection scopes**: Can be per-project, per-module, or per-directory.
- **Severity mapping**: Inspections have a default severity that can be remapped per profile (e.g., treating a warning as an error in production code).
- **Quick fixes**: Each inspection can provide one or more quick-fix actions. Fixes can be applied individually or in batch across the project.
- **Suppression**: Inspections can be suppressed with inline annotations (`@SuppressWarnings`, `// noinspection`) or profile exclusions.
- **SARIF export**: `InspectCode` command-line tool exports findings in SARIF format for CI integration.

#### SARIF Standard Details

SARIF (Static Analysis Results Interchange Format) is an OASIS standard (v2.1.0):
- **Structure**: `sarifLog` → `runs[]` → `results[]`. Each run has a `tool` descriptor and an array of results.
- **Result fields**: `ruleId`, `level` (error/warning/note/none), `message`, `locations[]`, `relatedLocations[]`, `codeFlows[]`, `fixes[]`, `fingerprints`.
- **Location model**: `physicalLocation` with `artifactLocation` (URI + index) and `region` (startLine, startColumn, endLine, endColumn). Also supports `logicalLocation` (fully qualified name).
- **Code flows**: Ordered sequences of locations representing execution paths. Used by dataflow analyzers to show how tainted data flows through code.
- **Fingerprints**: Stable identifiers for result deduplication across runs. Used by GitHub Code Scanning to track issues across commits.
- **Fixes**: Each fix has a description and an array of `artifactChanges`, each with `replacements` specifying exact text edits.

### Recommended Technical Approach for KittyCode

#### Diagnostics and Virtual Text Pipeline: SOTA Architecture

1. **Extmark model (Neovim-inspired) with interval tree storage**: Virtual text and decorations are stored as "extmarks" — metadata attached to buffer positions that survive edits automatically. Each extmark has: anchor position `(line, col)`, gravity (left or right — determines whether the mark moves with insertions at its exact position), type enum (virtual text, highlight range, sign/gutter icon, line highlight), priority (for stacking order when multiple marks overlap), and a payload (styled text segments, highlight style, sign character, etc.). All extmarks for a buffer are stored in an augmented interval tree (augmented red-black tree where each node stores the maximum endpoint in its subtree), enabling O(log n) insertion/deletion and O(log n + k) range queries (find all marks intersecting visible lines). On every buffer edit, the interval tree is updated: marks with right-gravity shift right on inserts at their position, marks with left-gravity stay. Deletions that encompass a mark either delete it (ephemeral marks) or collapse it to zero-width (persistent marks). This is the core data structure that underpins all virtual text, diagnostics, git blame, code lenses, and inline hints.

2. **LSP as the primary diagnostic provider, integrated from day one**: Design the entire diagnostic pipeline around the Language Server Protocol. The `LSPClient` actor spawns language servers per workspace root based on configuration, manages the lifecycle (initialize, initialized, shutdown), and routes notifications. `textDocument/publishDiagnostics` notifications are normalized into KittyCode's extmark model: each LSP diagnostic becomes one or more extmarks (underline highlight + gutter sign + optional virtual text). Support all LSP diagnostic fields: `severity`, `code`, `codeDescription` (URL to documentation), `source`, `message`, `tags` (unnecessary code = dim style, deprecated = strikethrough), `relatedInformation` (secondary locations rendered as linked extmarks), and `data` (opaque payload for code action resolution). Support `textDocument/inlayHint` for type annotations rendered as dim virtual text inline. This single integration unlocks diagnostics for every language with an LSP server.

3. **Diagnostic quick-fix actions with lightbulb UI**: Each diagnostic can carry associated code actions via `textDocument/codeAction`. When the cursor enters a line with available code actions, render a lightbulb icon (`*`) in the gutter with a distinct style. The `editor.action.quickFix` command opens a picker listing all available actions for the current cursor position, grouped by kind: quickfix, refactor, refactor.extract, refactor.inline, source, source.organizeImports. Each action can be either a direct `WorkspaceEdit` (applied immediately as an undo transaction) or a `Command` (executed by the language server). Support "preferred" actions that can be auto-applied. Support "fix all in file" (batch-apply all preferred fixes for a diagnostic source). Integrate with the undo system: every code action application is wrapped in a transaction for single-step undo.

4. **SARIF import/export for CI and external tool integration**: Implement `SARIFImporter` that parses SARIF v2.1.0 JSON and normalizes results into the extmark diagnostic model. Map SARIF `level` (error, warning, note, none) to KittyCode severity. Map SARIF `physicalLocation.region` to buffer positions. Preserve SARIF `fingerprints` for deduplication across runs. Preserve `codeFlows` as navigable step-through sequences (jump from location to location). Implement `SARIFExporter` that serializes the current diagnostic snapshot to SARIF, including `tool` metadata, `results` with full location information, and `fixes` as `artifactChanges`. This enables: importing SwiftLint, SonarQube, or CodeQL results as editor overlays; exporting KittyCode diagnostics for CI pipelines; and compatibility with GitHub Code Scanning's SARIF upload API.

5. **Virtual text rendering engine with three placement modes**: The renderer supports three virtual text placement modes, all backed by extmarks: (a) `after_line_end` — styled text appended after the real line content, separated by configurable padding (used for inline diagnostics, type hints, git blame). (b) `below_line` — virtual rows inserted between real lines that occupy screen space but do not exist in the text buffer (used for multi-line diagnostic messages, code lens actions, expanded documentation). (c) `inline` — styled text inserted at a specific column within the line, pushing real text to the right visually but not in the buffer (used for inlay type hints, parameter names). Virtual text participates fully in the layout engine (affects line height calculations, scroll position, viewport line count) but is excluded from the text buffer: cursor movement skips over virtual text, selection excludes it, copy does not include it, and search does not match it.

6. **Diagnostic severity theming with full style mapping**: Define 5 severity levels: error, warning, info, hint, and task (for TODO/FIXME comments). Each severity maps to a complete style specification in the theme: `underlineColor`, `underlineStyle` (single, double, wavy, dotted), `gutterIcon` (character + foreground color), `gutterBackground`, `lineHighlightBackground` (subtle tint), `statusBarForeground`, `statusBarBadge`. Default mapping: error = red wavy underline + `E` gutter icon, warning = yellow wavy underline + `W` gutter icon, info = blue single underline + `I` gutter icon, hint = dim dotted underline + no gutter icon, task = green single underline + checkmark gutter icon. Severity stacking priority: when multiple diagnostics overlap, the highest severity wins for underline rendering, and gutter icons stack with the highest severity on top. All severity styles are fully configurable via theme JSON.

7. **Inline git blame annotations**: Render git blame information as `after_line_end` virtual text on each line, loaded lazily and cached per commit. On scroll, request blame data for newly visible lines via `git blame -L <start>,<end> --porcelain`. Cache blame data keyed by `(file_path, commit_hash, line_range)` — cache entries are invalidated when the buffer is modified. Format: `author_name, relative_time — first_line_of_commit_message`, rendered in a dim/muted style to avoid visual competition with actual code. Toggle blame visibility with a command (`editor.toggleBlame`). On hover or keypress on a blame annotation, show a popup with full commit details. This matches GitLens functionality in VS Code.

8. **Code lens support with actionable annotations**: Code lenses are virtual text lines rendered above functions, classes, test methods, and other structural code elements. Each lens displays actionable annotations: "3 references | 1 implementation | Run Test | Debug". Lenses are contributed by `CodeLensProvider` protocol implementations (LSP `textDocument/codeLens`, test runner, reference counter). Each lens item has a title (display text), a command (executed on selection), and optional tooltip. Lenses are rendered as `below_line` extmarks positioned above their target line, using a distinct dim style. They are lazily resolved: the provider first returns positions, then resolves titles/commands on demand as lenses scroll into view. Lenses update on document change with debouncing (500ms) to avoid excessive LSP requests.

## SOTA Review and Accuracy Assessment

This section evaluates the ADR's technical claims and recommendations against verified state-of-the-art knowledge as of March 2026.

### Verified Accurate

1. **VS Code's separation of diagnostics, inlay hints, and code lenses** — verified. These are three distinct APIs (`publishDiagnostics`, `textDocument/inlayHint`, `textDocument/codeLens`) with different rendering treatments. The ADR correctly identifies these as related but separate concerns.

2. **Neovim's extmark API for virtual text** — verified. `nvim_buf_set_extmark()` supports `virt_text` (trailing text), `virt_lines` (virtual rows), inline virtual text, signs, and line highlights. Extmarks are stored in a B-tree variant ("marktree") for O(log n) lookups and efficient bulk updates.

3. **Neovim extmark gravity** — verified. Each mark endpoint has left or right gravity controlling behavior when text is inserted at the mark's exact position. This is critical for diagnostic marks staying attached to original code through edits.

4. **SARIF v2.1.0 as the interchange standard** — verified. Approved as an OASIS Standard on June 4, 2020, with Errata 01 published August 28, 2023. No v2.2 or v3.0 has been published. Strong adoption in security/SAST tools (CodeQL, Semgrep, GitHub Code Scanning).

5. **LSP `publishDiagnostics` architecture** — verified. Server-to-client notification with severity, range, message, code, source, relatedInformation, tags (Unnecessary, Deprecated), and data fields. LSP 3.17 added pull diagnostics (`textDocument/diagnostic`) as a complement.

6. **The phased approach** (async pipeline + status first → gutter/line cues → true inline lenses) is well-sequenced. Phase 1 delivers most value within current render constraints.

7. **The decision to normalize around a KittyCode-native model** with adapters for external formats follows industry best practice. Every major editor maintains its own internal diagnostic representation.

### Requires Qualification

1. **SARIF scope** — SARIF is well-established for static analysis interchange but heavyweight for simple use cases. The JSON schema is large and complex. For a terminal editor, consuming SARIF is useful for CI/CD interoperability, but LSP diagnostics remain the primary real-time channel. The ADR correctly prioritizes LSP and SARIF as the first two targets, but should note that the SARIF adapter will primarily serve batch/import workflows rather than live editing.

2. **Extmark storage as "augmented interval tree"** (recommended approach point 1) — Neovim's actual implementation uses a B-tree variant called "marktree" (implemented in `src/nvim/marktree.c`), not a classical augmented red-black interval tree. The B-tree structure provides better cache performance for bulk operations. The ADR's recommendation to use "an augmented red-black tree where each node stores the maximum endpoint in its subtree" is a valid alternative but differs from Neovim's proven implementation. Either data structure works; the ADR should note that a B-tree variant may be more cache-friendly.

3. **LSP pull diagnostics** — The ADR does not mention pull-based diagnostics (`textDocument/diagnostic`, added in LSP 3.17). IntelliJ 2025.2 enabled pull diagnostics by default. The architecture should accommodate both push (`publishDiagnostics`) and pull models, as the pull model gives the client more control over when to request diagnostics for visible documents.

4. **Git blame as inline virtual text** (point 7) — While technically accurate, this is a significant scope expansion beyond the diagnostics/findings ADR's stated goal. Git blame annotations are a decoration feature, not a diagnostic. This recommendation should either be moved to a separate ADR or explicitly marked as a future extension that demonstrates the virtual text infrastructure's reusability.

### References

- Neovim extmarks API: https://neovim.io/doc/user/api.html
- Neovim marktree implementation: https://github.com/neovim/neovim/blob/master/src/nvim/marktree.c
- SARIF 2.1.0 specification: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
- LSP 3.17 specification: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- VS Code Diagnostic API: https://code.visualstudio.com/api/language-extensions/programmatic-language-features
- GitHub SARIF support: https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning
