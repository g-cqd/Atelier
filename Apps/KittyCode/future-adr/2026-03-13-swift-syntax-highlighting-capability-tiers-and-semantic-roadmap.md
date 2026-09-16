# Future ADR: Swift Syntax Highlighting Capability Tiers and Semantic Roadmap

Status: Proposed
Date: 2026-03-13

## Goal

Define the architecture required for KittyCode to move from its current narrow Swift syntax highlighting toward materially more complete highlighting, while also establishing a generalized language-highlighting capability model that can scale to other languages and future extension contributions.

The immediate motivation is Swift because the current Swift experience has an obvious gap against modern editor expectations. The longer-term objective is not "make Swift prettier". It is to define a stable highlighting architecture that can express:

- lightweight lexical fallback
- grammar-backed structural highlighting
- semantic symbol-aware highlighting
- deterministic merging between those layers
- explicit compatibility reporting for language contributions

## Scope

This ADR covers:

- the current Swift highlighting pipeline in KittyCode
- the verified Swift highlighting gaps in the codebase
- the architectural distinction between lexical, structural, and semantic highlighting
- the parser and query-runtime requirements needed for richer grammar-backed highlighting
- the internal token model required for semantic differentiation
- the capability model language contributions should declare
- the migration path for Swift as the first serious consumer of the architecture
- the relationship between this work and the existing extension architecture direction

## Non-Goals

This ADR does not cover:

- implementing SourceKit-LSP integration end to end
- defining a complete extension marketplace or runtime plugin system
- replacing the current renderer or text model
- full theme-system redesign
- exact UX design for new settings, status indicators, or inspector panels
- non-Swift language migrations in detail

## Current Codebase Findings

### Swift query coverage is materially incomplete

`Sources/KittySyntax/Grammars/swift/highlights.scm` is only 42 lines and currently captures only:

- a flat keyword list
- `type_identifier` as `@type`
- `line_string_literal` as `@string`
- integer and real literals as `@number`
- comments as `@comment`
- attributes as `@attribute`
- function declaration names as `@function`
- property patterns as `@variable`
- parameter names as `@variable.parameter`

Verified implication:

- the current grammar-backed Swift highlighter does not distinguish call sites, members, operators, punctuation, constructors, booleans, `nil`, doc comments, raw strings, multiline strings, interpolation punctuation, regex literals, enum members, type parameters, macro-related syntax, labels, or declaration-vs-reference categories

This is not a subtle quality gap. It is a coverage gap in the resource layer itself.

### Grammar-backed highlighting is bundle-centric and compatibility-gated

`Sources/KittySyntax/LanguageHighlighter.swift` loads bundled `grammar.json` and `highlights.scm` resources, compiles them into syntax artifacts, and refuses grammar-backed loading unless `grammar.externals.isEmpty`.

Verified implication:

- KittyCode does not currently support grammars that require external scanners in the grammar-backed highlighting path

This is reinforced by `Tests/KittySyntaxTests/GrammarLoaderBundledGrammarTests.swift`, which explicitly asserts that the bundled Swift grammar has no externals.

### The current Swift grammar sourcing path is stale

`Scripts/generate-grammars.sh` defaults languages to the `tree-sitter` GitHub owner unless explicitly overridden. There is no Swift-specific override.

Verified implication:

- the current grammar generation path for Swift still points at the older `tree-sitter/tree-sitter-swift` line rather than the modern `alex-pinkus/tree-sitter-swift` line

This matters because the old source line is compatible with KittyCode's current "no externals" assumption, but it is also materially less capable.

### Query parsing and query execution are capable but not fully tree-sitter-compatible

`Sources/KittyQuery/QueryParser.swift` and `Sources/KittyQuery/QueryMatcher.swift` support:

- node matches
- field matches
- alternation
- anchors
- predicates such as `#match?`
- directives

Verified limitations:

- multiple captures on the same pattern are not modeled as first-class behavior
- quantifiers are only consumed syntactically and do not preserve quantifier semantics

This means KittyCode can parse a useful subset of tree-sitter query syntax, but not the full behavioral surface that richer upstream queries rely on.

### The fallback Swift highlighter is intentionally lightweight

`fallbackHighlightSwift` in `Sources/KittySyntax/LanguageHighlighter.swift` handles:

- a static keyword list
- a static type list
- comments
- simple attributes
- simple strings
- numbers

Verified limitations:

- it misses important newer keywords such as `actor`, `macro`, and `package`
- it does not distinguish doc comments
- it does not model raw, multiline, or interpolated string structure
- it does not distinguish methods, properties, enum members, type parameters, or semantic symbol roles

`Tests/KittySyntaxTests/FallbackSwiftCommentHighlightingTests.swift` show that the current fallback strategy is primarily trying to avoid bad false positives inside comments, not provide a rich Swift model.

### Theme resolution is not the primary architectural blocker

`Sources/KittySyntax/Theme.swift` already supports hierarchical fallback. Richer capture names can often degrade to a parent style without breaking rendering.

Verified implication:

- richer token classes will require more theme entries to look good, but missing theme keys are not the main reason Swift highlighting is currently incomplete

### The current rendering output is style-first, not role-first

`Sources/KittySyntax/Highlighter.swift` converts captures directly into styled spans. This is efficient for the current design, but it compresses semantic meaning too early.

Verified implication:

- the current pipeline is optimized for `capture name -> style -> rendered span`
- it is not optimized for preserving token role, modifiers, provenance, and merge precedence across multiple highlighting layers

