# A custom text renderer for the diff panes: measurements, design, and a pluggable backend

- **Status:** proposal, 2026-09-23. Nothing in the repository changes with this document.
- **Code:** `main` at `c375952`. Every file:line below refers to that commit. The lab replicates the panes as they were at `10ae905`, the commit the other reviews studied. Between the two, commit `840d4e1` landed the GUI review's fixes 1 and 2 (sizes without layout when lines do not wrap, gutter walks bounded by the dirty rect) and the sticky card views; §1.3 says which findings it closed.
- **Machine:** Apple M3 (4 performance and 4 efficiency cores), 16 GB, macOS 26.7. Swift 6.4.0 release toolchain, macOS SDK 26.5, release builds.
- **Lab:** `/tmp/text-renderer-lab` holds the benchmark package, the inputs, the raw results and the API probe. The appendix shows how to rerun everything.
- **Related reviews, at `10ae905`:** `/tmp/reviews/perf-gui.md` (in-app GUI timings), `/tmp/reviews/perf-tui.md` (KittyCode), `/tmp/reviews/perf-core.md` (core engines), and `/tmp/reviews/gitdiffviewer.md` (findings B7, B8, S6, S7).

## Summary

**Do the panes use the latest TextKit?** Yes. Both panes run TextKit 2 end to end: `NSTextView(usingTextLayoutManager: true)` with an `NSTextLayoutManager` delegate that vends `DiffLayoutFragment` (DiffTextView.swift:71-88, EmbeddedDiffTextView.swift:65). Nothing reads `NSTextView.layoutManager`, so the TextKit 1 compatibility mode never engages.
- One TextKit 1 object remains: `NSLayoutManager().defaultLineHeight(for:)` (DiffPalette.swift:59). Its value equals the TextKit 2 line height, but no CoreText formula reproduces it across fonts (§1.3, finding 7), so M0 replaces it with a TextKit 2 measurement.
- The hover panel's text views and its measure are TextKit 2 already (probe: `textLayoutManager != nil`).
- Newer TextKit exists but sits above the floor. The 2027 releases let an `NSTextView` subclass act as its viewport controller's delegate, for line numbers, and add `NSTextViewportRenderingSurface` (macOS 27.0; WWDC 2026, session 370). The app's floor is macOS 26.1.

**What the measurements say.** Release builds, real Swift code, one 1000 × 800 pt viewport at 2×, system monospaced 12 pt, load 4-6 (§2).

| Operation | TextKit 2 as the app uses it | TextKit 2 used correctly | CoreText prototype |
|---|---|---|---|
| New document, end to end in a window, 5k / 50k rows | 69 ms / 7,034 ms | 12.7 ms / 25.5 ms | 3.8 ms / 3.8 ms |
| Smooth-scroll frame, main thread | 2.6 ms | 2.6 ms | 0.07 ms |
| Page scroll | 9.6 ms | 9.6 ms | 3.5 ms |
| Jump to the middle row, 5k / 50k | 12.6 / 24.3 ms, landing 11 % / 2 % off; 85 / 808 ms in a card's detached layout | 31.5 / 204 ms, exact (`relocateViewport`) | 4.0 / 3.8 ms, exact |
| Split alignment with wrapping, per pass, 5k | 256 ms | about 250 ms: both panes still laid out whole | 0.23 ms estimate, 99.96 % of rows exact, corrected off the main actor |
| Layout memory once a document is laid out, 5k / 50k | 24.8 / 237.8 MB | 0.3 / 0.5 MB without wrapping | 0.5 MB plus 4 bytes per row |
| Fallback-heavy rows (CJK, emoji, right-to-left), new document, the user's MapleMono | – | 176 ms | 7.8 ms |

Three findings matter whichever backend ships:
- **`DiffTextView.apply` is quadratic in attribute runs** when the storage holds a large previous text: 5.8 s for a 50,000-row re-render. Emptying the storage first makes it 11.3 ms (§2.4).
- **Tiles must be rasterized in the window's colour space;** sRGB tiles cost 5× more per new document, because Core Animation converts them on commit (§2.2).
- **Bidi overrides reorder code on screen today** (the Trojan Source class); both backends can reveal and neutralise them (§1.3, §3.7).

**Recommendation.**
1. **Finish M0 now** (§5). Its first fixes already landed in `840d4e1`: sizes without layout when lines do not wrap, and bounded gutter walks (in-app first text 1,253 → 70 ms, GUI review). The rest is small and local, first the quadratic storage replace (7,034 → 25.5 ms at 50k rows). One cost stays: with wrapping, split alignment still lays out whole documents (256 ms per pass at 5k rows), which only the renderer removes. M0 also lands the seam, so a second backend can arrive without disturbing users.
2. **TextKit used correctly closes most of the gap for the user's current setup** (inline, no wrapping). New documents and scrolling fit one 60 Hz frame for files up to about 5,000 rows, and the in-app floor becomes the SwiftUI view swap, not text: the renderer would take 9-22 ms off a 70-78 ms path.
3. **Build the renderer after M0 if the product wants what TextKit cannot give** (§2.9):
   - headroom for 120 Hz: 2.6× to 40× faster per operation;
   - exact jumps and a scroller that does not grow by 20 % while scrolling;
   - wrapping without whole-document layout: 256 ms → 0.23 ms per alignment pass;
   - fallback-heavy text 23× faster;
   - typesetting off the main actor, UTF-8 end to end, and one styled-run model shared with KittyCode.
   On the lab's inputs, two of the gate's performance conditions already hold (§5), and the request states the architectural goals. So the recommendation is to start M1 once M0 lands, time-boxed by its exit criteria, and to take M3 (Metal) only on measured need.

**Effort** (estimates, §6.3): the rest of M0 1.5-2 weeks; M1 3.5-5 weeks; M2 3-4 weeks; M3 3-4 weeks if triggered.

**Inputs from the other reviews.** All three reports landed before this section was written, and their numbers are used where cited: `perf-gui.md` for in-app timings, `perf-core.md` for the UTF-8 lexer and the flat token buffer, and `perf-tui.md` for the model KittyCode shares. No number here waits on another review.

## 1. The TextKit 2 surface the app depends on

### 1.1 How the panes work today

GitDiffViewer shows a diff in two kinds of pane.
- **The scrolling pane** (`DiffTextView`, an `NSViewRepresentable`) shows one file, inline or as one side of a split. It wraps `NSTextView.scrollableTextView()` and forces TextKit 2 (DiffTextView.swift:71-78). A `DiffGutterView` sits to its left and a `MinimapView` to its right, inside a `DiffPaneView` (DiffGutterView.swift:324-363).
- **The card pane** (`EmbeddedDiffTextView`) shows one file of a folder comparison, in a card of a SwiftUI `LazyVStack` (CombinedDiffView.swift:20-21, :97). Each card owns a detached TextKit 2 system (`StaticTextLayout`) that sizes the card, without layout when lines do not wrap and by laying out the whole document when they do, then lends its content storage to the card's `NSTextView` (EmbeddedDiffTextView.swift:178-193, StaticTextLayout.swift:22-101).

Both panes read one input, `RenderedText` (RenderedDiff.swift:74-130). It holds a single `NSAttributedString` for the whole document, with UTF-16 row starts, per-row metadata (`RowMeta`: change kind, line numbers, gap marker), a baseline offset and a line height. `DiffRenderer` builds it off the main actor (DiffRenderer.swift:166-288). The layout delegate `DiffFragmentProvider` gives every paragraph a `DiffLayoutFragment`, which draws the row background, the intraline emphasis and the diagnostic squiggles before the glyphs (DiffFragmentProvider.swift:23-40, DiffLayoutFragment.swift:35-50).

The panes are read-only. Nothing edits text, nothing takes text input, and no caret is shown.

### 1.2 Parity checklist

Marks: **needed** means a replacement must match it before users see the new backend; **nice** means users benefit but the app does not rely on it today; **unused** means the app does not use it.

