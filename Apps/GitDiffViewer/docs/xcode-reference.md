# Xcode reference: gap handles, the fold ribbon and inline changes

Screenshots the user took on 09-23 from Xcode 26.6, of the throwaway project in
`~/Developer/experimental/010.xcode-diff-playground`. They are the visual reference for the roadmap's
"Diff interaction refinements" (DIFF-02 to DIFF-04). Images are in `assets/xcode-reference/`.

## Gap handles (DIFF-02)

![Handle between two runs](assets/xcode-reference/gap-handle-between-runs.png)
![Handle at the top](assets/xcode-reference/gap-handle-at-top.png)
![Handle above a change](assets/xcode-reference/gap-handle-above-change.png)

- **Shape:** a small rounded rectangle, about 20 × 14 pt, drawn as a grabber with two horizontal lines. It sits
  centred on a hairline that crosses the gutter where lines are hidden.
- **Line numbers** resume after the jump (18, then 237). The hidden run leaves no other trace.
- **Position:** the handle marks the collapsed run's boundary. It sits above a change (above line 82, where the
  change bar starts) or at the top of the file (line 12).

Our version: the user asks for two handles when a run sits between two changes, one extending each neighbouring
change, each with its own hover state. It must never disclose lines on a drag against the reveal direction, and it
keeps revealing, at a bounded rate, while held at an edge.

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