That design is sufficient for simple tree-sitter-style highlighting. It becomes constraining once semantic highlighting enters the system.

## External Comparison Findings

### Modern upstream tree-sitter Swift is richer before semantics even begin

The current `alex-pinkus/tree-sitter-swift` query surface is significantly broader than KittyCode's bundled Swift query. It covers, among other things:

- punctuation classes
- bracket classes
- builtin variables such as `self` and `super`
- keyword subclasses
- function call sites
- method names
- constructors
- macro-like constructs
- member access
- labels
- documentation comments
- string escapes
- interpolation punctuation
- regex literals
- boolean and builtin constant distinctions
- operators

Verified implication:

- even without semantic tokens, KittyCode is currently leaving substantial syntactic highlighting value on the table

Verified blocking constraint:

- the modern upstream grammar uses externals, so it is not currently compatible with KittyCode's grammar-backed pipeline

### VS Code Swift highlighting is not explained by one local grammar contribution alone

In the current `swiftlang/vscode-swift` `package.json`, the extension contributes a grammar for `swift-gyb`, not regular `.swift`.

Verified fact:

- the repository does not, in its current package metadata, declare a regular `.swift` grammar contribution the same way it declares `swift-gyb`

Verified fact:

- the repository still contains a Swift TextMate grammar fixture derived from `jtbandes/swift-tmlanguage`

Inference:

- the effective `.swift` highlighting experience in current VS Code setups appears to rely significantly on SourceKit-LSP semantic tokens, not only on a Swift grammar contribution in that repository

This inference should not be overstated. The important architectural point is simpler: the comparison target users experience in VS Code is hybrid, and a syntax-only comparison is therefore incomplete.

### SourceKit-LSP provides a semantic layer that KittyCode does not currently model

`SourceKit-LSP` merges syntax-tree classifications with semantic tokens and distinguishes categories such as:

- class
- actor
- struct
- enum
- enum member
- interface / protocol
- type parameter
- function
- method
- property
- variable
- operator
- macro
- documentation comment
- regex
- parameter label
- static
- default-library / builtin-like symbols

Verified implication:

- some of the distinctions users associate with "better syntax highlighting" are not realistically achievable from syntax grammar alone

This is the most important external comparison finding. KittyCode is missing two separate things:

- richer structural syntax coverage
- a semantic layer

Those are related, but they are not interchangeable.

## Problem Statement

KittyCode currently treats language highlighting as a mostly grammar-resource problem with a lexical fallback escape hatch. That model is no longer sufficient for Swift.

Swift exposes three separate levels of highlighting value:

1. lexical differentiation
2. structural syntax differentiation
3. semantic symbol differentiation

KittyCode currently has:

- a lightweight lexical fallback
- a narrow structural query on top of an older grammar
- no semantic highlighting layer

It also has two technical constraints that prevent simple adoption of richer upstream syntax resources:

- no external-scanner support in the grammar-backed pipeline
- incomplete tree-sitter query behavior

As a result, KittyCode cannot reach a meaningfully more complete Swift highlighting experience through theme tweaks or a few extra query lines alone. It needs an explicit highlighting capability architecture and a migration path that separates:

- resource freshness
- parser/runtime compatibility
- query-runtime compatibility
- token modeling
- semantic-provider integration

## Decision

KittyCode should adopt a language-highlighting capability architecture with explicit tiers, explicit provider boundaries, and explicit merge precedence.

The system should no longer treat "syntax highlighting" as one undifferentiated concern. Instead, it should model at least three distinct highlight sources:

- lexical fallback highlighting
- grammar-backed structural highlighting
- semantic symbol-aware highlighting

Each language contribution should declare which highlighting capabilities it supports, what parser/query features it requires, and how its highlight layers merge.

Swift should be the first language migrated against this architecture because it clearly exercises all three levels:

- it benefits from richer lexical fallback
- it needs a more modern structural grammar/query story
- it cannot approach modern-editor completeness without semantic token support

## Proposed Architecture

### 1. Introduce a role-preserving internal highlight token model

KittyCode should stop collapsing captures directly into styled spans as the only internal representation.

The rendering layer can still end in `StyledSpan`, but the highlighting pipeline should first produce a richer intermediate token stream:

```swift
struct HighlightToken: Sendable {
    let range: Range<Int>
    let role: HighlightRole
    let modifiers: Set<HighlightModifier>
    let source: HighlightLayer
    let priority: Int
}

enum HighlightLayer: Sendable {
    case lexical
    case structural
    case semantic
}

enum HighlightRole: Sendable {
    case keyword
    case type
    case function
    case method
    case property
    case variable
    case parameter
    case parameterLabel
    case enumMember
    case typeParameter
    case comment
    case string
    case regexp
    case number
    case operator
    case punctuation
    case label
    case attribute
    case macro
    case builtin
}

enum HighlightModifier: Sendable {
    case declaration
    case documentation
    case `static`
    case defaultLibrary
}
```

This is the architectural pivot that makes the rest of the roadmap coherent. Once the system preserves role and modifiers, theme resolution becomes a late-stage concern rather than the storage format for highlight meaning.

### 2. Split highlighting into layered providers

The highlighting pipeline should be factored into explicit providers:

- `LexicalHighlighter`
- `StructuralHighlighter`
- `SemanticHighlighter`

Each provider should return `HighlightToken` values for a document or region, not rendered spans.

