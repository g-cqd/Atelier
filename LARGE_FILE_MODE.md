# Large File Mode

## Problem

The current editor path assumes full-file materialization:

- file open decodes the entire file into one `String`
- `TextDocument` caches full text, full line arrays, and derived widths/byte counts
- grammar-backed highlighting operates on the whole source string
- the highlighter builds a per-byte style map for the entire document

That is fine for normal source files, but it scales poorly for large files and makes
windowed or paged rendering impossible without a lower-level abstraction change.

## Current Hot Paths

- `EditorState.readUTF8File(at:)` loads the whole file in one read/decode step
- `TextDocument` stores whole-document snapshots and derived caches
- `EditorState.refreshHighlights()` requests whole-document highlighting for grammar-backed sessions
- `LanguageHighlighter.highlightDocument(source:)` and `Highlighter.buildSpans(...)` process the full source

## Target

Add a large-file mode that keeps the current full-buffer behavior for normal files,
but switches oversized files to a windowed document provider with reduced
highlighting and viewport-driven reads.

## MVP Scope

1. Keep normal files on the current path.
2. Introduce a document access abstraction used by editor rendering and save logic.
3. Add a large-file threshold that selects a windowed implementation.
4. In windowed mode:
   - provide line count, visible line access, and incremental scroll reads
   - disable grammar-backed highlighting
   - allow plain or lexical line highlighting only
   - preserve detected line endings on save

## Proposed Interfaces

### `DocumentSource`

Required operations:

- `lineCount`
- `line(at:)`
- `lines(in:)`
- `replaceLines(in:with:)`
- `serializedByteCount`
- `save(to:lineEnding:)`
- `maxLineWidth(inVisibleRange:)`

Two implementations:

- `InMemoryDocumentSource`
- `WindowedFileDocumentSource`

### `HighlightStrategy`

Required operations:

- `highlightVisibleLines(...)`
- `invalidate(after:)`

Modes:

- `grammar`
- `lexical`
- `plain`

Large-file mode should never instantiate `grammar`.

## Migration Plan

1. Move editor reads from `fileContent`/`documentText` to a source abstraction.
2. Split whole-document caches into:
   - global metadata caches
   - viewport-local caches
3. Change render/highlight entry points to request only visible lines.
4. Add a large-file threshold and route oversized files to the windowed source.
5. Add fixtures for:
   - very long single lines
   - large multi-line logs
   - mixed line endings
   - save-after-edit in large-file mode

## Non-Goals

- grammar-accurate highlighting for arbitrarily large files
- random access edits with the same complexity guarantees as the current in-memory buffer
- replacing the current in-memory path for ordinary files

## Acceptance Criteria

- opening a large file does not require building a whole-document syntax-highlight buffer
- scrolling reads only the needed window plus a small margin
- edits in the visible window are persisted correctly
- save preserves line endings
- normal files keep the current behavior and test coverage
