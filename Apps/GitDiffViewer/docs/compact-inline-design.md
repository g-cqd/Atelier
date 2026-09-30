# Compact inline view (DIFF-04)

The book's DIFF-04 and the roadmap's "Diff interaction refinements", item 4: an inline view that reads as the new file,
with a gutter marker at each place that changed. Clicking a marker discloses that change in place. No Xcode capture
covers it (`xcode-reference.md`), so it borrows the gutter's own language: the gap handles' thin outlines and their
hover, and the change bar Xcode draws right of the line numbers.

## The setting

- **Compact inline view**, off by default. It sits under the diff layout it belongs to: in Settings ▸ Appearance ▸
  Layout, below the layout picker, and in the toolbar's View options menu, below Isolate changes. It is app-wide and
  not overridable per project. It changes nothing unless the layout is Inline; the caption says so.
- It applies wherever the inline layout shows: the single-file view and the cards of the card list.
- Turning it on or off, like changing the layout, renders the diff again and folds back every revealed line and every
  disclosed change.

## What shows

Each change of the inline diff is a run of removed lines followed by the added lines that replace them. In the compact
view each change is **folded** or **disclosed**:

- **Folded**, the default: the removed lines are not shown. The added lines show as the file reads, with their new
  line numbers, in the plain text colour: no row tint and no intraline emphasis. A change that only removes lines
  takes no row at all. A file with no new lines, a deleted one, would then show nothing: its changes show disclosed.
- **Disclosed**: the change shows exactly as the inline view shows it, in place: the removed lines, tinted red, then
  the added lines they became, tinted green, with the intraline emphasis. The removed lines appear above the resulting
  lines, and the lines around the change do not move.

Only the inline side is compacted. The split and stacked layouts are unchanged.

## Markers

Every marker lies in the gutter's change layer, back on its leading edge (09-30, D43, reversing the trailing move of
09-30 earlier the same day): a little negative space, then the layer, then the numbers. The layer is 8 points wide, at
rest and under the pointer alike; only present while it has something to draw, the compact view's markers or, lacking
those, the Xcode change bar, which share it and never draw together (`scope-ribbon-design.md`). Off, the gutter
reclaims the layer's own width.

- **A change with added lines**: a bar 6 points wide at rest, centred in the layer, with round ends, running down the
  change's rows: the added rows while folded, the removed and the added rows while disclosed. It stops at the last
  row's own height, never across a gap's band.
  - Green for an addition, blue for a modification, which removes lines and adds others (Xcode's change bar).
  - **Folded**: a solid bar. The text itself looks unchanged, so the bar is what says something changed here.
  - **Disclosed**: the same bar hollow, a 1-point outline over a faint fill, since the rows it spans already carry the
    change's colours, and subtle separator lines cut through it in the gutter's own background: on its own outer top
    and bottom edges, and, with both removed and added rows, on the seam where the one gives way to the other, at the
    row height its removed lines take down from its top (book D43).
- **A change that only removes lines**, folded: a red wedge 5 points wide and 7 tall, pointing into the text, centred
  on the boundary between the two rows around the removal: Xcode's mark for deleted lines. At the top of a file it
  sits on the first row's top edge, at the end on the last row's bottom edge. Where a gap's band lies on that
  boundary, or a neighbouring change touches it with no row between, it keeps to the side away from that neighbour, so
  the two markers never overlap (book D43, R134): below the boundary if the neighbour is above, or if a gap's band
  is there, above it if the neighbour is below, and only otherwise centred, since a row of context then separates it
  from its neighbours either way. Disclosed, the removal takes rows and is marked like the others, with a hollow red
  bar and its own outer-edge separators.
- **Hover**: the marker under the pointer grows to fill the layer, 8 points, and draws at full strength, the pointer
  turns into a pointing hand, and the tooltip tells the change and what a click does: "Modified: 2 lines removed, 3
  added. Click to show the change (⌥⌘↩)" or "… Click to hide the change". Its outer-edge separators show while
  hovered too, disclosed or not.
- **Hit area**: the change layer across the marker's rows, or half a row either side of a wedge, its own rows looked
  up directly wherever they lie, not guessed from how close they are to the pointer (book D43, "hover hits the wrong
  row"; ``DiffGutterView/changeMarker(at:)``). The line numbers keep their own clicks, and a gap's band keeps its
  handles: a marker never lies in a band.

## Interaction with isolated changes and the gap handles

- The hunks are worked out on the compact rows: a folded change counts its added rows, and a folded removal counts as
  a point, its context lines around it. Every change keeps its context lines, and its marker.
- Disclosing a change only grows it in place: the unchanged rows around it, and so the gaps between hunks, stay as
  they were. The gaps keep their keys, the lines they hide, their revealed lines and their handles, which drag as
  before. The card list, which always isolates changes, behaves the same way.
- With no context lines, a folded removal would have no row by it: it keeps the row after it (or before it, at the
  end of the file), so its marker stays, and that one row folds into the gap once the removal is disclosed.
- The gutter draws the bands and handles first and the markers over the rows; the two never share a spot.

## Keyboard

- **⌥⌘↩ Show or Hide Change**: toggles the current change, the one ⌘⇧↓ and ⌘⇧↑ last moved to, or the first change
  when none is current. In the card list, where those keys move from card to card, it toggles every change of the
  current card together.
- **⌥⌘⇧↩ Show or Hide All Changes**: discloses every change shown when any is folded, and folds them all otherwise.
- ⌘⇧↓ and ⌘⇧↑ stop on every change, a folded removal included, and scroll to its first row, or to the row after a
  folded removal.

Both commands do nothing outside the compact view. The markers are not yet VoiceOver elements; that is a follow-up.

## State

- Disclosed changes are kept per window, per file and change, as revealed lines are. They survive a reload of the same
  file, matched by the change's position among the file's changes, and are dropped when another selection loads, when
  the layout or the compact setting changes, and when the file leaves the list.
- Disclosing or folding renders only the file it belongs to again, and keeps the scroll position, as a gap drag does.

## Not in this step

The Xcode diff palette (D18) and the scope ribbon (DIFF-03), whose capsule and tab the markers may later share, wait
for the Swift syntax facts of PERF-11.