The merge stage should then apply deterministic precedence rules and coalesce into styled output.

### 3. Add a merge engine with explicit precedence

The system should define one merge policy instead of letting precedence emerge accidentally from resource order.

Recommended default precedence:

- semantic tokens override structural tokens when both cover the same semantic unit
- structural tokens override lexical fallback when structural parsing succeeds
- lexical fallback remains the last-resort baseline for unsupported, failed, or oversized cases

This should be configurable per provider family only where justified. It should not become arbitrary token-by-token extension behavior.

### 4. Make parser and query capabilities explicit, not implicit

The current runtime silently excludes richer resources by testing `grammar.externals.isEmpty` and by accepting only a subset of tree-sitter query behavior.

That compatibility boundary should be formalized as declared requirements:

```swift
struct ParserRequirements: Sendable {
    let requiresExternalScannerSupport: Bool
    let queryFeatures: Set<QueryFeature>
}

enum QueryFeature: Sendable {
    case multipleCapturesPerPattern
    case quantifiedPatterns
    case predicates
    case directives
    case anchors
}
```

This allows the host to answer questions such as:

- can this grammar run in the current parser?
- can this query execute with the current query runtime?
- if not, should the language fall back to lexical or to an older structural resource?

### 5. Decouple resource freshness from runtime compatibility

The system should not force one bundled Swift grammar resource to serve as both:

- the best available grammar
- the only compatible grammar

Instead, language contributions should be able to declare:

- preferred structural resources
- fallback structural resources
- parser requirements

That creates a path where Swift can move from:

- older compatible grammar
- to newer compatible grammar
- to modern external-scanner grammar

without changing the overall language-provider contract.

## Highlighting Capability Tiers

KittyCode should define explicit highlighting capability tiers for languages.

### Tier 0: Plain Detection

The host can identify the language but has no meaningful highlighter beyond default text.

Use cases:

- unsupported languages
- broken contributions
- emergency fallback

### Tier 1: Lexical Fallback

The language has a lightweight token classifier based on comments, strings, numbers, keywords, and a small number of safe lexical heuristics.

Properties:

- cheap
- robust under syntax errors
- suitable for very large files
- intentionally low fidelity

This is where KittyCode's current fallback Swift highlighter lives.

### Tier 2: Structural Grammar-Backed Highlighting

The language has parser-backed highlighting driven by grammar resources and highlight queries.

Properties:

- more precise than lexical fallback
- captures syntactic structure
- can classify members, calls, punctuation, directives, string structure, and other syntax roles
- still cannot reliably infer symbol meaning that requires semantic resolution

This is where a richer Swift tree-sitter-based experience belongs.

### Tier 3: Semantic Highlighting

The language has symbol-aware highlighting from a language service or semantic token provider.

Properties:

- distinguishes declaration vs reference
- distinguishes method vs function vs property vs variable where syntax alone is insufficient
- distinguishes builtin or default-library symbols
- can mark parameter labels, enum members, type parameters, actor references, and protocol references

This is the tier required to approach the effective highlighting users see in modern Swift editors.

### Tier 4: Merged Semantic + Structural

The final user-facing experience should generally be a merged presentation, not semantic replacement of all syntax information.

Semantic tokens do not eliminate the need for structural syntax highlighting because structural layers still provide:

- punctuation
- delimiter structure
- string escape and interpolation structure
- directive syntax
- fallback behavior when semantic providers are unavailable

Swift should ultimately target Tier 4:

- lexical fallback as safety net
- structural grammar-backed highlighting as baseline richness
- semantic layer for symbol-aware refinement

## Contribution and Extensibility Implications

This ADR refines the language-provider and capability-tier direction already implied by the extension architecture work.

Language contributions should be able to declare at least the following:

- detection rules
- lexical fallback provider
- grammar resource package
- highlight query package
- parser requirements
- query feature requirements
- semantic highlighting provider
- merge policy
- capability-reporting metadata

A language contribution model could look like:

```swift
struct LanguageHighlightingContribution: Sendable {
    let languageId: String
    let detection: DetectionContribution
    let lexicalProvider: LexicalProviderDescriptor?
    let structuralProvider: StructuralProviderDescriptor?
    let semanticProvider: SemanticProviderDescriptor?
    let mergeStrategy: HighlightMergeStrategy
    let capabilities: HighlightingCapabilities
}
```

This architecture is important even before third-party extensions exist. It lets built-in languages declare their support level honestly and consistently.

Examples:

- `json`: Tier 2 or Tier 4 later
- `swift`: Tier 1 today, partial Tier 2 today, target Tier 4
- `markdown`: Tier 2 with specialized injections
- future external language packs: any declared tier the host can support

The host should also expose capability reporting for diagnostics and UI.

Examples:

- status bar can say `Swift: lexical fallback` versus `Swift: structural` versus `Swift: structural + semantic`
- tests can assert capability transitions
- settings can allow users to prefer structural-only mode or disable semantic overlays

## Parser and Query Runtime Implications

### Parser/runtime work

To adopt the modern Swift grammar line, KittyCode needs parser/runtime support for external scanners in the grammar-backed pipeline.

This is not optional if the goal is compatibility with current upstream Swift grammar quality.

Required work includes:

- representing external scanner requirements in grammar artifacts
- loading and executing those scanner hooks in the parser path
- testing external-scanner compatibility under incremental parsing
- reporting unsupported parser requirements clearly rather than silently falling back

### Query-runtime work