| # | Capability | What the app relies on, and where | Mark | What a replacement must do |
|---|---|---|---|---|
| 1 | Text system | `NSTextView(usingTextLayoutManager: true)` in both panes (DiffTextView.swift:71-78, EmbeddedDiffTextView.swift:65); one `NSTextLayoutManager` delegate for panes and detached layouts (DiffTextView.swift:88, StaticTextLayout.swift:48, EmbeddedDiffTextView.swift:182) | needed | Own layout of rows; no TextKit object. |
| 2 | Read-only, selectable, plain text | `isEditable = false`, `isSelectable = true`, `isRichText = false`, `usesFontPanel = false` (DiffTextView.swift:79-82, EmbeddedDiffTextView.swift:66-69) | needed | Selectable, never editable; copy writes plain text. |
| 3 | Viewport layout | The view's viewport controller lays out visible fragments; explicit `layoutViewport()` after new text (DiffTextView.swift:252; EmbeddedDiffTextView.swift:190, only in a window) | needed | Typeset only rows that intersect the viewport and its overscan. |
| 4 | Whole-document layout for measurement | With wrapping: card height (StaticTextLayout.swift:78, :88), split row heights (RowSpacing.swift:13-19), `sizeToFit` and usage bounds (DiffTextView.swift:297, :381-382, :395). Without wrapping, sizes are arithmetic since 840d4e1 (StaticTextLayout.swift:61-65, :85-87; DiffTextView.swift:369-380). Minimap row lookup lays out the viewport (DiffTextView.swift:337-340) | needed as a result, not as a mechanism | Document height and per-row heights without typesetting every row: exact without wrapping, estimated then corrected with wrapping (§3.3). |
| 5 | Wrapping | Three modes: viewport width, fixed column, none (StaticTextLayout.swift:9-20); container width and tracking (DiffTextView.swift:261-300); column width from the advance of "0" (DiffPalette.swift:142-144) | needed | Same three modes, same column arithmetic. |
| 6 | Tabs and continuation indent | No tab stops, tab interval 4 spaces, wrapped lines indented 2 spaces (DiffRenderer.swift:250-254) | needed | Same tab interval and hanging indent. |
| 7 | Horizontal scrolling | Sideways elasticity only when a line is wider than the viewport (DiffTextView.swift:356-360, EmbeddedDiffTextView.swift:124-152) | needed | Same rule. |
| 8 | Line height and glyph centring | `lineHeightMultiple` from the theme; glyphs raised by half the extra space at draw time (DiffRenderer.swift:255-261, DiffLayoutFragment.swift:44-49, RenderedDiff.swift:84-88); the gutter follows the same offset (DiffGutterView.swift:283-290) | needed | Row height = font line height × multiple; baseline centred the same way. |
| 9 | Split row alignment when wrapping | Row heights of both panes, `RowAlignment.spacing`, then `paragraphSpacing` written row by row into the live storage (SplitPaneController.swift:92-122, RowSpacing.swift:25-50, StaticTextLayout.swift:121-138, AtelierDiff RowAlignment.swift:6-18) | needed | Paired rows share max(left, right) height, with no text mutation. |
| 10 | Overscroll | The last row can scroll to the top of the pane (DiffTextView.swift:364-399) | needed | Same trailing space. |
| 11 | Row backgrounds | Full-width fill per changed row, bounded surfaces (DiffLayoutFragment.swift:35-41, :117-130; DiffFragmentProvider.swift:34-37; DiffPalette.swift:95-107) | needed | Row fills across the content width. |
| 12 | Intraline emphasis | A custom attribute filled over the full line height (DiffRenderer.swift:195-198, :271-273, :320-324; DiffLayoutFragment.swift:52-71) | needed | Range fills over the full row height. |
| 13 | Diagnostic squiggles | Dashed underline per finding on the row's first line; an overlay "read on TextKit's drawing threads under a `Mutex`" (DiagnosticOverlay.swift:12; drawing at DiffLayoutFragment.swift:73-107); a change invalidates the whole layout (DiffTextView.swift:170-183) | needed | Underline decorations as a separate layer; a change redraws affected rows only. |
| 14 | Gap bands | At `c375952`, a "⋯ N hidden lines" row per gap (DiffRenderer.swift:205-212, :274-276). Since DIFF-02, a gap takes no row: one that offers a handle takes an empty band on the boundary between the rows around it, exactly one row tall (`RenderedText.gapBandHeight`). Between two rows the band is the row above's paragraph spacing (`DiffRenderer.addBands`), which `RowSpacing.apply` keeps under split alignment; above the first row and below the last it is the text's inset and trailing space (`StaticTextLayout.inset` and `bottomInset`; `DiffTextViewCoordinator.apply` and `updateOverscroll`), since TextKit ignores the spacing before a text's first paragraph and after its last. `DiffLayoutFragment` leaves the band uncoloured, and draws the separator of a band between two changes across the whole text. The gutter draws the split handle in the band, with its hover, drag, double-click, tooltip and resize cursors (`DiffGutterView.forEachGap`, `GapHandleLayout`) | needed | Same bands, with no row of their own, and exact unwrapped heights (rows × line height + bands); the gutter stays backend-neutral. |
| 15 | File header rows | Bold title rows in combined documents (DiffRenderer.swift:213-217, :277-284) | needed | Bold style run. |
| 16 | Syntax colours | Foreground colour per token (DiffRenderer.swift:187-194, :268-270; DiffPalette.swift:86-93) | needed | Style runs resolved per appearance. |
| 17 | Gutter synchronisation | Gutter walks the laid-out fragments of the dirty rect for y, height and first baseline (DiffGutterView.swift:14-29, :231-303); redraws on every clip-view scroll (DiffGutterView.swift:132-135) | needed | Row geometry query by rect (§4.1). |
| 18 | Minimap | Bars rasterized from rows, no text layout (MinimapView.swift:89-157); visible rows from TextKit (DiffTextView.swift:318-344); click scrolls to a row (DiffTextView.swift:106-109) | needed | Visible rows and scroll-to-row from the backend. |
| 19 | Hover hit-testing | Point → fragment → line fragment → UTF-16 index → identifier (HoverHitTester.swift:32-88); anchor re-measured on scroll (HoverHitTester.swift:93-116, DocHoverController.swift:103-121); tracking area on the text view (DocHoverController.swift:55-71) | needed | Point → row → grapheme-snapped offset; rect for a range. |
| 20 | Scroll to row | Change navigation, minimap, scroll requests (DiffTextView.swift:188-191, :302-315) | needed | O(log rows), no layout above the target. |
| 21 | Scroll position kept on re-render | (DiffTextView.swift:229, :246) | needed | Same. |
| 22 | Synchronised split scrolling | Clip-view bounds mirrored (SplitPaneController.swift:40-51, :76-88) | needed | Unchanged if the backend keeps `NSScrollView`. |
| 23 | Selection | NSTextView mouse selection, double-click word, triple-click paragraph, shift-extend, select all; colour from the palette (DiffTextView.swift:80, :232; EmbeddedDiffTextView.swift:184); kept across spacing changes (TextLayoutTests.swift:96-118) | needed | Character, word and row granularity, drag autoscroll, ⌘A. |
| 24 | Copy | NSTextView `copy:`; plain text because `isRichText = false` (DiffTextView.swift:81) | needed | Plain text on the general pasteboard. |
| 25 | Find | Not enabled: `usesFindPanel` and `usesFindBar` are both `false` on these views (probe), and no code sets them | unused | Nice to add through `NSTextFinder` (§3.9). |
| 26 | Accessibility | NSTextView's defaults: role `AXTextArea` (probe), value, selection, line and range queries. The gutter and minimap expose nothing, and change kinds are colour-only | needed | `NSAccessibilityNavigableStaticText` and the selection attributes (§3.9). |
| 27 | Context menu, Look Up, Services, text drag | NSTextView defaults; no code customises them | nice | Copy and Look Up first. |
| 28 | Appearance changes | Dynamic `NSColor`s resolved at draw time (DiffLayoutFragment.swift:38, :63; DiffGutterView.swift:257-260; DiffTextView.swift:230-232) | needed | Re-resolve colours and re-render tiles on appearance change. |
| 29 | Font change | A new palette font re-wraps (DiffTextView.swift:224, :236-240) | needed | Re-typeset visible rows, rescale heights. |
| 30 | Measure first, show later | Detached layout lends its storage to the card's view (EmbeddedDiffTextView.swift:178-201) | needed as a result | Heights without a view; show without re-measuring. |
| 31 | Editing, undo, input methods, spell checking, Writing Tools, insertion point, printing | `insertionPointColor` set (DiffTextView.swift:231) but no caret shows; nothing else | unused | Nothing. |
| 32 | Hover panel text | Rich prose with links in separate `NSTextView`s (HoverDocPanel.swift:417-438) | out of scope | Stays on NSTextView. |

### 1.3 What the checklist surfaced

These are defects or risks in today's code, found while building the checklist. They matter for any backend.

