# Xcode reference: gap handles, the fold ribbon and inline changes

Screenshots the user took on 09-23 from Xcode 26.6, of the throwaway project in
`~/Developer/experimental/010.xcode-diff-playground`. They are the visual reference for the roadmap's
"Diff interaction refinements" (DIFF-02 to DIFF-04). Images are in `assets/xcode-reference/`.

## Gap handles (DIFF-02)

![Handle between two runs](assets/xcode-reference/gap-handle-between-runs.png)
![Handle at the top](assets/xcode-reference/gap-handle-at-top.png)
![Handle above a change](assets/xcode-reference/gap-handle-above-change.png)

- **No row of its own:** the hidden run takes no line. A hairline across the gutter marks it, on the boundary
  between the two visible lines around it, and line numbers jump across it (18, then 237). The run leaves no other
  trace.
- **Shape:** one rounded rectangle, about 20 × 14 pt, centred on that hairline, which splits it into two halves.
  Each half carries one short grip line and is a handle of its own. The upper half is drawn over the bottom of the
  line above the hairline, and the lower half over the top of the line below it.
- **Which half does what:** the upper half extends the change above, and is dragged down. The lower half extends
  the change below, and is dragged up. Each half's rounded corners face the change it extends; its flat side lies
  on the hairline, facing the direction it is dragged.
- **One direction only:** where a run can grow from one side alone, only that half is drawn. At the top of the file
  (above line 12) the lower half hangs under the hairline, flat side up and rounded corners toward line 12; at the
  end of a file the upper half sits on top of it. Above a change with a run on each side (line 82), both halves
  show.

Our version: the user corrected the first build on 09-23 to exactly this geometry. Each half hovers and drags on its
own. A drag never discloses lines against its half's direction, and a half held at an edge keeps revealing at a
bounded rate. The count of hidden lines, which the removed row used to show, moves to the handle's tooltip.

## Inline change and intraline emphasis

![Inline change](assets/xcode-reference/inline-change-intraline.png)

- **Old line:** a light gray background, and no line number.
- **New line:** a light blue background, and its line number (416).
- **Changed tokens:** tan on the old line (`100`) and blue on the new line (`120`).
- **Change bar:** a solid blue bar at the gutter's leading edge spans the change, old and new lines together.

This is Xcode's modification look. It differs from our red and green palette, and could become an "Xcode" diff
palette to match the Xcode badge scheme (SET-07). That idea is not requested yet.

## Fold ribbon (DIFF-03)

![Ribbon depth](assets/xcode-reference/fold-ribbon-depth.png)
![Ribbon depth with a folded if](assets/xcode-reference/fold-ribbon-depth-and-folded-if.png)

- **Place:** a narrow strip between the line numbers and the text.
- **Depth:** each line's segment is shaded by nesting depth, and deeper scopes are darker grays. A hairline marks
  where a scope ends (line 66).
- **Wrapped lines:** a folded or wrapped line (60) keeps a single ribbon segment across its visual rows.

![Hovering a function](assets/xcode-reference/fold-hover-function-scope.png)
![Hovering an inner if](assets/xcode-reference/fold-hover-inner-if.png)

- **Hover:** outlines the scope under the pointer as a rounded capsule in the ribbon, with a `⌄` at its first line
  and a `⌃` at its last. The scope's opening and closing braces light up in blue in the text.
- **Hover precision:** it works at any depth. Hovering the inner `if` (lines 60 to 62) outlines only that block.

![Folded function](assets/xcode-reference/fold-folded-function.png)
![Folded type with changes](assets/xcode-reference/fold-folded-type-with-changes.png)

- **Folded scope:** shows a dark tab with `›` in the ribbon, and a gray `•••` capsule in the text between the
  braces. Line numbers jump (53, then 72).
- **Changes inside a fold:** a scope with changes inside it keeps a dotted blue change bar at the gutter's edge
  (`actor SyncEngine`, lines 12 to 495). A fold never hides that something changed.

Our version: the ribbon shares the gutter with line numbers, the change bar and diagnostics tints without widening
it much. That is why the gutter's spacing is to be reworked into layers with dedicated sides.

## Compact inline view (DIFF-04)

No Xcode screenshot covers it. It reuses the ribbon's visual language, meaning the markers, the tab and the capsule,
to flag where changes are in a view that shows only the new content. Clicking a marker discloses the change in
place.