To run richer upstream queries faithfully, KittyCode needs stronger query compatibility.

Priority gaps include:

- multiple captures on the same pattern
- meaningful quantifier semantics
- compatibility testing for upstream highlight queries

Without this, KittyCode risks adopting richer resources but still mis-executing them in subtle ways.

### Resource work

Swift grammar generation should stop implicitly preferring the older grammar source line. Resource sourcing needs to become explicit and versionable.

That work belongs in:

- grammar generation metadata
- bundled language manifests
- contribution declarations

### Theme/token mapping work

Once richer token roles exist, theme resolution should map from `(role, modifiers)` rather than from raw query capture names alone.

Hierarchical fallback should remain, but it should fall back across semantic roles intentionally rather than by capture-name coincidence.

## Swift-Specific Migration Path

### Phase 1: Expand the current compatible Swift surface

Ship the highest-value improvements that do not require parser/runtime redesign:

- broaden the bundled Swift highlight query substantially
- add missing obvious lexical tokens to the fallback highlighter
- add tests for Swift punctuation, operators, member access, booleans, `nil`, raw identifiers, doc comments, multiline strings, regex literals where the current grammar can represent them, and call-site coverage where possible

This phase does not create VS Code parity. It does reduce the most visible gap quickly.

### Phase 2: Introduce internal highlight roles and merge infrastructure

Refactor the highlighting pipeline to preserve semantic role before resolving final styles:

- add internal `HighlightToken` representation
- add merge precedence rules
- keep `StyledSpan` as a render artifact, not the primary semantic representation
- extend theme mapping to understand richer roles and modifiers

This phase is the prerequisite for any credible semantic layer.

### Phase 3: Formalize grammar and query compatibility reporting

Before adopting newer Swift resources, the host should be able to say exactly why a resource is or is not compatible.

Deliverables:

- parser requirement metadata
- query feature metadata
- capability reporting APIs
- tests that assert expected compatibility decisions

### Phase 4: Add external-scanner support and modernize Swift grammar sourcing

Once parser/runtime support exists:

- support grammars with external scanners
- update Swift grammar sourcing toward the modern upstream line
- adopt richer structural highlight resources
- add compatibility tests using real upstream Swift grammar/query fixtures

This phase should move Swift from a partial structural highlighter toward a meaningfully richer structural tier.

### Phase 5: Add Swift semantic highlighting

Introduce a Swift semantic provider that can refine structural output with symbol-aware distinctions.

Likely responsibilities:

- method vs function vs property vs variable
- enum members
- type parameters
- builtin / default-library distinctions
- actor and protocol reference distinctions
- parameter-label roles

This phase should target merged output, not semantic-only output.

## Alternatives Considered and Rejected

### 1. Expand only the current Swift query and stop there

Rejected because it improves only one layer of the problem.

Reason:

- Swift users will still expect symbol-aware distinctions that syntax-only resources cannot infer reliably
- the architecture would remain unable to explain capability differences across languages

### 2. Try to match VS Code with syntax grammar alone

Rejected because the comparison target is hybrid.

Reason:

- verified SourceKit-LSP behavior shows semantic distinctions that are outside the reach of syntax-only highlighting
- syntax-only parity is therefore the wrong architectural target

### 3. Drop in modern upstream tree-sitter Swift immediately

Rejected because it is incompatible with the current parser/runtime boundary.

Reason:

- KittyCode currently excludes grammars with externals
- KittyCode's query runtime does not yet model enough of tree-sitter query behavior to treat upstream queries as drop-in resources

### 4. Build semantic highlighting first and ignore structural syntax infrastructure

Rejected because semantic highlighting is not a complete replacement for structural syntax coverage.

Reason:

- structural layers still own punctuation, delimiter structure, interpolation structure, and resilient fallback behavior
- skipping structural improvements would leave the merged experience weak and brittle

## Risks and Open Questions

### Risk: semantic-provider integration may be platform- and toolchain-sensitive

Swift semantic highlighting likely depends on toolchain availability, project configuration quality, and potentially platform-specific language-service behavior.

Open question:

- what minimum semantic-provider contract can KittyCode support consistently across environments?

### Risk: parser/runtime work is deeper than the immediate highlighting request suggests

External-scanner support is not a small query tweak. It is parser/runtime capability work with correctness and incremental-parsing consequences.

Open question:

- should external-scanner support be added in the general parser now, or should the host temporarily support language-specific escape hatches?

### Risk: merge precedence can produce unstable or surprising output

Once lexical, structural, and semantic layers all exist, incorrect precedence rules can cause flicker, unstable token ownership, or confusing conflicts.

Open question:

- should merge precedence be entirely global, or partly language-specific under strict constraints?

### Risk: richer token modeling increases internal complexity

A role-preserving token model is architecturally correct, but it is also more complex than direct `capture -> style -> span` conversion.

Open question:

- what is the smallest internal token model that still supports semantic highlighting cleanly?

### Risk: capability reporting can drift from reality

If the system advertises Tier 3 or Tier 4 support while silently degrading or failing often, users and tests will both receive misleading signals.

Open question:

- how should capability reporting encode degraded operation, such as "semantic requested but unavailable, structural active"?

## Validation and Test Strategy

The migration should be validated at multiple layers.

### Resource and compatibility tests

- verify grammar-source metadata for Swift
- verify parser requirement reporting
- verify query feature requirement reporting
- verify compatibility decisions for bundled and upstream resource shapes