1. **Replacing a live text storage is quadratic in attribute runs.** `apply` calls `setAttributedString` on a storage that still holds the previous render (DiffTextView.swift:233-235). Measured in §2.4: 173 ms at 20,556 runs, 2.4 s at 75,796 runs, 5.8 s for a 50,000-line file (127,388 runs). Emptying the storage first in the same transaction makes it linear: 11.3 ms at 50,000 lines. Every re-render of the single-file pane takes this path (a gap drag, a palette or mode change, a reload), and so does switching between two large files (73.5 ms at 8,000 rows, 344 ms at 16,000).
2. **Split alignment rewrites paragraph styles row by row on a live storage.** `RowSpacing.apply` (RowSpacing.swift:31-48) is superlinear: 6.2 ms at 4,000 lines and 515 ms at 50,000 lines when one row in three changes (§2.4). It runs after every debounced resize in the default configuration (split view and wrapping on: ViewerSettings.swift:271, :276).
3. **The minimap caches its bars by size only** (MinimapView.swift:40-42). It rasterizes dynamic colours at the window's backing scale of the moment (MinimapView.swift:90). A light/dark switch or a move to a display with another scale keeps the old bars until the pane is resized.
4. **Bidi overrides reorder code on screen.** No code handles U+202A–U+202E or U+2066–U+2069. The probe shows CoreText, and therefore TextKit, displaying `abc⟨RLO⟩def⟨PDF⟩ghi` as `abcfedghi`. A reviewer can be shown code that differs from what compiles (the "Trojan Source" class, CVE-2021-42574). §3.7 fixes it for the new backend; the TextKit backend can fix it in `DiffRenderer` by substituting visible placeholders.
5. **Change kinds are colour-only for assistive technology.** VoiceOver reads the text but not whether a row was added or removed (§3.9 adds rotors).
6. **Find is off.** Users cannot search a pane with ⌘F (probe: `usesFindPanel == false`, `usesFindBar == false`).
7. **One TextKit 1 object remains, and its value is not a simple CoreText formula.** `NSLayoutManager().defaultLineHeight(for:)` (DiffPalette.swift:59) is built for every palette. It always matched the height of a TextKit 2 line fragment in the lab, but no single CoreText rule reproduces it at 12 pt:

   | Font | ascent + descent | TextKit 1 and TextKit 2 line | ceil(ascent) + ceil(descent) | round(ascent + descent) |
   |---|---|---|---|---|
   | System monospaced | 14.13 | 15 | 15 | 14 |
   | MapleMono NF CN (the user's) | 15.84 | 16 | 17 | 16 |
   | SF Mono (file font) | 14.32 | 14 | 15 | 14 |
   | Menlo | 13.97 | 14 | 15 | 14 |

   Replace it with a one-line TextKit 2 measurement per font, and pass that one value to both backends (§5, M0 item 9). A renderer that derives its own line height disagrees with TextKit by a point per row on some fonts.

**Since `10ae905`.** Commit `840d4e1` closed three of the review findings this document measures: whole-document layout when lines do not wrap (StaticTextLayout.swift:61-65, :85-87; DiffTextView.swift:265-278, :369-380), the gutter's walks over every fragment (B8: DiffGutterView.swift:79-95, :161-168, :231-254), and the throwaway card layouts (S6: CombinedDiffView.swift:211). Still open at `c375952`: findings 1-7 above, whole-document layout when lines wrap (StaticTextLayout.swift:78, :88; RowSpacing.swift:13-19), B7 (RenderPipeline.swift:142-165) and the relayout on every diagnostics change (DiffTextView.swift:170-183).

## 2. Measured baseline against a prototype

### 2.1 Method

**Inputs.**

| Input | Rows | Source | UTF-8 | Line length (UTF-16 units) | Non-ASCII rows |
|---|---|---|---|---|---|
| `swift-5k` | 5,000 | 46 real Swift files, concatenated in path order | 171 KB | median 30, p90 71, p99 114, max 179 | 65 (1.3 %) |
| `swift-50k` | 50,000 | 684 real Swift files, same way | 1.64 MB | median 28, p90 71, p99 109, max 179 | 548 (1.1 %) |
| `unicode-5k` | 5,000 | generated worst case: CJK, emoji ZWJ sequences, Arabic, Hebrew, Devanagari, combining marks, box drawing on every row | 330 KB | – | 5,000 (100 %) |

The Swift inputs come from the local `develop-video` checkout and are never printed; only the statistics above leave the lab. Tokens come from a verbatim copy of `AtelierSyntaxModel` and `AtelierLexers`: 6,321 lexical tokens for 5,000 rows, 60,299 for 50,000.

**What the lab replicates of the app.**
- The attributed string exactly as `DiffRenderer.attributed` builds it (DiffRenderer.swift:246-288): system monospaced 12 pt, no tab stops, tab interval and hanging indent from the space advance, line height multiple 1, one colour per token, an emphasis attribute on changed rows. One row in 17 is marked added and one in 23 removed.
- `DiffFragmentProvider` (offset → binary search → row background) and `DiffLayoutFragment.draw` (background, emphasis enumeration, glyphs).
- `RowSpacing.rowHeights` and `RowSpacing.apply`, and `DiffTextView.apply`.
- `NSTextView.scrollableTextView()` configured as `DiffTextView.makeNSView` configures it, in an offscreen window. Its container tracks the view, so rows wrap at the viewport width as in a pane with the default settings; with a p99 row of 109-114 units, under 1 % of rows are long enough to wrap. Each step scrolls, calls `layoutViewport()`, displays the window and flushes the Core Animation transaction, so drawing and commit are inside the measurement; a counter in the fragment confirms 54 fragments drawn per screen.

**The CoreText prototype.** One `CFAttributedString` per row from the UTF-8 bytes (`CFStringCreateWithBytes`), token offsets mapped UTF-8 → UTF-16 (identity on ASCII rows), a `CTTypesetter` with `kCTTypesetterOptionForcedEmbeddingLevel = 0`, and `CTTypesetterSuggestLineBreakWithOffset` for wrapping with the two-space hanging indent. Drawing uses `CTLineDraw`, or glyph runs extracted once and drawn with `CTFontDrawGlyphs`. The window host puts rows in tiles of 32, one `CALayer` each, and rasterizes a missing tile synchronously on the main actor, so its numbers are the worst case a prefetcher would hide.

**Common settings.** A 1000 × 800 pt viewport at 2× backing: 54 rows of 15 pt. Wrapping, when on, at 600 pt. Release builds, Swift 6.4.0.

**Statistics.** Warm-up of 1-5 runs, then 7-240 measured runs per case; the tables give the median with the p10-p90 spread. Allocation events come from a `malloc_logger` hook in separate, untimed runs; retained memory from `malloc_zone_statistics` before and after.

**Contention.** Other agents compiled on the same machine. The load average ranged from 4 to 45 on 8 cores. Every table states the load of its run. Round 1 and round 3 ran at load 4-6 and are the primary numbers; round 3 repeated each end-to-end case three times, and the three medians agree within 10 %. Round 2 ran at load 9-36; its numbers are compared only with each other.

### 2.2 End to end in a window

Round 3, load 4.6-5.2, median of three medians (p10-p90 of the middle run). The TextKit column already includes the storage fix of §2.4; without it, the same operation is in the last row.

| Operation | Rows | TextKit 2 `NSTextView` | CoreText tiles, window colour space | Ratio |
|---|---|---|---|---|
| New document: text in, first screen laid out, drawn, committed | 5k | 12.7 ms (12.3-13.6) | 3.8 ms (3.7-4.4) | 3.4× |
| | 50k | 25.5 ms (24.8-26.1) | 3.8 ms (3.7-4.1) | 6.7× |
| Smooth scroll, 3 rows per frame, main thread per frame | 5k | 2.55 ms (2.25-3.23) | 0.068 ms (0.066-0.131) | 38× |
| | 50k | 2.64 ms (2.42-3.47) | 0.066 ms (0.065-0.089) | 40× |
| Page scroll, one screen per step | 5k | 9.6 ms (8.6-10.7) | 3.5 ms (1.9-4.3) | 2.7× |
| | 50k | 8.9 ms (7.9-10.1) | 3.4 ms (1.8-4.0) | 2.6× |
| Jump to the middle row, the app's way (`ensureLayout` at the row) | 5k | 12.6 ms, lands 11.4 % short of the true position | 4.0 ms, exact | 3.2× |
| | 50k | 24.3 ms, lands 2.1 % short | 3.8 ms, exact | 6.4× |
| Jump with `relocateViewport(to:)` | 5k | 31.5 ms, within 0.2 %, lays out all 2,498 rows above | – | – |
| | 50k | 204 ms, within 0.1 %, lays out all 24,998 rows above | – | – |
| New document without the storage fix (today's `apply`, round 1, load 4.9) | 5k | 69.3 ms (68.0-70.4) | – | – |
| | 50k | 7,034 ms (6,247-12,359) | – | – |

What these say:
- **CoreText tiles win every end-to-end case, by 2.6× to 40×.** The largest gap is the smooth-scroll frame: a tile that already exists costs a layer move and a commit (0.07 ms); TextKit lays out and draws the rows that enter (2.5 ms, 3,711 allocations per frame against 131).
- **Fixed TextKit stays inside one 60 Hz frame** (16.7 ms) for everything except a 50k-row new document (25.5 ms) and a 50k-row jump (24.3 ms). It misses a 120 Hz frame (8.3 ms) on new documents, page steps and jumps.
- **TextKit's cheap jump is inexact.** Its layout manager estimates the position of rows it has not laid out, so the target row lands where the estimate puts it; `relocateViewport(to:)` is exact but lays out everything above. The tile host knows every position from the height index.
- **Tiles must be rasterized in the window's colour space.** The same host with sRGB tile images costs 20.4 ms (5k) and 20.7 ms (50k) per new document: Core Animation converts each 7.7 MB tile on commit (15.7 MB allocated per new document). Letting the layers draw themselves costs the same as colour-matched images (3.9 ms), with the drawing on the main actor.

### 2.3 Components, per viewport

Round 1, load 4.2-5.5 unless marked. Detached text systems (no view), so this isolates layout and drawing from AppKit.

| Step | Rows | TextKit 2 | CoreText | Ratio |
|---|---|---|---|---|
| Lay out the first screen | 5k | 1.98 ms (54 fragments) | 0.47 ms | 4.2× |
| | 50k | 2.84 ms | 0.39 ms | 7.3× |
| Draw one screen into a 2× bitmap | 5k | 2.81 ms | 1.35 ms with `CTLineDraw`, 0.67 ms with `CTFontDrawGlyphs` | 2.1-4.2× |
| | 50k | 2.55 ms | 1.17 ms, 0.54 ms | 2.2-4.7× |
| Text in + first screen laid out (no view) | 5k | 3.12 ms | 1.88 ms including drawing | – |
| | 50k | 17.5 ms (9.9 ms of it copying 1.6 MB into the storage) | 1.63 ms including drawing | – |
| Next screen, laid out and drawn | 5k | 9.80 ms (p90 13.9) | 1.78 ms | 5.5× |
| | 50k | 26.4 ms (p90 31.1) | 1.52 ms | 17× |
| With wrapping at 600 pt: first screen | 5k | 2.05 ms (51 fragments) | 0.42 ms | 4.9× |
| | 50k (load 15.6) | 2.38 ms | 0.88 ms (load 5.1) | – |
| One 32-row tile rasterized in a child task | 5k | – | 1.86 ms (1.70-2.24) | – |
| Two tiles in parallel (one screen) | 5k | – | 2.39 ms (2.16-2.81) | – |

Per row, TextKit's layout costs 37 µs and the prototype's typesetting 8.7 µs at 5k (7.1 µs at 50k), attributes and UTF-8 bridging included.

### 2.4 Putting text into TextKit

`DiffTextView.apply` replaces the whole storage in one editing transaction (DiffTextView.swift:233-235). The cost depends on what the storage held before.

Content storage, no view. Round 1 (load 5-13 falling) and round 2 (load 9-10, the last three columns).

| Rows | Attribute runs | Into an empty storage | Replacing the same text (a re-render) | Emptied first, then set | New `NSTextStorage` swapped in | Replacing a different text of the same size | Replacing a 50-row text |
|---|---|---|---|---|---|---|---|
| 1,000 | 2,066 | 0.85 ms | 2.13 ms | 0.74 ms | 1.40 ms | 1.25 ms | 0.79 ms |
| 4,000 | 11,247 | 1.35 ms | 52.6 ms | 1.25 ms | 0.83 ms | 16.9 ms | 1.58 ms |
| 8,000 | 20,556 | 2.34 ms | 173 ms | 1.95 ms | 1.27 ms | 73.5 ms | 2.64 ms |
| 16,000 | 39,666 | 4.53 ms | 577 ms | 3.80 ms | 2.28 ms | 344 ms | 6.76 ms |
| 32,000 | 75,796 | 7.84 ms | 2,371 ms | 6.62 ms | 4.04 ms | – | 14.3 ms |
| 50,000 | 127,388 | 14.1 ms | 5,786 ms | 11.3 ms | 6.69 ms | – | 16.6 ms |

- Replacing a storage that holds a large text is quadratic in attribute runs: from 11,247 runs up, the time grows with the runs to a power of 1.7 to 2.2 between successive sizes. It happens for every re-render of the same file (a gap drag, a palette or mode change, a reload) and when switching between two large files.
- Emptying the storage first, in the same transaction, makes it linear: 5,786 ms → 11.3 ms at 50,000 rows, 173 ms → 1.95 ms at 8,000. In the real `NSTextView` it takes a new document from 69.3 ms to 12.7 ms (5k) and from 7,034 ms to 25.5 ms (50k) (§2.2; rounds 1 and 3, at load 4.5-5.2).
- Split alignment writes paragraph spacing row by row into the live storage (RowSpacing.swift:31-48). With one row in three changing: 1.26 ms at 1,000 rows, 6.19 ms at 4,000, 54.3 ms at 16,000, 515 ms at 50,000.

### 2.5 Whole-document work

| Work | Rows | TextKit 2 | CoreText | Load |
|---|---|---|---|---|
| Lay out every row without wrapping (what cards did before `840d4e1`) | 5k | 178 ms, 5,000 fragments, 476,582 allocations | not needed: heights are arithmetic without wrapping | 4.7 |
| | 50k | 1,141 ms, 4.6 M allocations, 464 MB allocated | not needed | 4.2 |
| Lay out every row, wrapping at 600 pt (cards and split alignment today) | 5k | 204 ms | estimate 0.23 ms; exact typeset 42.2 ms on one core, 25.6 ms on 8 tasks | 4.5 |
| | 50k | 3,122 ms (load 15.6) | estimate 2.1 ms; exact 346 ms on one core, 218 ms on 8 tasks | 5.1 |
| Split alignment pass (both panes laid out, row heights read, spacing written) | 5k | 256 ms (253-265), 978,239 allocations | shared height table: O(changed rows · log rows) | 4.9 |
| | 50k | 5,465 ms, against 1,687 ms for one whole layout in the same run | – | 12.7 |
| Height estimate accuracy with wrapping | 5k | – | 4,998 of 5,000 rows exact, error 30 pt of 80,640 | 4.5 |
| | 50k | – | 49,909 of 50,000 rows exact, error 1,365 pt of 805,110 (0.17 %) | 5.1 |
| Jump to the middle row in a detached layout (cards) | 5k | 85 ms, lays out 2,554 fragments | 1.9 ms | 4.7 |
| | 50k | 808 ms, lays out 25,054 fragments | 1.5 ms | 4.2 |
| Gutter walk over every fragment of a card (B8, fixed in `840d4e1`), per draw | 5k | 5.4 ms | O(rows in rect) | 4.7 |
| | 50k | 100 ms | O(rows in rect) | 4.2 |

- **Document height.** A detached layout manager reports usage bounds for laid-out text only: 810 pt after the first screen of a 75,000 pt document. `NSTextView` estimates the rest: 72,093 pt against a true 75,008 pt after a new document, 91,198 pt after scrolling 36,000 pt, and 80,600 pt after a `relocateViewport` jump (5k); 692,446 → 955,970 pt for a true 750,008 pt (50k). The scroller's size and position follow these estimates.
- **Parallel typesetting** gains 1.6-2.8× over one core on this 4 + 4-core machine (8 tasks or 64 chunks, rounds 1 and 2). It is background work either way.

### 2.6 Memory and allocations

| What is kept | 5k | 50k |
|---|---|---|
| TextKit: storage | 592 KB | 5.6 MB |
| TextKit: first screen laid out | 264 KB | 534 KB |
| TextKit: every row laid out | 24.8 MB | 237.8 MB |
| CoreText: three screens of typeset lines | 501 KB | 488 KB |
| CoreText: height index | 20 KB | 208 KB |
| CoreText: document bytes (UTF-8) | 172 KB | 1.65 MB |

| Allocations per operation | TextKit 2 | CoreText |
|---|---|---|
| First screen laid out | 4,946 | 3,027 |
| Smooth-scroll frame, end to end | 3,711 (547 KB) | 131 (6 KB) |
| New document, end to end (5k) | 30,047 (4.0 MB) | 4,627 (557 KB) |
| Every row laid out, 50k | 4,625,011 (464 MB) | 2,887,868 (275 MB) to typeset every row once, and it keeps none of it |

### 2.7 UTF-8 against UTF-16

Round 1: `swift-5k` at load 4.7; `unicode-5k` at load 38, so its absolute values are inflated.

| Cost per row | Real code (98.7-98.9 % ASCII rows) | `unicode-5k` (every row non-ASCII) |
|---|---|---|
| Is the row ASCII (8 bytes at a time) | 7.0 ns | 3.6 ns (exits at the first non-ASCII byte) |
| Map every token offset UTF-8 → UTF-16 | 3.1 ns | 127 ns |
| Build the row's CFString: `CFStringCreateWithBytes` (UTF-8) | 129 ns | 823 ns |
| … a bridged Swift `String` | 86 ns | 684 ns |
| … transcode to UTF-16, then `CFStringCreateWithCharacters` | 327 ns | 1,484 ns |
| Typeset the row (`CTLine`, attributes included) | 8.5-10.9 µs | 131-175 µs |

- Keeping text in UTF-8 costs under 2 % of typesetting on real code, and under 1 % on the worst case. At 5k rows, the three string constructions typeset within 6 % of each other (10.3-10.9 µs per row); the 50k run, at load 44, is too noisy to separate them.
- The costs that matter are elsewhere: the lexer's UTF-16 path (157 ms against 7.0 ms per 50k-line pair, perf-core.md) and fallback-heavy text (15× the typesetting cost per row, §2.8).
- The attributed string for 5,000 rows takes 3.87 ms to build; the flat run model takes 0.54 ms.

### 2.8 The user's font and fallback-heavy text

Round 4. MapleMono NF CN 12 pt, the font the GUI review found in the user's settings. Load 4.2-4.8 except where marked. A TextKit screen holds 50 rows at this font's 16 pt line; the prototype's holds 48, because it derived 17 pt (§1.3, finding 7), so per-row costs are the fair comparison.

| `swift-5k`, MapleMono | Ligatures and contextual alternates on (as installed) | Both off |
|---|---|---|
| TextKit: first screen laid out | 2.79 ms, 56 µs per row | 1.76 ms, 35 µs per row |
| CoreText: first screen typeset | 1.35 ms, 28 µs per row | 0.36 ms, 7.5 µs per row |
| CoreText: first screen typeset and drawn | 2.36 ms | 1.46 ms |
| `NSTextView`: new document, end to end | 10.7 ms (10.5-11.0) | 9.0 ms (8.9-9.3) |
| Tiles: new document, end to end | 4.9 ms (4.8-5.5) | 3.3 ms (3.2-3.6) |
| `NSTextView`: smooth-scroll frame | 1.89 ms (1.66-2.40) | 1.69 ms (1.56-1.97) |
| Tiles: smooth-scroll frame | 0.056 ms (0.053-0.132) | 0.056 ms (0.053-0.092) |
| Every row, one core: TextKit layout / CoreText typesetting | 269 ms / 150 ms | 196 ms / 65 ms (load 17-20) |

- **Contextual alternates dominate CoreText's cost with this font.** They multiply the per-row typesetting cost by 3.7 (7.5 → 28 µs), against 1.6 for TextKit (35 → 56 µs). With the user's font as installed, the prototype typesets 2× faster than TextKit per row, not 4-7× as with the system font.
- **End to end, tiles still win by 2.2× on a new document and 34× per smooth-scroll frame**, because a frame that needs no new tile does no typesetting at all.
- **The GUI review's trade-off stands:** turning the features off halves full layout (180 → 90 ms for L in the app), but a viewport-only layout makes it matter little.

| `unicode-5k`, MapleMono, ligatures on | TextKit 2 | CoreText | Ratio |
|---|---|---|---|
| First screen laid out or typeset | 89.8 ms (1.8 ms per row) | 3.85 ms (80 µs per row) | 23× |
| New document, end to end | 176 ms (132-230) | 7.8 ms (7.2-9.3) | 23× |
| Smooth-scroll frame | 8.2 ms (2.2-14.4) | 0.056 ms (0.052-0.176) | 146× |

- Rows that mix CJK, emoji, Arabic, Hebrew and Devanagari cost TextKit 1.8 ms each to lay out (109 ms per screen with the system font, at load 15). The prototype pays 80 µs.
- In a detached layout, the first draw of such a screen typesets it, and two profiles of that draw spend 86 % and 91 % of their samples resolving each paragraph's base writing direction (`-[NSTextParagraph _resolvedBaseWritingDirectionWithFallbackDirection:]` → `CFAttributedStringGetStatisticalWritingDirections`). The case's 37 fresh layouts ran for 6 min 41 s, several seconds each. Inside an `NSTextView` the same document costs 176 ms end to end, so the view limits the damage, but cards start from a detached layout. The prototype does no such resolution: it forces the embedding level (§3.7).
- `NSTextView`'s smooth scrolling misses a 120 Hz frame at the median and a 60 Hz frame at p90 on such text. Localized string tables and test fixtures in other scripts are ordinary files in a diff.

### 2.9 What TextKit 2 used correctly closes, and what remains

TextKit 2 "used correctly" means: viewport layout only, no whole-document `ensureLayout`, analytic sizes without wrapping, the storage emptied before a new text, rendering attributes for colour, and gutter walks bounded by the dirty rect. The GUI review measured most of this in the real app, and its fixes 1 and 2 have since landed (`840d4e1`):
- publish → first text: 616 → 78 ms (L, 2,374 rows) and 1,253 → 70 ms (XL, 9,292 rows), with the SwiftUI view swap as the remaining floor;
- stage-0 text first, end to end: 10.9 / 15.1 / 25.6 ms (M / L / XL) against 72 / 454 / 2,163 ms today;
- expanding a 9,027-row card: 2,346 → 40 ms; a gutter tile: 292 → 1.3-2.0 ms (L).

**Closed by M0, with no new renderer:**
- the quadratic storage replace, and the whole-document layouts and gutter walks of unwrapped panes (the last two already, in `840d4e1`);
- new documents within one 60 Hz frame at 5k rows (12.7 ms of text work), and 25.5 ms at 50k;
- smooth scrolling within a 120 Hz frame (2.6 ms per frame).

**Not closed by M0:** with wrapping, split alignment and card heights still lay out every row: 256 ms per alignment pass at 5k rows, 5.5 s at 50k (§2.5).

**What a custom renderer still wins:**
- **Speed where it compounds:** 3.4-6.7× on a new document, 38-40× per smooth-scroll frame, 2.6× per page, 3-6× on jumps (§2.2). This moves every operation measured here inside a 120 Hz frame, which fixed TextKit does not reach for new documents, pages and jumps.
- **Exact geometry.** Jumps land on the row, and the scroller never grows or shrinks by 20 % under the user (§2.5).
- **Wrapping without whole-document work.** Split alignment and card heights need every row laid out in TextKit: 204 ms (5k) to 3.1 s (50k) per pass, plus the row-by-row spacing writes (§2.4-2.5). The renderer estimates heights in 0.23-2.1 ms, 99.8 % exact, and corrects them off the main actor.
- **Typesetting and rasterizing off the main actor**, with only `Sendable` values crossing (§3.4). TextKit's view layout is main-actor work.
- **UTF-8 end to end and a typed attribute model** shared with KittyCode (§3.2), instead of one `NSAttributedString` with `@unchecked Sendable` around it (RenderedDiff.swift:74).
- **Memory bounded by the viewport:** 0.5 MB of lines and 4 bytes per row, against 24.8-237.8 MB once TextKit has laid out a document.
- **Control over what is shown:** bidi controls revealed and neutralised, typographic features per run, a renderer reusable outside this app.

**What it does not win:** the in-app floor. With M0, the GUI review's 70-78 ms publish → first text is dominated by the SwiftUI view swap, not by text. The renderer saves 9 ms (5k rows) to 22 ms (50k rows) of text work per new document (§2.2), roughly 11-30 % of that path.

## 3. Design of the renderer

The renderer is a CoreText engine that knows nothing about diffs, and an AppKit host view that shows it. GitDiffViewer maps its rows, gaps, emphasis and diagnostics onto the engine's generic model.

### 3.1 Targets and tiers

| Target | Package | Tier (AGENTS.md) | Links | Contents |
|---|---|---|---|---|
| `AtelierSyntaxModel` (exists) | `Packages/AtelierCore` | core | nothing | Adds the flat per-line token buffer from the core review (M1): one `tokens` array plus `offsets: [UInt32]`, a 12-byte `LineToken`. This is the styled-run model KittyCode shares; the TUI review asks for the same (§4 there). |
| `AtelierTextRendering` (new) | `Packages/AtelierCore` | core | CoreText, CoreGraphics, `AtelierSyntaxModel` | The typed document model, style sheets, the height index, per-row typesetting, tile rasterization. Pure functions and value types; no AppKit, no QuartzCore, no tasks of its own. |
| `AtelierTextView` (new) | `Packages/AtelierCore` | core | AppKit, QuartzCore, SwiftUI, `AtelierTextRendering` | The `@MainActor` host view, tiles as layers, selection, copy, `NSTextFinderClient`, accessibility, the SwiftUI representable. |
| `DiffTextKit` (exists) | `Apps/GitDiffViewer` | app models | both of the above | The backend seam (§4), the TextKit 2 adapter, the CoreText adapter, the gutter and the minimap. |

Why the core tier for both new targets:
- The engine is shared infrastructure with no diff knowledge, and AGENTS.md reserves the `Atelier` prefix for shared core targets.
- The core rules fit a renderer: "no unstructured tasks and no `TaskProvider`: a core service exposes `async` functions, task groups and `AsyncStream`s the caller drives". The host exposes `run() async`, which the app drives from SwiftUI's `.task` or from its `TaskProvider` (§3.4).
- KittyCode links products one by one, so it never links `AtelierTextView`. It links `AtelierSyntaxModel` only, and shares the model, not the renderer.
- `AtelierTextView` would be the first core target to import AppKit. If that should stay out of `AtelierCore`, a sibling package `Packages/AtelierUI` holds it under the same rules; nothing else changes.

### 3.2 The attribute model

Text stays UTF-8 from the file to the typesetter. UTF-16 appears only inside one function per line, at the CoreText boundary, and in the offsets AppKit's protocols demand (§3.9).

```swift
/// A byte offset into one row's UTF-8 text.
public struct ByteOffset: Hashable, Comparable, Sendable { public var rawValue: Int32 }
/// A UTF-16 offset, only at AppKit and CoreText boundaries.
public struct UTF16Offset: Hashable, Comparable, Sendable { public var rawValue: Int32 }
public struct RowIndex: Hashable, Comparable, Strideable, Sendable { public var rawValue: Int32 }
/// A position in the document: a row and a byte offset on a scalar boundary within it.
public struct TextPosition: Hashable, Comparable, Sendable {
    public var row: RowIndex
    public var offset: ByteOffset
}
public struct TextRange: Hashable, Sendable { public var lowerBound, upperBound: TextPosition }

/// An immutable snapshot: UTF-8 bytes, row starts, and one ASCII bit per row for the identity fast path.
public struct StyledText: Sendable {
    public init(utf8: [UInt8], rowStarts: [UInt32], runs: LineRuns, styles: StyleSheet)
    public var rowCount: Int { get }
    public func bytes(ofRow row: RowIndex) -> Span<UInt8>          // macOS 26
    public func isASCII(row: RowIndex) -> Bool
}

/// Style runs per row, in one flat buffer: `runs[offsets[row] ..< offsets[row + 1]]`.
public struct LineRuns: Sendable {
    public struct Run: Hashable, Sendable {                        // 8 bytes
        public var start: UInt32          // byte offset within the row
        public var length: UInt16
        public var style: StyleID
    }
    public subscript(row: RowIndex) -> ArraySlice<Run> { get }
}

public struct StyleID: Hashable, Sendable { public var rawValue: UInt16 }

/// Everything a run can change. Font-affecting fields force re-typesetting; colour does not.
public struct TextStyle: Hashable, Sendable {
    public var foreground: ColorRef
    public var weight: FontWeight?                 // nil: the base font's
    public var isItalic: Bool
    public var features: [FontFeature]             // per-run OpenType overrides
}

/// A colour resolved per appearance at render time; no NSColor in the model.
public enum ColorRef: Hashable, Sendable {
    case fixed(RGBA)                               // AtelierTheme's sRGB value
    case adaptive(light: RGBA, dark: RGBA, highContrast: RGBA?)
}

public struct StyleSheet: Sendable {
    public var font: FontSpec
    public var styles: [TextStyle]                 // indexed by StyleID
}

/// Row-level and range-level paint, layered above the text model. A layer can change without touching text.
public struct DecorationLayer: Sendable, Identifiable {
    public enum Paint: Hashable, Sendable {
        case rowFill(ColorRef)                                   // diff row backgrounds
        case rangeFill(Range<ByteOffset>, ColorRef)              // intraline emphasis
        case underline(Range<ByteOffset>?, UnderlineShape, ColorRef)   // squiggles; nil range = whole row
    }
    public let id: LayerID
    public var zIndex: Int
    public var paints: [RowIndex: [Paint]]         // sparse: changed rows only
}
```

GitDiffViewer's mapping:
- **Text:** the rows `DiffRenderer` already assembles, kept as UTF-8. The lexer's UTF-8 scanner then applies directly. The core review measures 157 ms and 2.16 M allocations per 50k-line pair on today's UTF-16 path, against 7.0 ms and 2 allocations on UTF-8 (perf-core.md, L1).
- **Runs:** the per-line tokens from the flat buffer, mapped role → `StyleID` once per theme.
- **Decorations:** row backgrounds, emphasis and squiggles as three layers. They land progressively, the order the GUI review proposes (text first, then colour, emphasis, diagnostics), and each costs a redraw of affected tiles only. TextKit reaches the same with rendering attributes (perf-gui.md §2, item 5); storage edits there cost 743 ms for L.
- **Text never waits for a layer.** Tiles draw the text with whatever layers have landed; a layer that is late, cancelled or failed leaves the text as it is. This is the order asked for earlier today: text first, with highlighting and diff decoration computed in parallel, without blocking, and without failing the text.

### 3.3 Line-based incremental layout

The unit of layout is a row. A row becomes one or more visual lines when it wraps.

- **Height index.** A Fenwick tree over row heights gives y-of-row and row-at-y in O(log rows), and updates one height in O(log rows). Each row carries a flag: exact or estimated. 50,000 `Float` heights take 200 KB; the lab measured 208 KB for the index (`ct-memory`).
- **Initial heights.** Without wrapping, every row is one line, so every height is exact: row count × line height. With wrapping, a row's height is estimated from its display width in cells, the column count and the two-cell continuation indent. The estimate needs no typesetting. On the real code it matched the typeset line count on 4,998 of 5,000 rows and on 49,909 of 50,000 rows: 0.17 % of the document height. It costs 0.23 ms for 5,000 rows and 2.1 ms for 50,000 (`ct-height-estimate`, §2.5).
- **Corrections.** Typesetting a row replaces its estimate. A background pass converts the rest outward from the viewport: 50,000 wrapped rows typeset in 218-336 ms off the main actor across 8 child tasks (`ct-whole-parallel`, §2.5).
- **Scroll anchoring.** The view remembers the first visible row and the offset into it. When a correction changes a row above the anchor by Δ, the clip view's origin moves by Δ in the same transaction, so the text on screen does not move. Corrections below the anchor change only the document height. The scroller can move by at most the correction; TextKit's `NSTextView` today grows its estimated document height from 72,093 pt to 91,198 pt while scrolling a 75,008 pt document (§2.5).
- **Split alignment.** The two panes of a split share an alignment table: a paired row's height is the maximum of both sides. Updating a row updates both indexes in O(log rows). No text is mutated; compare finding 2 in §1.3.

### 3.4 Background typesetting

Typesetting and rasterization run off the main actor in child tasks the caller owns. CoreText objects never cross an isolation boundary.

- **Thread safety, verified.** Every CoreText header states "All functions in this header are thread safe unless otherwise specified", CTTypesetter.h included (SDK 26.5). The Swift overlay does not mark `CTFont`, `CTLine`, `CTRun`, `CTTypesetter`, `CTParagraphStyle` or `CFAttributedString` `Sendable` (type-checked under Swift 6.4); only `CTGlyphInfo` carries `CT_SWIFT_SENDABLE`. The indexed Apple documentation has no archived Core Text guide to cite on sharing layout objects, so the design does not share them: each task creates its typesetter, its lines and its bitmap, uses them, and lets them go. A stress probe typeset 32,000 lines on 64 tasks sharing one `CTFont` with zero width mismatches; that is a smoke test, not a proof, and the design does not depend on it.
- **What crosses.** `CGImage`, `CGColor` and `CGColorSpace` are `Sendable` in SDK 26.5 (type-checked; `CGFont` is not), as are plain arrays. A task returns a `RenderedTile` (an image plus the rows' geometry) and nothing else.
- **Fonts per task.** A task builds its `CTFont` from a `Sendable` `FontSpec`. Creating one, feature descriptor included, costs 15.5 µs for MapleMono NF CN and 17.8 µs for the system monospaced font (median of 200), under 1 % of a 1.9 ms tile. The lab prototype shares one font through an `@unchecked Sendable` wrapper (`TypesetStyle`); the design does not need one.
- **Scheduling.** The host's `run()` consumes an `AsyncStream` of viewport requests with `.bufferingNewest(1)`, so only the latest viewport waits. It keeps at most four tile jobs in flight in one task group, visible tiles first, then one screen of prefetch in the scroll direction. A generation counter (`Atomic<UInt64>`, Synchronization) lets a job see it was superseded and return early; results for a stale generation are dropped on arrival.
- **First paint never waits.** If a visible tile is missing when the view draws, the host typesets and draws those rows synchronously on the main actor. The lab measures that at 1.6-1.9 ms for a full 54-row viewport with the system font and 2.4 ms with MapleMono (`ct-first-frame`, §2.3, §2.8), so text is never blank.

### 3.5 Rendering

- **Tiles.** Rows are grouped in tiles of 32 (480 pt at the default line height). Each tile is one `CALayer` in a flipped document view inside the pane's `NSScrollView`. Only tiles within one screen of the viewport exist.
- **Colour space.** Tiles are rasterized in the window's colour space. The lab measured a new document at 20.4 ms with sRGB tile images against 3.8 ms with tiles in the window's colour space (a Dell P2418D profile): Core Animation converts every sRGB tile on commit (§2.2). The host re-renders on `NSWindow.didChangeScreenNotification` and on `viewDidChangeBackingProperties`.
- **Colour at draw time.** Lines are typeset with font-affecting attributes only. Colour comes from the style runs when glyphs are drawn: the glyph runs are drawn with `CTFontDrawGlyphs`, segment by segment. Drawing a viewport that way took 0.54-0.67 ms against 1.17-1.35 ms with `CTLineDraw` (§2.3), and a recolour never re-typesets. The probe confirms `CTFontDrawGlyphs` draws colour emoji from the fallback font (586 coloured pixels either way).
- **Glyph and selection layers.** Row fills, emphasis and selection sit in a background layer under the text tiles, so selecting or hovering never re-rasterizes text. Whether text on a transparent tile renders identically to text on an opaque one is a golden-image question for M1 (§4.4); the fallback is opaque tiles re-rendered on selection change (1.86 ms per tile, §2.3).
- **A Metal glyph atlas, later.** M3 replaces tiles with a glyph atlas (A8 pages for outlines, BGRA pages for colour glyphs) and instanced quads in a `CAMetalLayer`. It is justified only if, on the M1 benchmarks, one of these holds:
  1. p95 main-thread time per frame exceeds 4 ms while scrolling at 120 Hz with prefetch on (the lab's tiled host measured 0.07 ms median and 0.13 ms p90 with no prefetch at all, §2.2);
  2. tile memory exceeds 64 MB per window at the largest supported window on a 5K display;
  3. a feature needs per-frame re-layout that tiles cannot cache (smooth zoom, animated folding);
  4. continuous scrolling uses more than half of one performance core.

### 3.6 Caches and memory bounds

| Cache | Key | Bound | Eviction |
|---|---|---|---|
| Tiles | rows, width, scale, colour space, appearance, decoration generation | 48 MB per window (about six 1000 × 480 pt tiles at 2×) | LRU, and anything two tiles beyond the viewport |
| Row geometry | row, width, font generation | 3 viewports (about 160 rows, 0.5 MB measured for typeset lines) | LRU |
| Height index | document | 4 bytes per row | with the document |
| Fonts | `FontSpec` | per task | with the task |
| Glyph atlas (M3 only) | font, glyph, subpixel phase | 4 pages of 2048² | LRU per page |

Memory is predictable from the input: 4 bytes per row for heights, plus bounded caches. TextKit keeps 24.8 MB for a 5,000-line document and 237.8 MB for 50,000 lines once they are fully laid out (§2.6).

### 3.7 Full font support

- **Fallback cascade.** CoreText falls back inside `CTTypesetter` using the font's cascade list. `FontSpec.fallback` prepends user choices (a CJK face, a symbols font) to `CTFontCopyDefaultCascadeListForLanguages(font, preferredLanguages)`, applied through `kCTFontCascadeListAttribute`. For the system monospaced font and [en, ja, ar] the default list has 41 entries (probe).
- **OpenType features.** `FontSpec.features` and `TextStyle.features` hold tag/value pairs (`liga`, `calt`, `ss01`, `zero`, `cv01` …) applied through `kCTFontFeatureSettingsAttribute` with `kCTFontOpenTypeFeatureTag` and `kCTFontOpenTypeFeatureValue`. The user's MapleMono NF CN has ligatures and contextual alternates; their cost is in §2.8.
- **Variable axes.** `FontSpec.variations` maps four-character axis tags to values through `kCTFontVariationAttribute`; `CTFontCopyVariationAxes` lists what a font offers (the system monospaced font: `YAXS`, `Weight`).
- **Colour glyphs and emoji.** Apple Color Emoji arrives through fallback. A ZWJ family sequence shapes to one glyph, and both drawing paths render it in colour (probe).
- **Grapheme-accurate hit-testing.** `CTLineGetStringIndexForPosition` gives a UTF-16 index. It is snapped to the nearest grapheme cluster boundary of the row (Swift `Character` boundaries), then mapped to a `ByteOffset`. Caret positions come from `CTLineEnumerateCaretOffsets`, which splits ligatures into per-character carets.
- **Bidi: needed, in two ways.**
  1. Right-to-left text appears in string literals and comments, and CoreText lays it out with the Unicode Bidirectional Algorithm; hit-testing and selection use caret offsets in visual order, so a mixed-direction range can yield several rectangles.
  2. Explicit direction controls must not reorder code. The typesetter runs with `kCTTypesetterOptionForcedEmbeddingLevel = 0`, which per the documentation makes CoreText ignore directional control characters while still ordering strong right-to-left letters. The probe confirms it: `abc⟨RLO⟩def⟨PDF⟩ghi` shows as `abcfedghi` by default and `abcdefghi` with the option. The controls themselves are drawn as visible placeholders, so a reviewer sees them.

### 3.8 Dynamic Type on macOS

What exists, checked in the docs and by the probe:
- The HIG says "macOS doesn't support Dynamic Type".
- `EnvironmentValues.dynamicTypeSize` exists on macOS 12+, but the docs say "On macOS, this value cannot be changed by users and does not affect the text size."
- `@ScaledMetric` (macOS 11+) does not scale on macOS 26.7 even when the app sets the environment: `@ScaledMetric(relativeTo: .body) var x = 12` read 12.00 under `.xSmall`, `.large`, `.xxxLarge` and `.accessibility3`, while each view saw its own `dynamicTypeSize` (probe).
- `NSFont.preferredFont(forTextStyle:options:)` (macOS 11+) returns the fixed macOS text-style sizes.

How the renderer honours text size:
- `StyleSheet.font.pointSize` is the one source of the size. The app drives it from its own zoom commands (Bigger, Smaller and Actual Size on ⌘+, ⌘− and ⌘0, as Terminal does), and persists it with the other font settings.
- The SwiftUI wrapper reads `\.dynamicTypeSize` and maps it through the iOS body-size ratios only where the platform scales text (`#if !os(macOS)`), so the engine is ready for iPadOS or visionOS without a behaviour change on the Mac.
- A size change re-typesets visible rows and rescales every estimated height in O(rows) without typesetting; unwrapped heights stay exact.

### 3.9 Hit-testing, selection, copy, find and accessibility

- **Hit-testing.** y → row through the height index, row → visual line, x → caret through the row's cached caret offsets, snapped to a grapheme boundary, returned as a `TextPosition`. `HoverHit` keeps its public fields; its UTF-16 column is computed at the boundary.
- **Selection.** `TextSelection { anchor, head, granularity }` with character, word and row granularity. Word boundaries come from the same identifier rules `HoverHitTester` uses today (HoverHitTester.swift:143-166), extended to grapheme clusters. Dragging autoscrolls through the clip view. Selection paints in the background layer.
- **Copy.** The selected byte ranges, joined with "\n", written as a plain string. The TextKit backend copies header titles because they are text in its storage (at `c375952` it also copied gap labels, which the bands of DIFF-02 have since removed); the CoreText backend copies the same rows, so users see no change.
- **Find.** The host is an `NSTextFinderClient`, and the pane's `NSScrollView` is the find bar container.
  - `string(at:effectiveRange:endsWithSearchBoundary:)` and `stringLength()` serve one row at a time as a UTF-16 `NSString`, with a search boundary at each row end, so no match spans rows and no whole-document string is built.
  - A UTF-16 row-start table (built once per document, identity on ASCII rows) converts finder offsets to `TextPosition`s.
  - `rects(forCharacterRange:)`, `visibleCharacterRanges`, `scrollRangeToVisible(_:)`, `contentView(at:effectiveCharacterRange:)` and `drawCharacters(in:forContentView:)` come from the height index and the tiles.
  - `performTextFinderAction(_:)` and `validateUserInterfaceItem(_:)` route the Edit ▸ Find menu, as the `NSTextFinder` docs require.
- **Accessibility.** This is the real cost of leaving `NSTextView`, which gives an `AXTextArea` with all of this for free. The host implements `NSAccessibilityNavigableStaticText` (which includes `NSAccessibilityStaticText`) and the text attributes of `NSAccessibilityProtocol`:
  - role `.textArea`, `accessibilityValue()` (the document, built lazily and cached per document), `accessibilityNumberOfCharacters()`;
  - `accessibilitySelectedText()`, `accessibilitySelectedTextRange()`, `accessibilitySelectedTextRanges()` and their setters, so VoiceOver can move the selection;
  - `accessibilityVisibleCharacterRange()`, `accessibilityInsertionPointLineNumber()`;
  - `accessibilityLine(for:)`, `accessibilityRange(forLine:)`, `accessibilityString(for:)`, `accessibilityAttributedString(for:)`, `accessibilityFrame(for:)` (screen coordinates; off-screen rows from the height index), `accessibilityRange(for:)` for a point and for an index (composed character range), `accessibilityStyleRange(for:)`;
  - notifications through `NSAccessibility.post(element:notification:)`: `.selectedTextChanged` on selection, `.valueChanged` on a new document;
  - `NSAccessibilityCustomRotor`s for changes and diagnostics, and the change kind in the attributed string of each line, which VoiceOver does not get today (§1.3, item 5).
  Every accessibility offset is UTF-16, through the same row-start table as find.

### 3.10 Swift 6.4 strict concurrency and Sendable boundaries

- Every model type in §3.2 is a struct or enum of `Sendable` members and conforms implicitly.
- CoreText and CoreGraphics objects that are not `Sendable` (above) live inside one child task and never escape it. No `@unchecked Sendable` is needed for them.
- The host view, its layers, its caches and its accessibility state are `@MainActor`. Tiles arrive through the task group the main-actor `run()` owns.
- No `@unchecked Sendable` is planned. Fonts are rebuilt per task for 15.5-17.8 µs each (§3.4). If a profile ever shows otherwise, the one permitted exception is a `FontStack` holding `CTFont`s created once and never mutated, with that invariant and CTFont.h's thread-safety statement written at its declaration.
- No `DispatchQueue`, no locks beyond the generation `Atomic`. Heavy functions are `@concurrent`, as the app already does for diagnostics (DiagnosticOverlay.swift:70-76).
- Every target compiles in Swift 6 mode with warnings as errors and the four upcoming features AGENTS.md lists; the lab package builds under those settings.

### 3.11 Public API sketch

```swift
// AtelierTextRendering (core, no AppKit)

public struct FontSpec: Hashable, Sendable {
    public var postScriptName: String?             // nil: the system monospaced face
    public var pointSize: Double
    public var features: [FontFeature]
    public var variations: [FontVariation]
    public var fallback: [String]                  // prepended to the default cascade list
}
public struct FontFeature: Hashable, Sendable { public var tag: String; public var value: Int }
public struct FontVariation: Hashable, Sendable { public var axis: String; public var value: Double }

public struct LayoutConfiguration: Hashable, Sendable {
    public enum Wrap: Hashable, Sendable { case none, width(Double), columns(Int) }
    public var wrap: Wrap
    /// Given, never derived: the one value both backends share (§1.3, finding 7).
    public var lineHeight: Double
    public var lineHeightMultiple: Double
    public var tabWidth: Int                       // in cells
    public var continuationIndent: Int             // in cells
    public var padding: Double
    public var bidi: BidiPolicy                    // .forceLeftToRight for code; reveals controls
}

/// Row heights with O(log rows) prefix queries; estimated until typeset.
public struct HeightIndex: Sendable {
    public init(text: StyledText, configuration: LayoutConfiguration, cellAdvance: Double)
    public var documentHeight: Double { get }
    public func y(of row: RowIndex) -> Double                   // O(log rows)
    public func row(atY y: Double) -> RowIndex                  // O(log rows)
    public func isExact(_ row: RowIndex) -> Bool
    /// - Returns: the height change, for scroll anchoring.
    public mutating func setHeight(_ height: Float, of row: RowIndex) -> Double
}

public struct RowGeometry: Sendable {
    public var height: Float
    public var lines: [VisualLine]
}
public struct VisualLine: Sendable {
    public var bytes: Range<ByteOffset>
    public var carets: [Float]                     // x of every UTF-16 boundary, visual order resolved
}
public struct RenderedTile: Sendable {
    public var rows: Range<RowIndex>
    public var image: CGImage
    public var geometry: [RowGeometry]
}

public enum TextTypesetter {
    /// Geometry of `rows`. - Complexity: O(bytes in rows). Throws only on cancellation.
    @concurrent public static func layout(
        _ rows: Range<RowIndex>, of text: StyledText, configuration: LayoutConfiguration
    ) async throws(CancellationError) -> [RowGeometry]
    /// Typesets and draws `rows` into one image in `colorSpace`.
    @concurrent public static func render(
        _ rows: Range<RowIndex>, of text: StyledText, decorations: [DecorationLayer],
        configuration: LayoutConfiguration, appearance: Appearance, colorSpace: CGColorSpace, scale: Double
    ) async throws(CancellationError) -> RenderedTile
}

// AtelierTextView (core, @MainActor)

@MainActor
public final class TextCanvasView: NSView {
    public init(configuration: LayoutConfiguration)
    public private(set) var text: StyledText
    /// Shows a new document; with `keepingAnchor`, the first visible row stays where it is.
    public func show(_ text: StyledText, keepingAnchor: Bool)
    public func setDecorations(_ layer: DecorationLayer)          // redraws affected tiles only
    public var selection: TextSelection? { get set }
    public var visibleRows: Range<RowIndex> { get }
    public func frame(ofRow row: RowIndex) -> CGRect              // O(log rows)
    public func position(at point: CGPoint) -> TextPosition?      // grapheme-snapped
    public func rects(for range: TextRange) -> [CGRect]
    public func scroll(to row: RowIndex, anchor: ScrollAnchor)
    public var rowSpacing: RowSpacingSource?                      // the split alignment table
    public var events: AsyncStream<TextCanvasEvent> { get }       // visible rows, selection, height changes
    /// Drives typesetting and tile rendering until cancelled; call it once per view.
    public func run() async
}

public struct TextCanvas: NSViewRepresentable { /* .task { await view.run() } */ }
```

`Appearance`, `BidiPolicy`, `ScrollAnchor`, `TextSelection`, `RowSpacingSource`, `TextCanvasEvent`, `LayerID`, `UnderlineShape`, `RGBA` and `FontWeight` are small value types or enums, left out for length. `TextTypesetter` uses typed throws, so a caller knows cancellation is the only failure.

## 4. The pluggable seam

The seam lets a window choose TextKit 2 or the CoreText renderer while the second one is being built. It sits at the `DiffTextKit` boundary and covers exactly the rows §1.2 marks as needed.

### 4.1 Protocols

```swift
// DiffTextKit/Seam/TextBackendKind.swift
/// The text engine a window's panes use.
package enum TextBackendKind: String, CaseIterable, Identifiable, Sendable {
    case textKit2
    case coreText
    package var id: String { rawValue }
}

// DiffTextKit/Seam/DiffTextPane.swift
/// One pane's text, whichever engine draws it. The comments name the §1.2 rows each member serves.
@MainActor
package protocol DiffTextPane: AnyObject {
    /// The view the pane embeds: a scroll view for a scrolling pane, the text view itself for a card.
    var view: NSView { get }
    var clipView: NSClipView? { get }

    func show(_ rendered: RenderedText, keepingScroll: Bool)          // 1-3, 15, 16, 21, 29
    func setDecorations(_ decorations: DiffDecorations)               // 11-13, progressive layers
    func setWrapping(_ mode: WrapMode)                                // 5-7

    var geometry: any DiffRowGeometry { get }                         // 4, 8, 10, 17, 18
    func scroll(toRow row: Int, centered: Bool)                       // 20

    /// Heights for split alignment; `isExact` is false while a CoreText pane still estimates wrapped rows.
    func rowHeights() -> (heights: [Double], isExact: Bool)           // 9
    func setRowSpacing(_ spacing: [Double])                           // 9

    func hoverHit(at point: NSPoint) -> HoverHit?                     // 19
    func anchorRect(for hit: HoverHit) -> NSRect?                     // 19
    // Selection, copy, find and accessibility (23-26) live inside `view`; the seam does not expose them.
}

// DiffTextKit/Seam/DiffRowGeometry.swift
/// Row positions in the pane's document coordinates, for the gutter, the minimap and the overscroll.
@MainActor
package protocol DiffRowGeometry {
    var documentHeight: CGFloat { get }
    /// Rows intersecting `rect`, top to bottom, with each row's frame and its first line's baseline.
    /// - Complexity: O(log rows + rows in rect); never lays out rows outside `rect`.
    func forEachRow(in rect: CGRect, _ body: (_ row: Int, _ frame: CGRect, _ firstBaseline: CGFloat) -> Void)
    func visibleRows() -> Range<Int>
}

// DiffTextKit/Seam/DiffCardText.swift
/// A card's text: sized for SwiftUI first, shown afterwards without measuring again.
@MainActor
package protocol DiffCardText: AnyObject {
    /// - Complexity: O(1) without wrapping; with wrapping, O(rows) for TextKit and O(rows) without typesetting for
    ///   CoreText (an estimate, corrected as rows are typeset).
    func size(forWidth width: CGFloat, mode: WrapMode) -> CGSize
    func makePane(gutter: GutterStyle) -> any DiffTextPane
}

// DiffTextKit/Seam/DiffTextBackend.swift
@MainActor
package protocol DiffTextBackend {
    var kind: TextBackendKind { get }
    func makePane(gutter: GutterStyle) -> any DiffTextPane
    func makeCardText(for rendered: RenderedText) -> any DiffCardText
}
```

`DiffDecorations` is the backend-neutral form of what `DiffLayoutFragment` draws today: row kinds, emphasis ranges and diagnostics, keyed by row. The TextKit adapter turns it into rendering attributes and the fragment's side table (the GUI review's stage 1-3 design); the CoreText adapter turns it into `DecorationLayer`s.

The existential `any DiffTextPane` costs one indirect call per pane operation, never per row.

### 4.2 Adapters

- **`TextKit2Backend`** holds today's code behind the protocols: the coordinator logic of `DiffTextView`, `StaticTextLayout` and `CardLayouts`, `DiffFragmentProvider`, `DiffLayoutFragment`, `HoverHitTester` and `RowSpacing`. Its `geometry` enumerates fragments from the one at `rect.minY` and stops past `rect.maxY`, as the gutter has done since `840d4e1` (DiffGutterView.swift:231-254). It carries the M0 fixes.
- **`CoreTextBackend`** wraps `TextCanvasView`. It maps `RenderedText` to `StyledText` and `DecorationLayer`s, answers `geometry` from the height index, `hoverHit` from `position(at:)`, and split alignment from a table shared by the pair.
- **Backend-neutral code** switches to the protocols:
  - `DiffGutterView.source` becomes `any DiffRowGeometry` instead of `GutterTextSource` (DiffGutterView.swift:14-29, :231-254);
  - `MinimapView` keeps its closures; they call `geometry.visibleRows()` and `pane.scroll(toRow:centered:)`;
  - `DocHoverController.attach(to:)` takes a pane instead of an `NSTextView` (DocHoverController.swift:55-71);
  - `SplitPaneController.register` takes panes and aligns through `rowHeights()` and `setRowSpacing(_:)` (SplitPaneController.swift:40-122);
  - `DiffTextView` and `EmbeddedDiffTextView` ask the backend for panes and keep their SwiftUI surface, so `DiagnosticDiffTextView`, `DiffDetailView` and `CombinedDiffView` do not change.

### 4.3 Runtime switch, per window

- `ComparisonWindow` owns `@State private var textBackend: TextBackendKind`, next to its own `settings` and `model` (ComparisonWindow.swift:19-24). It starts from a developer default: the `GDV_TEXT_BACKEND` environment variable, else the hidden defaults key `developer.textBackend`, else `.textKit2`.
- The window passes it down with `.environment(\.diffTextBackend, textBackend)` (an `@Entry` on `EnvironmentValues`) and publishes a binding with `.focusedSceneValue(\.textBackend, $textBackend)`.
- A **Develop** menu in App.swift's `.commands` (App.swift:44-50) shows a picker bound through `@FocusedBinding(\.textBackend)`. It appears in debug builds, or when the defaults key `developer.showsDevelopMenu` is set.
- Panes carry `.id(textBackend)`, so a switch rebuilds that window's panes only. Other windows keep their backend.
- Comparison windows are not restored (App.swift:63), so the choice lives as long as its window, and the defaults key sets the next window's start.

### 4.4 Parity harness

Three suites, all fed the same `RenderedText` fixtures: ASCII code, tabs, long lines, CJK, emoji with ZWJ sequences, right-to-left strings, combining marks, bidi controls, gap, header and filler rows, and diagnostics.

1. **`TextBackendParityTests`** (Swift Testing, `GitDiffViewerTests`, parameterized over fixtures × widths {no wrap, 400 pt, 800 pt}):
   - row frames: y and height within 0.5 pt, document height within 1 pt, wrapped line count per row equal;
   - `hoverHit` on a 20 × 20 grid of points: same row and UTF-16 column;
   - `visibleRows()` after scrolling to 10 offsets: equal;
   - `scroll(toRow:)`: the row lands within 1 pt;
   - copy of 10 fixture selections: identical strings;
   - accessibility: `accessibilityRange(forLine:)` and `accessibilityString(for:)` equal on every line (M2).
2. **`TextBackendSnapshotTests`** (gated by `GDV_SNAPSHOTS=1`): each backend renders each fixture offscreen at 2×, light and dark. Images are compared backend against backend and against stored baselines per macOS build. The pixel threshold is calibrated in M1 against TextKit's own run-to-run difference, then fixed; a failure writes both images and a difference image.
3. **`TextBackendBenchmark`** (gated by `GDV_BENCH=1`, like `PipelineBenchmark`): the lab's cases ported for both backends (new text, page scroll, smooth-scroll frame, jump, 50k apply, memory), median and p10-p90 printed, thresholds per phase in §5.

### 4.5 Which files move where

AGENTS.md asks for one move per commit, every package green after each. Moves inside `DiffTextKit` touch no manifest; the rule still applies.

| Commit | Change | Kind |
|---|---|---|
| 1 | Add `Seam/TextBackendKind.swift`, `DiffTextPane.swift`, `DiffRowGeometry.swift`, `DiffCardText.swift`, `DiffTextBackend.swift` | new files |
| 2 | Split `HoverHit` and `HoverSide` out of `HoverHitTester.swift` into `Seam/HoverHit.swift` | edit |
| 3 | `git mv DiffTextKit/HoverHitTester.swift DiffTextKit/TextKit2/` | move |
| 4 | `git mv DiffTextKit/DiffLayoutFragment.swift DiffTextKit/TextKit2/` | move |
| 5 | `git mv DiffTextKit/DiffFragmentProvider.swift DiffTextKit/TextKit2/` | move |
| 6 | `git mv DiffTextKit/RowSpacing.swift DiffTextKit/TextKit2/` | move |
| 7 | `git mv DiffTextKit/StaticTextLayout.swift DiffTextKit/TextKit2/` | move |
| 8 | Add `TextKit2/TextKit2Backend.swift`; route `DiffTextView` and `EmbeddedDiffTextView` through it | edit |
| 9 | `DiffGutterView`, `DocHoverController`, `SplitPaneController` and the minimap wiring use the protocols | edit |
| 10 | The environment value, the per-window state and the Develop menu | edit |
| 11 | `AtelierCore`: add the `AtelierTextRendering` and `AtelierTextView` targets | new files, manifest |
| 12 | Add `CoreText/CoreTextBackend.swift` | new file |

- `DiffPaneView` stays in `DiffGutterView.swift`, and `MinimapView`, `MinimapGeometry`, `DiagnosticOverlay`, `DocHoverController` and `HoverDocPanel` stay where they are: they become backend-neutral.
- If a seam type ever moves into a shared package, its `package` declarations are promoted to `public` in a separate no-op commit first.
- The sticky card views landed in `840d4e1` (StickyCardView.swift; CombinedDiffView.swift:97-227). Commit 8 routes the `EmbeddedDiffTextView` they host through the backend like every other pane.

## 5. Phased plan with decision gates

Each phase ends with numbers, not with a feeling. The benchmarks named below are the lab cases ported into `TextBackendBenchmark` (§4.4), run in release on the same inputs, reporting median and p10-p90.

### M0. The seam, and TextKit 2 used correctly

TextKit stays the only backend users get. Everything here is worth doing even if M1 never starts, because TextKit remains the fallback during M1 and M2.

| # | Change | Where (at `c375952`) | Measured effect | Status |
|---|---|---|---|---|
| 1 | Empty the live storage before setting a new render, in the same transaction | DiffTextView.swift:233-235 | New document 69.3 → 12.7 ms (5k), 7,034 → 25.5 ms (50k) (§2.2) | open |
| 2 | No wrapping: width-tracking container, sizes without layout, attach after sizing, `layoutViewport()` only in a window (GUI review fix 1) | DiffTextView.swift:265-278, :369-380; EmbeddedDiffTextView.swift:105-152, :190; StaticTextLayout.swift:59-90 | In-app first text 616 → 78 ms (L), 1,253 → 70 ms (XL); card expand 2,346 → 40 ms (perf-gui.md) | landed in `840d4e1` |
| 3 | Gutter and cursor-rect walks bounded by the rect, metrics cached (B8, GUI fix 2) | DiffGutterView.swift:79-95, :161-168, :231-254 | 292 → 1.3-2.0 ms per gutter tile (L); 100 ms per card draw at 50k before (§2.5) | landed in `840d4e1` |
| 4 | Memoize the wrapped `height` (S7; the no-wrap half landed with fix 2, and S6 with the card hosts) | StaticTextLayout.swift:84-90 | 3.8-4.2 ms per call for L (perf-gui.md) | open |
| 5 | Re-render only the dragged card, off the main actor (B7) | RenderPipeline.swift:142-165 | 58-92 ms → one card per gap-drag step (perf-gui.md) | open |
| 6 | A diagnostics bump redraws; it does not invalidate the whole layout | DiffTextView.swift:170-183 | Removes one full layout per bump: 172-323 ms for L (perf-gui.md) | open |
| 7 | Split alignment without per-row live writes: spacing built into the attributed string, set into an emptied storage; alignment deferred to the end of a live resize | SplitPaneController.swift:92-122; RowSpacing.swift:25-50 | Row writes (515 ms at 50k) become one linear set (11.3 ms at 50k, §2.4); building the per-row paragraph styles is not measured. The whole-document layout of both panes (256 ms per pass at 5k) remains | open |
| 8 | Colour as rendering attributes, text first (GUI review stage 1) | DiffFragmentProvider.swift, DiffRenderer.swift | 0.84 ms per screen instead of 743 ms for L (perf-gui.md) | open |
| 9 | One line-height source for both backends, measured once per font with TextKit 2, replacing the TextKit 1 object | DiffPalette.swift:59 | Removes the last TextKit 1 use (§1.3, finding 7) | open |
| 10 | Minimap bars keyed by appearance and backing scale | MinimapView.swift:40-42, :90 | Correctness | open |
| 11 | Visible placeholders for bidi controls in rendered text | DiffRenderer.swift:166-235 | Correctness and safety, both backends | open |
| 12 | Find through the text view's own find bar (`usesFindBar = true`) | DiffTextView.swift:79-82, EmbeddedDiffTextView.swift:66-69 | New capability; M2 must match it | open |
| 13 | The seam: protocols, `TextKit2Backend`, the per-window switch with one choice | §4 | No behaviour change | open |

**Exit criteria.**
- New document at 5k rows ≤ 16 ms and at 50k rows ≤ 30 ms of main-thread text work (lab: 12.7 and 25.5 ms).
- Smooth-scroll frame p90 ≤ 4 ms (lab p90: 2.8-3.5 ms), page step ≤ 12 ms (lab: 9.6 ms).
- In-app publish → first text ≤ 100 ms for L and XL (GUI prototype: 78 and 70 ms), guarded by the instrumented `PipelineBenchmark`.
- Gutter tile ≤ 2 ms.
- No whole-document layout without wrapping. `NoWrapLayoutTests` (added in `840d4e1`) checks the heights; a new test counts fragments created per publish in a scrolling pane and fails above three times the visible rows.
- `TextBackendParityTests` green for `TextKit2Backend` against today's behaviour.

**Decision gate: start M1 if any of these holds after M0.**
1. The architectural wins are wanted for their own sake: UTF-8 end to end, typesetting off the main actor, one styled-run model with KittyCode, a renderer reusable outside this app. This is a product decision; no benchmark settles it.
2. Wrapping in a split stays above 100 ms per alignment pass for L files. The lab measures 256 ms for 5,000 rows, and M0 cannot remove the layout of both panes.
3. A 120 Hz budget (8.3 ms) is wanted for new documents, page steps and jumps; fixed TextKit measures 12.7, 9.6 and 12.6 ms at 5k (§2.2).
4. Jumps must land exactly, or the scroller must stop changing size while scrolling (§2.5).
5. A window keeps more than 100 MB of text layout in normal use.

On the lab's inputs, conditions 2 and 3 already hold, and condition 1 is the goal the request states. Once M0 has landed, the recommendation is to start M1, time-boxed to its exit criteria.

### M1. CoreText viewport renderer, read-only drawing

Scope: `AtelierTextRendering` and `AtelierTextView` (§3), `CoreTextBackend` (§4.2) with rows, decorations, gutter geometry, minimap, split alignment, card sizes and hover hit-testing. No selection yet: the Develop switch labels the backend "drawing only".

**Exit criteria**, both backends side by side in `TextBackendBenchmark` and the parity suites:
- Geometry: row frames within 0.5 pt of TextKit, equal wrapped line counts, the hover grid identical, on every fixture and width.
- Golden images within the threshold calibrated on TextKit's own run-to-run noise, light and dark.
- New document ≤ 5 ms at 50k rows (lab: 3.8 ms); page step ≤ 5 ms (lab: 3.4 ms); jump ≤ 5 ms and exact (lab: 3.8 ms).
- Smooth-scroll frame p95 ≤ 0.5 ms with prefetch (lab, no prefetch: 0.07 ms median, 0.13 ms p90).
- Split alignment with wrapping ≤ 5 ms of main-thread work (lab estimate: 0.23-2.1 ms), corrections off the main actor.
- Tile memory ≤ 48 MB per window; retained layout memory ≤ 2 MB at 50k rows (lab: 0.5 MB plus 208 KB).
- Strict concurrency, warnings as errors, no `@unchecked Sendable`.

### M2. Hit-testing, selection, copy, find, accessibility

Scope: grapheme-snapped hit-testing, selection by character, word and row with drag autoscroll, copy, `NSTextFinderClient` with the find bar, `NSAccessibilityNavigableStaticText` with the rotors, the context menu (Copy, Look Up), dictionary lookup.

**Exit criteria:**
- Copy and selection: identical strings to the TextKit backend on every fixture selection.
- Find: the same matches, in the same order, as the TextKit backend's find bar for 20 fixture queries, including ones that would cross rows.
- Accessibility: an XCUITest reads `AXValue`, `AXSelectedTextRange`, `AXNumberOfCharacters`, `AXLineForIndex`, `AXRangeForLine`, `AXStringForRange` and `AXBoundsForRange` on both backends and requires equal answers (bounds within 1 pt); the Accessibility Inspector audit reports no error; VoiceOver reads a changed line with its change kind.
- A selection-drag frame ≤ 4 ms of main-thread work.

Then the default flips to CoreText. The TextKit backend stays behind the Develop menu for one release, then goes, together with the files under `TextKit2/`.

### M3. Metal glyph atlas, only if needed

Taken only if the M1 or M2 benchmarks cross a criterion of §3.5. Exit criteria: p95 main-thread frame ≤ 4 ms while fast-scrolling at 120 Hz on the largest window, memory within the tile budget it replaces, golden images within threshold of the CoreText tiles.

## 6. Risks and effort

### 6.1 What TextKit gives for free that must be rebuilt

| Capability | NSTextView today | The CoreText backend | Phase |
|---|---|---|---|
| Layout, wrapping, tabs, hanging indent | built in | per-row typesetting | M1 |
| Viewport management and document height | built in, estimated | height index, exact or corrected | M1 |
| Drawing, including colour glyphs and fallback | built in | tiles, `CTFontDrawGlyphs` | M1 |
| Appearance and backing-scale changes | automatic | re-resolve colours, re-render tiles | M1 |
| Mouse selection, word and paragraph granularity, autoscroll | built in | selection model and drag loop | M2 |
| Copy (plain text) | built in | pasteboard write | M2 |
| Find panel or bar, incremental search | built in, off today | `NSTextFinderClient` | M2 |
| `AXTextArea`: value, selection, lines, ranges, bounds, notifications | built in | `NSAccessibilityNavigableStaticText` and the text attributes | M2 |
| Context menu, Look Up, Translate, Services, Share | built in | Copy and Look Up first; Services later | M2 |
| Text drag source | built in | not planned | – |
| Writing Tools, spelling, input methods, undo | built in, unused | not needed: read-only | – |

### 6.2 Risks

1. **Accessibility.** The largest risk: `NSTextView`'s text area is mature, and a custom one can fail VoiceOver in ways tests miss. Mitigation: M2's attribute-by-attribute comparison against the TextKit backend on the same fixtures, and the TextKit backend kept per window until it passes.
2. **Rendering fidelity.** Anti-aliasing, baselines and line heights can differ from `NSTextView`. The lab found one already: no single CoreText formula reproduces TextKit's line height (16 pt for MapleMono against 17 from ceil(ascent) + ceil(descent); 14 pt for Menlo and SF Mono against 15). Mitigation: one line height passed to both backends (M0, item 9), golden images in M1.
3. **Colour management.** A tile in the wrong colour space costs five times more to commit (§2.2) and can shift colours. Mitigation: tiles in the window's colour space, re-rendered on screen changes.
4. **Memory on large windows.** A 32-row tile at 2× is 7.7 MB for a 1000 pt wide pane, and a pane twice as wide doubles it. Mitigation: the byte-bounded cache (§3.6), tiles as wide as their longest line.
5. **SwiftUI card sizes with wrapping.** Estimated heights that correct later make `LazyVStack` re-lay cards. Mitigation: exact heights without wrapping; with wrapping, typeset a card's rows off the main actor before first display (42 ms for 5,000 rows on one core) or keep the estimate and anchor.
6. **Complex scripts.** Fallback-heavy rows cost about 15 times more to typeset (§2.7-2.8), and mixed-direction selection is harder than left-to-right. The cost stays bounded by the viewport.
7. **Two backends at once.** Every fix during M1-M2 lands twice unless the seam stays narrow. Mitigation: the seam covers only §1.2's needed rows, and backend-neutral code (gutter, minimap, hover panel, diagnostics) stays shared.
8. **Scope creep.** Editing is out of scope. KittyCode shares the model, not the renderer.
9. **TextKit keeps improving.** The 2027 releases add hooks for line numbers in `NSTextView` (WWDC 2026 session 370); they need macOS 27, above today's 26.1 floor, and they do not change the layout costs measured here.

### 6.3 Effort estimates

Estimates, for one engineer who knows this code; not measurements.

| Phase | Work | Estimate |
|---|---|---|
| M0 | The open fixes 1 and 4-12 (several exist as measured patches in `/tmp/gdv-perf`) | 3-4 days |
| M0 | Seam, `TextKit2Backend`, per-window switch, parity harness skeleton | 4-6 days |
| M1 | Engine: model, height index, typesetting, tiles | 5-7 days |
| M1 | Host view: tiles, prefetch, anchoring, appearance and scale, SwiftUI wrapper | 5-7 days |
| M1 | `CoreTextBackend`: decorations, gutter, minimap, alignment, cards, hover | 4-6 days |
| M1 | Golden images, parity fixes | 3-5 days |
| M2 | Hit-testing, selection, copy, context menu, Look Up | 5-7 days |
| M2 | Find | 3-4 days |
| M2 | Accessibility, rotors, VoiceOver testing | 7-10 days |
| M3 | Metal atlas, if triggered | 15-20 days |

Total without M3: 39-56 working days, about 8-11 weeks, of which M0 is 1.5-2 weeks.

## Appendix: reproducing the measurements

Everything lives in `/tmp/text-renderer-lab`, outside the repository.

| Path | What it is |
|---|---|
| `Package.swift` | The lab package, with the repository's strict settings (Swift 6 mode, warnings as errors, the four upcoming features) |
| `Sources/AtelierSyntaxModel`, `Sources/AtelierLexers` | Verbatim copies of the core targets at 10ae905, for real token density |
| `Sources/MakeInputs` | Builds `inputs/swift-5k.swift`, `inputs/swift-50k.swift` and `inputs/unicode-5k.swift`; prints statistics only |
| `Sources/Probe` | API questions answered by observation: find defaults, TextKit 2 status, colour glyphs, bidi, fonts, `@ScaledMetric`, concurrent typesetting |
| `Sources/Bench` | The benchmark: `TextKitCases.swift`, `CoreTextPrototype.swift`, `CoreTextCases.swift`, `TileCases.swift`, `StorageCases.swift`, `UnicodeCases.swift`, `Harness.swift` |
| `Sources/MallocCounter` | Allocation events through libmalloc's `malloc_logger` hook |
| `run-round.sh`, `run-round2.sh`, `run-round3.sh`, `run-round4.sh` | The four rounds; each writes `results/round-N.txt` with the load average before every suite |
| `summarize.py` | Merges rounds into one line per case and input |
| `results/textview-apply.trace` | The Time Profiler trace that located the quadratic storage replace |
| `sendable-check/` | The type-check of `Sendable` conformances, the font-creation timing and the line-height table |

```sh
cd /tmp/text-renderer-lab
~/.swiftly/bin/swift build -c release --scratch-path .build3          # Swift 6.4.0 via .swift-version
./.build3/out/Products/Release/MakeInputs <swift-corpus-root> inputs
./.build3/out/Products/Release/Probe
./run-round3.sh 3                                                      # the end-to-end comparison, three repeats
LAB_FONT=MapleMono-NF-CN-Regular ./run-round3.sh maple                 # the same with the user's font
python3 summarize.py results/round-3.txt
```

`Bench <input> <suite> [case-prefix …]` runs one suite; suites are `textkit`, `textkit-wrap`, `textview`, `coretext`, `coretext-wrap`, `tiles`, `storage`, `unicode`, `model` and `info`. `LAB_FONT` sets the pane font by PostScript name, `LAB_FEATURES_OFF=1` turns off `liga` and `calt`, and `LAB_TILE_MODE` picks `imageSRGB`, `imageMatched` or `layerDraws` for the tile cases.
