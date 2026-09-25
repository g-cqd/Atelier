# Gutter scope ribbon and the Xcode diff colours (DIFF-03, D18)

The book's DIFF-03 asks for scope indicators and fold controls in the gutter without growing it much; the roadmap's
"Diff interaction refinements", item 3, asks for the gutter's spacing to be reworked into layers. D18 adds an "Xcode"
choice for the diff colours, off by default, built with it. The reference is Xcode's fold ribbon and its inline change,
images 12 to 18 in `xcode-reference.md`.

## The gutter's layers

The gutter keeps one width for a text whatever it shows, and every layer has a side of its own, so no two ever share a
spot. From the leading edge:

| Place | Width | What lies there |
| --- | --- | --- |
| Leading padding | 8 pt | The change layer: the compact inline view's markers (DIFF-04), or, with the Xcode colours, the change bar. Never both: the compact view's markers already say where the changes are. |
| Number columns | as now | The line numbers, over their diagnostics underlay (DIAG-03). |
| Trailing padding | 10 pt, 2 pt more than today's 8 | The scope ribbon, 5 pt wide, 1 pt from the gutter's trailing hairline, with 2 pt of air before the numbers. |
| Across the gutter | the band | A gap's band and its handles (DIFF-02) and a folded scope's band, over every layer, since no row lies there. |

The only growth is the ribbon's 2 points, the whole of criterion 3's "a few points". A text without scopes keeps them,
so the gutter never changes width when scopes land after first paint.

Z order, bottom to top: the gutter's background; the ribbon's depth shading; the diagnostics underlay; the line
numbers; the change layer; the ribbon's hover capsule and fold tabs; a band and its handles.

## The ribbon

![Ribbon depth](assets/xcode-reference/fold-ribbon-depth.png)
![Hovering a function](assets/xcode-reference/fold-hover-function-scope.png)

- **At rest**: each row's segment is shaded by how deeply it nests, the text colour at 5 % per level up to four
  levels, and a hairline marks the row where a scope ends. A wrapped row keeps one segment across its lines. A row
  outside every scope has none.
- **Hovering a row** anywhere in the gutter or the text outlines its innermost scope in the ribbon: a rounded
  capsule, 1 pt, at the outline strength a gap handle's half has under the pointer, from the scope's first row to its
  last, with a `⌄` at the first and a `⌃` at the last. The scope's braces light up in the text, in the accent
  colour, as rendering attributes, which lay nothing out again.
- **Hovering the capsule's ends** strengthens them, with a pointing hand and a tooltip: "Fold the function (⌥⌘←)".
- **Folded**: the scope's first row stays, its inner rows and its last row give way to a band one row tall, like a
  gap's, holding a gray `•••` capsule after the first row's text and the closing brace; the line numbers jump across
  it. The ribbon shows a dark tab with a `›` on the first row. If the folded rows hold a change, the band's leading
  padding shows a dotted change bar (image 13): a fold never hides that something changed.
- **Clicking** the `⌄` or the `›` tab folds or unfolds; clicking a `•••` capsule unfolds.

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
| The change bar | none | solid blue, 3 pt, in the gutter's leading padding, down every changed row |
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