### Query-runtime tests

- add tests for multiple-capture behavior
- add tests for quantified-pattern behavior
- add tests that compare expected capture sets from representative Swift query patterns

### Structural highlighting tests

- add richer Swift highlight snapshot tests for:
  - members
  - function calls
  - punctuation
  - operators
  - booleans
  - `nil`
  - doc comments
  - raw identifiers
  - multiline strings
  - string interpolation
  - regex literals
  - directives and configuration conditions where grammar supports them

### Lexical fallback tests

- extend fallback Swift tests beyond comment safety
- verify fallback treatment of newer keywords
- verify large-file behavior that intentionally forces fallback

### Merge-engine tests

- assert semantic-over-structural precedence
- assert structural-over-lexical precedence
- verify coalescing stability after merges
- verify identical-range conflict handling

### Capability-reporting tests

- assert reported tier for each bundled language
- assert degraded-mode reporting when semantic providers are unavailable
- assert unsupported parser/query requirements produce explicit capability downgrades

### Integration tests

- when a Swift semantic provider exists, test merged output for actor references, enum members, parameter labels, builtin symbols, and property references

## Relationship to the Extension Architecture ADR

This ADR should be treated as a refinement of the language-provider and capability-tier direction already implied by the extension architecture work.

Specifically, it sharpens that direction by defining:

- a highlighting capability model
- provider boundaries for lexical, structural, and semantic layers
- parser and query compatibility metadata
- merge semantics between highlight layers

It does not require the extension architecture ADR to be edited immediately. The existing direction remains valid. This ADR simply makes one part of that direction concrete enough to guide implementation work.

If the extension architecture ADR is revised later, it should reference this ADR when describing:

- typed language providers
- language capability tiers
- contribution manifests for language resources
- future semantic-provider contribution seams

The important sequencing point is:

- the extension architecture ADR defines the broad host model
- this ADR defines the highlighting-specific language capability model that should fit inside that host model

## Deep Technical Analysis

### Codebase Impact Assessment

#### External Scanner Support Engineering

The alex-pinkus/tree-sitter-swift grammar requires approximately 33 external token types handled by a C external scanner (`scanner.c`). These are not optional niceties — they cover fundamental Swift constructs:

- **Raw string literals**: `raw_str_part`, `raw_str_continuing_indicator`, `raw_str_end_part` — Swift raw strings use variable numbers of `#` delimiters (`#"..."#`, `##"..."##`). The delimiter count determines interpolation boundaries, requiring scanner state that context-free rules cannot express.
- **Implicit semicolons**: `_implicit_semi` — Swift uses newlines as statement terminators in most contexts, but the rules for when a newline acts as a semicolon vs. continuation are context-dependent (e.g., method chaining across lines requires lookahead).
- **Custom operators**: Multiple operator tokens (`_arrow_operator_custom`, `_dot_custom`, `_eq_custom`, etc.) — Swift custom operators must be validated against extensive Unicode ranges and termination rules beyond what regular grammar rules can handle.
- **Nested block comments**: `multiline_comment` — Swift allows `/* ... /* ... */ ... */` nesting, which is not context-free.
- **Compiler directives**: `_directive_if`, `_directive_elseif`, `_directive_else`, `_directive_endif` — the `#` symbol requires disambiguation from raw strings and other uses.
- **Contextual keywords**: `_async_keyword_custom`, `_throws_keyword`, `_rethrows_keyword` — these are contextually significant in Swift.

The tree-sitter external scanner API requires five functions: `create`, `destroy`, `scan`, `serialize`, and `deserialize`. The `serialize`/`deserialize` functions are critical for incremental parsing — when tree-sitter jumps to the middle of a file during re-parse, it must reconstruct the scanner's state from the serialized form.

KittyCode's GLR parser currently uses `Sources/KittyParser/GLRParser.swift` with grammar artifacts that exclude externals (`grammar.externals.isEmpty` check in `Sources/KittySyntax/LanguageHighlighter.swift`). Adding external scanner support requires:

1. **Scanner hosting**: Load and execute the C scanner functions alongside the grammar. This could use Swift's C interop (`@_silgen_name` or a bridging header) or compile the scanner into a small dynamic library.
2. **State serialization in incremental parsing**: The parser must save and restore scanner state at subtree boundaries for correct incremental re-parsing. Each parse tree node at the boundary of an external token region needs associated serialized scanner state.
3. **Grammar artifact format extension**: The grammar JSON and compiled parse table must carry external token declarations and their relationship to the scanner's validity array.
4. **Testing under incremental edits**: External scanner state bugs typically manifest as incorrect tokens after edits inside scanner-managed regions (e.g., editing inside a raw string). Incremental parsing tests with external scanners are essential.

#### Query Runtime Compatibility Gaps

The alex-pinkus highlights.scm query uses the following tree-sitter query features:

- **Predicates** (`#match?`): Used to distinguish keywords that share node types. KittyCode's `QueryMatcher` already supports predicates — this is compatible.
- **Alternations** (`["if" "else" "while"] @keyword`): Heavily used for keyword grouping. KittyCode's `QueryParser` supports alternation — this is compatible.
- **Field names** (`name:`, `body:`, `class_body:`): Used to target specific children. KittyCode's query system supports field matches — this is compatible.
- **Multiple captures per pattern**: Some upstream patterns capture multiple nodes (e.g., both a function name and its parameter list). KittyCode's `QueryMatcher` does not model multiple captures per pattern as first-class behavior — this needs work.
- **Quantifiers** (`*`, `+`, `?`): Used in parameter lists and repetitive structures. KittyCode's `QueryParser` consumes quantifiers syntactically but does not preserve quantifier semantics — this needs work.

