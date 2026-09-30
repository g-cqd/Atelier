# Gutter scope ribbon and the Xcode diff colours (DIFF-03, D18, D43)

The book's DIFF-03 asks for scope indicators and fold controls in the gutter without growing it much; the roadmap's
"Diff interaction refinements", item 3, asks for the gutter's spacing to be reworked into layers. D18 adds an "Xcode"
choice for the diff colours, off by default, built with it. D43 (09-30) restyles the change layer and the ribbon after
Xcode more closely still, reversing D42's move of the change layer to the trailing side. The reference is Xcode's fold
ribbon and its inline change, images 12 to 18 in `xcode-reference.md`, and the user's screenshot
`assets/xcode-reference/xcode-folding-ribbon-0930.png`.

## The gutter's layers

Every layer has a side of its own, so no two ever share a spot, but the gutter's width now follows what it has to
show (D43, replacing the earlier "one width whatever it shows" rule): a layer with nothing to draw takes no space.
From the leading edge:

| Place | Width | What lies there |
| --- | --- | --- |
| Leading air | 2 pt | Negative space before the change layer, so a marker is easy to click without hugging the gutter's own edge; absent when the change layer is. |
| Change layer | 8 pt | The compact inline view's markers (DIFF-04), or, with the Xcode colours, the change bar, never both, since the compact view's markers already say where the changes are. Present only while one of the two would draw something: a plain diff in the app's own colours, with the compact view off, has none, and the gutter is that much narrower. A marker is 6 pt wide at rest, growing to 8 pt, the whole layer, under the pointer, like Xcode's. |
| Gap to numbers | 2 pt | Air before the numbers; alone, without the change layer's own air, when it is absent. |
| Number columns | as now | The line numbers, over their diagnostics underlay (DIAG-03). |
| Gap to ribbon | 2 pt | Air after the numbers; present only while the ribbon shows. |
| Scope ribbon | 8 pt | Capsule segments, nested scopes shaded darker (below); present only while `showsScopeRibbon` is on. |
| Trailing air | 2 pt | To the gutter's trailing hairline. |
| Across the gutter | the band | A gap's band and its handles (DIFF-02) and a folded scope's band, over every layer, since no row lies there. |