The practical priority order for query runtime fixes:

1. Multiple captures per pattern — required for many structural queries
2. Quantifier semantics — required for matching repetitive constructs accurately
3. Compatibility testing harness — run upstream queries against reference parse trees and compare capture sets

#### Highlight Token Model Migration

The current pipeline in `Sources/KittySyntax/Highlighter.swift` converts captures directly into `StyledSpan` values. The `StyledSpan` carries only visual style (foreground color, background color, bold, italic) — no semantic role, no source layer, no modifier flags.

Introducing the proposed `HighlightToken` intermediate representation requires changes at three levels:

1. **Extraction**: Each highlight provider (`LexicalHighlighter`, `StructuralHighlighter`, future `SemanticHighlighter`) produces `[HighlightToken]` per line instead of `[StyledSpan]`.
2. **Merge**: A `HighlightMergeEngine` combines tokens from all active providers using the precedence rules (semantic > structural > lexical). For overlapping ranges at the same precedence, more specific roles win (e.g., `function.method` over `function`). The merge produces a non-overlapping, sorted `[HighlightToken]` sequence per line.
3. **Resolution**: The `ThemeResolver` maps `(HighlightRole, Set<HighlightModifier>)` to final `StyledSpan` values using hierarchical fallback. This replaces the current direct `capture_name -> style` lookup with `role + modifiers -> style`.

The performance impact is bounded: the additional intermediate step adds one allocation and one sort-merge pass per line per highlight update. For typical source files (100-500 visible lines, 5-20 tokens per line), this is well under 1ms.

#### SourceKit-LSP Integration Architecture

SourceKit-LSP provides semantic tokens for Swift through two layers:

1. **Syntax classification layer**: Uses SwiftSyntax to classify tokens from the parse tree. Maps `SyntaxClassification` cases to LSP semantic token types.
2. **Sourcekitd semantic layer**: Parses sourcekitd responses for deep semantic classification — `declClass`, `declStruct`, `declEnum`, `declMethodInstance`, `declFunctionFree`, `declVarLocal`, `declVarInstance`, etc.

Swift-specific semantic distinctions provided by SourceKit-LSP that syntax grammars cannot infer:

- **Actor vs. class vs. struct vs. enum**: All are bare identifiers in usage; only the declaration site reveals the kind. Semantic tokens classify reference sites by their declaration kind.
- **Type parameter references**: `T` in `func foo<T>(x: T)` — the parameter reference is visually identical to a type reference but semantically distinct.
- **Enum member references**: `.case` in pattern matching — distinguished from property access only by semantic analysis.
- **Default-library/builtin symbols**: `String`, `Int`, `Array`, `print` — the `.defaultLibrary` modifier distinguishes standard library types from user-defined types.
- **Static vs. instance members**: The `.static` modifier on property/method tokens.
- **Parameter labels at call sites**: `name:` in `foo(name: "bar")` — distinguished from dictionary keys or other label-like syntax.

The LSP semantic token protocol uses a delta-capable encoding:

- `textDocument/semanticTokens/full` returns all tokens as a flat integer array (5 integers per token: deltaLine, deltaStart, length, tokenType, tokenModifiers).
- `textDocument/semanticTokens/full/delta` returns incremental edits relative to a previous `resultId`, avoiding full retransmission after small edits.
- `textDocument/semanticTokens/range` returns tokens for a specific document range, enabling viewport-first rendering.

Integration with KittyCode requires:

1. **LSP client**: Spawn and manage the SourceKit-LSP process, handle initialization, and route notifications. This is shared infrastructure needed by multiple features (diagnostics, completion, etc.).
2. **Semantic token consumer**: Request tokens on document open and after edits (with debouncing). Decode the integer array into `HighlightToken` values with `source: .semantic`.
3. **Delta handling**: Track `resultId` and request deltas for efficiency. Fall back to full requests on mismatch.
4. **Merge with structural tokens**: The merge engine applies semantic > structural precedence. Regions without semantic coverage retain structural highlighting. This matches how VS Code, Neovim, and Zed all handle the layering.

### State of the Art: Syntax Highlighting Architectures

#### Tree-sitter Ecosystem (2025-2026)

Tree-sitter has become the dominant parsing technology for editor syntax highlighting. Neovim, Helix, Zed, and most new editors use it as their primary highlighting engine. VS Code remains the notable exception, still using TextMate grammars with LSP semantic tokens layered on top.

Key tree-sitter capabilities relevant to KittyCode:

- **Incremental parsing**: After `ts_tree_edit()` + `ts_parser_parse()`, only changed subtrees are recomputed. `ts_tree_get_changed_ranges()` returns the byte ranges that need re-highlighting, enabling minimal re-rendering.
- **Error recovery**: Tree-sitter produces useful trees even with syntax errors, inserting `ERROR` and `MISSING` nodes. This is critical for editors where code is almost always partially invalid during editing.
- **External scanners**: Required by most real-world languages for constructs that are not context-free. The alex-pinkus Swift grammar uses ~33 external token types.
- **Query language**: S-expression patterns with captures, predicates, field names, alternations, quantifiers, and anchors. The `highlights.scm` convention uses hierarchical names (`@keyword.function`, `@variable.builtin`) with theme fallback.

#### VS Code's Hybrid Model

VS Code uses a three-layer highlighting model:

1. **TextMate grammars**: Regex-based tokenization as the base layer. Still the primary highlighting engine.
2. **Semantic tokens from LSP**: Language servers push semantic classifications that augment or override TextMate.
3. **Theme resolution**: `semanticTokenColors` rules (highest priority) → semantic tokens mapped to TextMate scopes → standard `tokenColors` (lowest priority).

For Swift specifically, the effective highlighting in VS Code relies significantly on SourceKit-LSP semantic tokens, not only on a Swift grammar contribution. This is the reference quality bar that users compare against.

#### Neovim's Priority-Based Merge

Neovim uses `nvim_buf_set_extmark()` with a numeric priority system:

- Tree-sitter highlights: priority 100 (default)
- Individual query patterns can override via `(#set! priority 105)`
- LSP semantic tokens: typically priority 125 (overrides tree-sitter)
- Legacy Vim syntax highlighting: lower priority

The highest-priority extmark wins at each character position. Capture name resolution uses longest-match: `@comment.documentation.lua` falls back to `@comment.documentation` then to `@comment`.

#### Zed's Three-Mode Semantic Token Integration

Zed offers configurable semantic token modes per language:

- `off` (default): tree-sitter only
- `combined`: LSP semantic tokens augment tree-sitter (blended)
- `full`: LSP semantic tokens completely replace tree-sitter

This configurability is important because semantic token latency varies by language server. Slow servers can cause flickering if structural tokens are replaced too aggressively.

#### Helix's Tree-sitter-Native Approach

Helix is built entirely on tree-sitter with no TextMate layer. It supports the full tree-sitter query feature set and defines a comprehensive scope hierarchy with ~50+ recognized scopes. Resolution uses longest-match against the theme's scope definitions. Helix also supports tree-sitter injections for multi-language files.

### Recommended Technical Approach for KittyCode

#### Syntax Highlighting Pipeline: SOTA Architecture