A card list shares one width across every card through a `GutterWidthCoordinator` (D43, "one gutter width across the
card list"): each card's gutter registers the width its own numbers, markers and ribbon need, and reads back the
widest any card needs, so every card's trailing edge lines up; a card leaving drops its own width, which may narrow
the shared one back. Registering or updating a width that does not move the shared one calls no gutter back, so a
settled list, or a card that already matches, causes no storm of invalidation; a card's own wrapped text alone
re-measures, from the next width it reads.

Z order, bottom to top: the gutter's background, the code's own (D43, no longer a tinted one); the ribbon's capsules;
the diagnostics underlay; the line numbers; the change layer; the ribbon's hovered stroke and fold tabs; a band and
its handles.

## The ribbon

![Ribbon depth](assets/xcode-reference/fold-ribbon-depth.png)
![Hovering a function](assets/xcode-reference/fold-hover-function-scope.png)

- **At rest**: each scope draws as a capsule spanning its own rows, rounded ends, no stroke, shaded by how deeply it
  nests, the text colour at 5 % per level up to four levels: a scope inside another draws over it, darker, so the two
  read as nested pills, the outer one's rounded ends showing past the inner's, as the user's Xcode screenshot shows
  it. A row outside every scope has none.
- **Hovering a row** anywhere in the gutter or the text outlines its innermost scope: a rounded capsule stroke only,
  mostly white with enough of the text colour blended in to still show against a barely shaded gutter background,
  from the scope's first row to its last, with a `⌄` at the first and a `⌃` at the last, in the same stroke. The
  scope's own depth shading stays under the stroke, unlike a gap handle's outline, which used to erase it. The
  scope's braces light up in the text, in the accent colour, as rendering attributes, which lay nothing out again.
- **Hovering the capsule's ends** strengthens them, with a pointing hand and a tooltip: "Fold the function (⌥⌘←)".
- **Folded**: the scope's first row stays, its inner rows and its last row give way to a band one row tall, like a
  gap's, holding a gray `•••` capsule after the first row's text and the closing brace; the line numbers jump across
  it. The ribbon shows a dark tab with a `›` on the first row. If the folded rows hold a change, the band's change
  layer shows a dotted change bar (image 13): a fold never hides that something changed.
- **Clicking** the `⌄` or the `›` tab folds or unfolds; clicking a `•••` capsule unfolds.

### Hovering the right row

The ribbon's own row lookup (`rowIndex(at:)`, `scope(atRow:)`) is a direct TextKit fragment lookup for the one row
under the pointer, not a guess from a small window around some other row, so it was never the class of bug the change
markers had (below): it is not resized by a card's inset, a gap's band, or how tall the scope it finds turns out to
be.

## Folding, gaps and the compact view

- A fold is kept like a gap's revealed lines: per window, per file and scope (its first line on its side), carried
  through a reload of the same file, dropped with a new selection.
- The rows are worked out in this order: the compact view folds its changes (DIFF-04), isolated changes cut the file
  into hunks with their gaps (DIFF-02), and folded scopes then hide the rows they cover among what shows. A fold that
  spans a gap swallows it, and the gap's revealed lines come back as they were once the scope unfolds. A fold never
  changes a gap's key, since gaps are worked out before folds.
- Folding a scope that holds a change keeps the change counted and navigable: ⌘⇧↓ unfolds the scope it lands in.
- Split panes fold their two sides together, by the side whose ribbon was clicked, so rows stay paired.

## Where scopes come from, after first paint

- **Swift**: the braces of the one parse per side that PERF-11 step 3 keeps in the `SyntaxFactsStore`. `SyntaxFacts`
  gains `scopes`, each a brace pair's UTF-8 range and its kind (type, function, closure, control flow), gathered in the
  same tree walk as the declarations; no second parse.
- **Other languages**: the lexer's `punctuationBracket` tokens, braces matched in order, so braces in strings and
  comments never count.
- Scopes come with the refined colours: the refinement pass that follows first paint maps each side's scopes to line
  ranges, which the pane maps to its rows by their line numbers, and the gutter shades and outlines them from then on.
  Nothing waits for them.

## The Xcode diff colours (D18)

![Inline change](assets/xcode-reference/inline-change-intraline.png)

A **Diff colors** choice in Settings ▸ Appearance, beside the badge colours and independent of them: **Red and green**,
the default, or **Xcode**. Xcode's, from image 12, in light and dark alike through system colours:

| | Red and green | Xcode |
| --- | --- | --- |
| A removed line, and the old side of a modified one | red, 16 % | the text colour, 7 %: gray |
| An added line, and the new side of a modified one | green, 16 % | blue, 12 % |
| A changed token on the old side | red, 40 % | orange, 28 %: tan |
| A changed token on the new side | green, 40 % | blue, 30 % |
| The change bar | none | solid blue, in the gutter's change layer before the numbers (D43), down every changed row |
| The minimap of a split pane | green and red | blue and gray |

Moved lines keep their own blue in both. The compact inline view keeps its markers; its disclosed changes take the
colours chosen here.

## Keyboard

As Xcode's Editor ▸ Code Folding: **⌥⌘←** folds the innermost scope around the insertion point, **⌥⌘→** unfolds it,
**⌥⌘⇧←** folds every function and type body shown, and **⌥⌘⇧→** unfolds everything. The commands act on the pane
that has the focus, and do nothing where no scope is known yet.

## What each part touches, and in what order

1. **The Xcode diff colours**: `DiffPalette`, the settings, the gutter's change bar. Independent of the rest.
2. **Scope facts**: `SyntaxFacts` and `SwiftSyntaxFacts` in AtelierCore, and a bracket matcher for the lexer's tokens.
3. **The ribbon and its hover**: `RefinedSides` and the refinement pass in `RenderPipeline+Refinement` carry scopes to
   the panes; the gutter draws them, in `DiffGutterView` and new files; the braces' highlight is a rendering
   attribute in a new DiffTextKit file.
4. **Folding**: a fold is a row cut like a gap, in `DiffRenderer` and `RenderedDiff`, kept by `RenderPipeline`, and
   drawn as a band by `DiffLayoutFragment` and `DiffFragmentProvider`.

Parts 3 and 4 need the render pipeline, the renderer, the rendered text and the fragment files, which the text-first
pipeline (P2) is reworking, so they follow it; part 2 lands with part 3, which is the first to use it.