1. **Three-layer provider model with explicit precedence**: Implement three distinct highlight providers, each producing `[HighlightToken]` per line:
   - `LexicalHighlighter`: Fast regex/pattern-based fallback. Always available. Handles keywords, strings, numbers, comments using simple lexical rules. Acts as the safety net when grammar or semantic providers are unavailable or for very large files where full parsing is too expensive.
   - `StructuralHighlighter`: Tree-sitter-based (or KittyCode's GLR parser-based) highlighting driven by grammar resources and highlight queries. Distinguishes syntactic roles: call sites vs. declarations, member access, punctuation classes, string interpolation structure, operator categories.
   - `SemanticHighlighter`: LSP semantic token consumer. Provides symbol-aware classifications: type kind (class/struct/enum/actor/protocol), declaration vs. reference, default-library markers, static modifiers, parameter labels.

   Merge precedence: semantic > structural > lexical. At each character position, the highest-available-layer token wins. The merge engine produces a single non-overlapping `[HighlightToken]` sequence per line for theme resolution.

2. **External scanner support via C FFI**: Add external scanner hosting to the parser runtime. Load scanner functions (`create`, `destroy`, `scan`, `serialize`, `deserialize`) via Swift's C interop. The `serialize`/`deserialize` pair is critical for incremental parsing correctness — the parser must save scanner state at reparse boundaries. Test extensively with edits inside scanner-managed regions (raw strings, nested comments, interpolations). This unblocks adoption of the modern alex-pinkus Swift grammar with its ~33 external token types.

3. **Query runtime extensions for upstream compatibility**: Close the two priority gaps in `QueryMatcher`:
   - **Multiple captures per pattern**: Allow a single pattern match to produce captures under different `@names`. This is needed for queries that reference multiple parts of a construct (e.g., both a function name and its return type annotation).
   - **Quantifier semantics**: Preserve `*`, `+`, `?` behavior so that quantified child patterns match correctly against repetitive structures (parameter lists, argument lists, array elements).
   Add a compatibility test harness that runs upstream `highlights.scm` queries against reference parse trees and compares the resulting capture sets to expected output.

4. **Viewport-first incremental highlighting**: On every edit, highlight the visible viewport first (Phase 1), then compute full-document highlights in the background (Phase 2):
   - Phase 1 (<1ms target): Re-parse incrementally. Run highlight queries only on the visible line range. Apply results to the display immediately.
   - Phase 2 (background): Run highlight queries on the full document. Stream results to the scrollbar annotation gutter and full-document token cache. Cancel and restart on each new edit.
   For semantic tokens, use `textDocument/semanticTokens/range` (LSP 3.17) for viewport-scoped requests, falling back to `full/delta` for incremental updates.

5. **Theme resolution with hierarchical role fallback**: Map `(HighlightRole, Set<HighlightModifier>)` pairs to styles using a hierarchical lookup:
   - Most specific: `function.method.static.declaration` → `function.method.static` → `function.method` → `function`
   - Modifiers narrow the match: `variable + {defaultLibrary}` matches `variable.defaultLibrary` if defined, otherwise falls back to `variable`.
   - The existing `Sources/KittySyntax/Theme.swift` hierarchical fallback can be extended to support this — the mechanism is already present, only the depth and modifier-awareness need to increase.

6. **Grammar source versioning and resource manifests**: Replace the implicit grammar generation path (`Scripts/generate-grammars.sh` defaulting to `tree-sitter` GitHub org) with explicit, versioned resource manifests per language:
   ```swift
   struct GrammarResourceManifest: Codable, Sendable {
       let languageId: String
       let source: GrammarSource
       let version: String
       let requiresExternalScanner: Bool
       let queryFeatures: Set<QueryFeature>
       let compatibilityNotes: String?
   }

   enum GrammarSource: Codable, Sendable {
       case bundled
       case repository(owner: String, repo: String, ref: String)
   }
   ```
   This makes the Swift grammar source explicit (`alex-pinkus/tree-sitter-swift` at a pinned ref) and allows the host to make informed compatibility decisions at load time rather than silently falling back.

7. **Capability reporting in status bar and tests**: Surface the active highlighting tier for each open buffer:
   - Status bar: `Swift: structural` or `Swift: structural + semantic` or `Swift: lexical fallback`
   - Test assertions: `XCTAssertEqual(highlighter.activeTier(for: "swift"), .structural)` or `.merged(.structural, .semantic)`
   - Degradation reporting: When a semantic provider is requested but unavailable, report `Swift: structural (semantic unavailable — SourceKit-LSP not found)` rather than silently degrading.

8. **Expanded Swift highlight queries (immediate win)**: Before any parser/runtime work, substantially expand the bundled `highlights.scm` for Swift within the constraints of the current compatible grammar:
   - Add `@boolean` for `true`, `false`
   - Add `@constant.builtin` for `nil`
   - Add `@keyword.function` / `@keyword.return` / `@keyword.conditional` / `@keyword.repeat` / `@keyword.exception` subcategories
   - Add `@punctuation.bracket`, `@punctuation.delimiter`, `@punctuation.special` for braces, commas, semicolons, interpolation delimiters
   - Add `@operator` for operators
   - Add `@comment.documentation` for `///` and `/** */` doc comments
   - Add `@function.call` where the current grammar can distinguish call sites
   - Add `@variable.builtin` for `self` and `super`
   - Update the lexical fallback to include newer keywords: `actor`, `macro`, `package`, `consuming`, `borrowing`, `nonisolated`

   This phase delivers the highest user-visible improvement with zero parser/runtime risk.

## SOTA Review and Accuracy Assessment

This section evaluates the ADR's technical claims and recommendations against verified state-of-the-art knowledge.

### Verified Accurate

1. **The distinction between lexical, structural, and semantic highlighting layers** is well-established in the industry. VS Code, Neovim, Zed, and Helix all implement some form of layered highlighting with explicit precedence. The ADR's three-tier model aligns with current best practice.

2. **The claim that VS Code Swift highlighting relies significantly on SourceKit-LSP semantic tokens** is verified. The `swiftlang/vscode-swift` extension provides a TextMate grammar fixture, but semantic distinctions (actor vs. class, enum members, default-library, type parameters) require the LSP semantic layer.

3. **The claim that the old tree-sitter-swift grammar is materially less capable** is verified. The tree-sitter/tree-sitter-swift repository was archived in February 2024 with a redirect to alex-pinkus. The old grammar cannot handle raw strings, implicit semicolons, custom operators, nested comments, or compiler directives.

4. **The architectural decision to normalize around a KittyCode-native token model** rather than adopting one external schema directly follows industry practice. VS Code uses its own internal token representation with adapters for TextMate and LSP. Neovim uses extmarks with priority-based stacking.

5. **The phased migration path** (expand compatible queries first → add token model → formalize compatibility → add external scanner support → add semantic highlighting) is well-sequenced and reflects realistic dependency ordering.

### Requires Qualification

1. **The claim that some query features are "not modeled as first-class behavior"** is accurate for multiple captures per pattern and quantifier semantics, but the practical impact may be less severe than implied. The alex-pinkus highlights.scm primarily uses predicates, alternations, and field names — features KittyCode already supports. The quantifier and multi-capture gaps affect a subset of patterns, not all upstream queries.

2. **The relationship between syntax-only and semantic highlighting** could be stated more precisely. The ADR correctly notes they are complementary, but the specific Swift constructs that require semantic analysis (actor/class/struct/enum distinction at usage sites, type parameter references, enum member references, default-library markers) should be enumerated explicitly so the scope of the semantic layer is concrete rather than aspirational.

### Risks Correctly Identified

1. **External scanner support is deeper parser/runtime work** — this is the most significant technical risk. The serialize/deserialize contract for incremental parsing is the hardest part and the most likely source of subtle bugs.

2. **Merge precedence can produce unstable output** — verified by industry experience. Zed provides configurable modes (off/combined/full) precisely because semantic token latency varies, and aggressive replacement can cause flickering.

3. **Capability reporting can drift from reality** — this is a genuine maintenance burden. The recommended approach of making capability a computed property of active provider state (rather than static configuration) is the right mitigation.

### External References

- Tree-sitter documentation: https://tree-sitter.github.io/tree-sitter/
- LSP 3.17 Semantic Tokens specification: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- VS Code Semantic Highlight Guide: https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide
- alex-pinkus/tree-sitter-swift: https://github.com/alex-pinkus/tree-sitter-swift
- apple/sourcekit-lsp: https://github.com/apple/sourcekit-lsp
- Neovim tree-sitter integration: https://neovim.io/doc/user/treesitter/
- Helix theme scopes: https://docs.helix-editor.com/themes.html
- Zed language extensions: https://zed.dev/docs/extensions/languages
