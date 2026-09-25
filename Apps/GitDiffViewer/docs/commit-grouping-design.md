# The flat file list grouped by commit: research and design (GIT-06)

Criterion 1 of GIT-06 (book, R120): settle the open questions before building. This note holds the options, a
measured spike, a UI sketch and a build plan. It adds no product code.

The request: "i'd like that we investigate ways to improve the one flat sidebar file list, by having a toggleable
setting to group through disclosable section diffed files by commit when the 2 compared repo states share the same
ancestry, it can only work in flat sidebar, for repos".

## Summary of decisions

| Question | Decision |
|---|---|
| A file changed by several commits | Listed under **each** commit that touched it |
| A file changed and changed back within the range | Not listed; its commit's section still shows, and says so when nothing is left in it |
| Merges | **First-parent** history: one section per mainline commit, a merge holding everything it brought in |
| Renames and copies | `-M` per commit, renames chained to the comparison's own row; the row keeps the new name (D14); copies read as added |
| Uncommitted changes | One **Uncommitted Changes** section first, when the right side is the working tree; staged or not shows on the badge (CARD-09) |
| Ancestry | Only **left is an ancestor of right** (`git merge-base --is-ancestor`); a diverged left offers "Compare from the merge base" instead |
| Section header | Subject and file count on the row; short id, author, date and full message in the tooltip; no line counts |
| Selecting a section or a file under it | Shows **that commit's own change**, first parent to commit; Uncommitted Changes shows `HEAD` against the working tree (D39, replacing D31's net diff) |
| Cap | **1,000** commits, loaded in pages of **200**, newest first; the rest in a trailing **Earlier Changes** section |
| Where it applies | The flat style in the merged sidebar ("One merged tree in a sidebar"), for two states of one repository |
| The setting | "Group changed files by commit", off by default, General ▸ File Explorers and the View options menu |

## What the app has today

- **The flat list.** `ExplorerTrees.build` (`DiffComparison/ExplorerTrees.swift`) arranges each tree by
  `FileTreeStyle`; `.flat` ("Flat list of paths") calls `PathNode.flatList(from:)` (`AtelierFileTree`), which sorts
  every file path with `localizedStandardCompare` into one level of rows. The trees are built off the main actor
  (`buildOffMain`, `@concurrent`) and replaced wholesale.
- **Placements.** `ExplorerPlacement`: `.top` (two explorers above the diff), `.sidebar` (two explorers stacked in the
  sidebar, one per side, each listing that side's own paths), `.unifiedSidebar` (one merged tree, keyed by left
  paths). Only the last is "the one flat sidebar file list": one list of the comparison's changes. The two-explorer
  sidebar shows the left side's files in one list and the right side's in the other; a commit grouping belongs to
  neither side alone.
- **Sections.** `ExplorerSection` (kind `.changes` or `.ignored`) feeds `FileOutlineView`, an `NSOutlineView` source
  list: one section shows its rows plainly, several become group rows, which cannot be selected. Items are reused
  by path (`itemsByKey[node.id]`), and fold state lives in the window-owned `ExplorerUIState.collapsed`, keyed by
  chain key, so it survives a rebuild, a change of style and a change of placement.
- **Badges and filters.** The badge letter comes from the net `PathStatus` (`Comparison.summaryKind`); its fill comes
  from `BadgeChangeStates` (git status of a working tree: filled when staged, stroked when unstaged or untracked,
  CARD-09). "Show changed files only" filters `.same` paths out; "Show ignored files" adds an Ignored Files section.
- **Git.** `AtelierGit.GitClient` runs every command through `ProcessRunner` (`HardenedProcessRunner` on a
  `BlockingOffloadPool` of width 4, behind `InterruptibleProcessRunner`), with `GitIsolation`'s pinned flags,
  `diff.autoRefreshIndex=false` among them, `GIT_OPTIONAL_LOCKS=0`, and the repository's configuration judged by
  `GitConfigPolicy` first. `SourceLoader` clients get a 60 s timeout; standard output is capped at 512 MiB. Output is
  returned whole, not streamed. A non-zero exit throws `GitError.commandFailed`, so `merge-base --is-ancestor`, which
  answers "no" with exit 1, needs its own method that reads the status. `recentCommits` already passes
  `--no-show-signature`, which every `log` here must too.
- **Which sides are "one repository".** `SourceLoader.renames(from:to:)` already draws that line: two `.gitRef`s of the
  same repository URL, or a `.gitRef` on the left and a `.directory` at that repository's root (the working tree) on
  the right. `ComparisonSource` also has `.file`, a plain `.directory` and `.patch`, none of which has history.
- **Renames.** Net renames come from `git diff --name-status -M --diff-filter=R` between the two sides and merge into
  `Comparison.renames` (left path ↔ right path). Card headers read `new ← old`; the file list, tabs and status bar
  keep the new name only (D14, CARD-09).
- **Reloads.** GIT-03 keeps what is on screen during any reload; GIT-04 re-renders only files whose blobs changed.
  TAB-10 makes the file list a fixed first tab.

## Prior art

- **GitHub pull requests.** The Commits tab lists every commit between base and head (merges from the base
  included), oldest first, grouped by day, and stops at 250 commits with a note that more exist; the Commits tab
  counts up to 10,000. Files changed shows the **net** diff against the merge base (three-dot) with a file tree
  that lists each file once. A commit filter (keyboard `C`) narrows Files changed to one commit or a range, and then
  shows **that commit's own diff**; since December 2025 this stays on the Files changed page rather than
  redirecting. A file touched by three commits therefore appears in each commit's view, and once in the net view.
  Files changed stops listing at 3,000 files.
- **Xcode.** The Source Control navigator's Repositories tab lists a branch's commits, newest first; selecting one
  shows the files it changed in the inspector, and double-clicking shows that commit's diff. The Changes tab lists
  uncommitted work, with staging explicit since Xcode 15. The Project navigator marks files changed since the last
  commit with a letter. Xcode never mixes commits and a net diff in one list: a commit's detail is the commit's own
  change.

Both tools keep **one net list** and offer the **per-commit view on request**. Both list a file under every commit
that touched it. Neither lists files for a merge commit on its own row by default: GitHub lists the merge as a
commit, and its files show only when it is picked.

## Open questions

### 1. A file changed by several commits

- **A. Under each commit that touched it.** Pros: a section reads as "what this commit did", as GitHub's commit filter
  and Xcode's commit detail do; no commit looks empty because a later one touched the same file. Cons: rows repeat
  (Atelier, 500 first-parent commits: 855 paths, 2,186 rows; Homebrew, 1,000 commits: 2,660 net paths, 10,234 rows);
  one path has several rows, so the outline must key rows by section and path, and selection must pick one of them.
- **B. Under the last commit only.** Pros: a partition, one row per file, as many rows as the flat list, selection
  unchanged. Cons: a section no longer means its commit; the commit that added a file shows nothing when a later
  commit touched it; this answers "who touched it last", which blame answers better.
- **C. Under the first commit only.** The same partition, with the opposite bias, and the same flaw.

**Recommendation: A.** It is what "group by commit" means, and what both reference tools show. The duplicated rows are
bounded by the cap below, and collapsed sections keep the visible rows few.

### 2. A file changed then changed back within the range

The net diff does not hold it: the comparison has no status for it, no card and nothing to show. On this repository
no such path appears in the last 500 commits; on Homebrew's last 1,000, 1,534 of 4,194 touched paths (37 %) are not in
the net diff (changed back, or added then deleted).

- **A. Hide the row.** Pros: every row opens a card; the grouped list holds exactly the net files. Cons: a section can
  lose some or all of its rows.
- **B. Show it dimmed, without a badge, unselectable.** Pros: the commit reads complete. Cons: rows that lead nowhere;
  on merge-heavy histories a third of the rows.
- **C. Show it and open the commit's own diff for it.** Needs the per-commit view for a single row, a second kind of
  card in the list.

**Recommendation: A**, with the section kept: a section whose files were all changed back shows one inert line,
"No net changes: later commits changed these files back". The tooltip of every section says how many of its files
were changed back, so nothing is silently lost. The per-commit view (question 8) shows them.

### 3. Merges: first-parent history or every parent

Measured on Homebrew, a merge-per-pull-request history: 25,333 first-parent commits against 52,834 in all.

- **A. First-parent (`git log --first-parent`).** Since git 2.31, `--first-parent` implies
  `--diff-merges=first-parent`, so a merge carries its whole diff against the mainline (checked on git 2.55: the
  merge lists its files). The first-parent diffs telescope: their path union equals the net diff's paths when the
  left side is on the right side's first-parent chain (checked on Homebrew's last 50 commits: identical sets).
  Pros: half the sections on merge-heavy repositories; a merged pull request reads as one section, as it reads in
  `main`'s history; every net file is attributed. Cons: the commits inside a merged branch are not shown one by one.
- **B. Every commit, merges without files (plain `git log`).** Pros: each branch commit gets its own section. Cons:
  merges show nothing by default, so conflict resolutions made in the merge are attributed to no commit; `-m` would
  list the merge once per parent and repeat everything; 1.3× to 1.5× the time (below); twice the sections.
- **C. Every commit, merges as combined diffs (`--cc`).** Only conflicted hunks show, and the cost of a text diff per
  merge is paid.

**Recommendation: A.** One edge needs care: when the left side is an ancestor of the right side but not on its
first-parent chain (the left is a commit inside a branch that `main` later merged), the first merge section also
holds changes the left side already has. The log itself shows it: the oldest loaded commit's first parent is not
the left side. Then the loader runs the range again without `--first-parent`, and says so in the section tooltip
("History includes merged branches"). Rows stay limited to net files (question 2), so nothing false is listed.

A merge section's header reads like any other; its tooltip adds "Merge of N commits". Expanding a merge into its
branch's commits would nest sections, which a flat list cannot hold; it is left for later.

### 4. Renames and copies across commits

The file list shows new names only (D14), keyed by left path.

- **A. `-M` per commit, chained.** Walk the commits oldest to newest; each `R old→new` moves the file's identity from
  `old` to `new`; a path in any commit is mapped to its final right path, then to the comparison's left-path row
  through `Comparison.renames.byRight`. Pros: exact across several hops (`a → b → c`). Cons: rename detection costs
  (Homebrew, 10,000 commits: 1.6 s with `-M` against 0.54 s without); within the cap the difference is 100 ms
  against 70 ms, and on this repository 33 ms against 30 ms for its whole history.
- **B. `--no-renames`, mapped through the net renames only.** A rename commit reads as `D old` and `A new`, and both
  map to the one row, since the net comparison knows `old ↔ new`. Pros: cheapest. Cons: a file touched only under an
  intermediate name is lost (a two-hop rename).
- **C. Copies (`-C`).** Detecting copies reads every modified file of the commit as a candidate source; a copy then
  reads as added in both the commit and the net diff anyway.

**Recommendation: A** within the cap, no copy detection: a copied file reads as added, as the net diff does. The row
under an older commit keeps the file's new name (D14); the row tooltip adds "Named `old/path` in this commit" when the
name then was different. The badge is the net one (question 6 of the sketch), so a file renamed with no change reads
`R` in every section it appears in.

### 5. Uncommitted and staged changes

When the right side is the working tree of the repository, the net diff runs from the left ref to the files on disk,
which includes work that no commit holds.

- **A. One "Uncommitted Changes" section, first.** It holds every net file whose working-tree state differs from
  `HEAD`: tracked changes from `git diff --raw -M HEAD` (index and working tree against `HEAD`; 15 ms here) plus the
  untracked files the status snapshot the side already reads lists. Staged or not reads on the badge, as it does
  today (CARD-09: filled when staged, stroked when not). Pros: one place, no repeated rows for a half-staged file,
  and the badge already carries the distinction. Cons: staged and unstaged are not apart.
- **B. Two sections, "Staged Changes" and "Unstaged Changes", as Xcode's commit sheet does.** Pros: mirrors `git
  status`. Cons: a partly staged file sits in both; the app has no index side, so both sections would show the same
  net card; it doubles what the badges say.
- **C. Fold uncommitted work into no section.** It would be attributed to nothing and lost.

**Recommendation: A.** A file that commits touched and that is also edited on disk sits in its commits and in
Uncommitted Changes. The range of commits is `left..HEAD`, since `HEAD` is what the working tree builds on.

### 6. What "share the same ancestry" admits

- **A. The left side is an ancestor of the right (`git merge-base --is-ancestor left right`, exit 0).** Then
  `left..right` is exactly the history between the two states, and the first-parent diffs add up to the net diff.
- **B. Any common merge base.** With a diverged left side, the two-dot net diff the app shows (left tree against right
  tree) also holds the left side's own commits since the base, in reverse. Commits on the right side would not
  explain those rows: they would sit in no section, or in a second family of "undone" sections, read backwards.
  GitHub avoids this by diffing from the merge base (three-dot), which is a different comparison.
- **C. Either direction (right an ancestor of left, after Swap).** Every section would describe a commit the
  comparison undoes: an added file reads as deleted.

**Recommendation: A only.** A diverged left side gets the "doesn't apply" state with a one-click **Compare from Merge
Base** (the left side becomes the merge base's commit), which is exactly GitHub's view, built from sources the app
already has. A reversed comparison gets the state with **Swap Sides**. Unrelated histories (no merge base) and equal
states get the state without an action (equal states with a working tree on the right still show Uncommitted
Changes). Both checks cost one git run of about 5 ms here and 10 to 14 ms on Homebrew at 10,000 commits.

"One repository" follows `SourceLoader.renames(from:to:)`: two refs of the same repository, or a ref on the left and
the working tree at that repository's root on the right. A folder, a single file, a patch, or two different
repositories never qualify. Linked worktrees share one object store but have different roots; they follow the same
rule as renames for now (a follow-up could compare `git rev-parse --git-common-dir`).

### 7. The section header

The sidebar is narrow, and a source-list header is one line.

- **A. Subject and file count on the row; the rest on hover.** The row: the subject, truncated at the tail, and the
  number of files the section lists, trailing, as a source list shows counts. The tooltip: short id, author, date
  (absolute and relative), the full first paragraph of the message, "N files changed back" when any, and "Merge of N
  commits" for a merge. The accessibility label reads all of it.
- **B. Two lines: subject, then `abc1234 · Author · 3 days ago`.** More to read at a glance, twice the height for every
  section, and an outline of different row heights.
- **C. Add line counts (`+12 −4`).** Needs `--numstat`, a text diff of every file of every commit: 3.4× to 8× the
  time of `--raw` (this repository, whole history: 153 ms against 33 ms; Homebrew, 1,000 commits: 497 ms against
  100 ms; 10,000: 12.6 s against 1.6 s).

**Recommendation: A**, no line counts. The file count is the one the list shows, after hiding changed-back files, so
it always matches the rows beneath. Sections run newest first, as `git log` and Xcode's history do, with Uncommitted
Changes on top, so the list reads from the right side's state backwards to the left's.

### 8. What selecting a section does, and which diff it shows

- **A. Nothing: a section is a group row, disclosure only.** Simplest; matches the current Ignored Files header.
- **B. It opens its files in the temporary tab, as selecting a folder does, with the net diff per file.** The cards are
  the ones the flat list already shows (GIT-04 reuse), just the commit's files, in the list's order; the tab reads the
  commit's subject. A double click pins it. Pros: consistent with every other card; no new rendering path. Cons: a
  card shows the whole net change of a file, including what other commits did to it.
- **C. It shows each file's per-commit diff (`commit^` against `commit`).** Pros: exactly GitHub's commit filter.
  Cons: a second pair of sides inside one comparison; every card, badge, rename and GIT-04 cache assumes one left and
  one right.

D31 chose B. In use it read as "a weird sum": the same file under two commits showed the same diff twice, the whole
range's. **D39 replaces it with C**, for sections and for the files under them (GIT-06 criterion 5):

- **A file under a commit** shows that commit's own change to it, from the commit's first parent to the commit: a
  rename inside the commit reads its old path at the parent and its new path at the commit, an addition has an empty
  left side, a deletion an empty right side. The change is the one the listing already recorded
  (`GitCommitChanges`), with its paths and both blob ids.
- **A selected commit section** shows each of its files that way, as cards in its temporary tab; a double click pins
  the tab. The cards are the section's rows, the files the net diff holds, so the tab lists what the sidebar lists.
- **Uncommitted Changes** shows `HEAD` against the working tree, for its files and for the section.
- **Earlier Changes** stands for the range from the left side to the oldest listed commit's first parent. No listed
  commit touched its files, so for them that range and the comparison agree: they show the comparison's own pairs.
- **Everything else** (grouping off, the plain list, a folder, the file list's tab) shows the comparison, left against
  right, as before. "Compare This Commit" and "Copy Commit ID" stay on the section's context menu.

How it is built, with no second comparison model:

- **Selection keys.** A section is selected under `\0section:<id>`; a file under it under
  `\0section:<id>\0<path>`, so the same file under two commits is two selections: two tabs, two scroll positions, two
  highlighted rows. The outline keys each row by its section and path and selects that key; a plain path from the
  model still lands on the clicked row, or the newest section's.
- **A scope on the selection.** `CommitScope` (`DiffComparison/CommitScope.swift`) is what a commit or Uncommitted
  Changes key shows: two sources of its own, `.gitRef(parent)` and `.gitRef(commit)`, or `.gitRef(HEAD)` and the
  working tree, and one `FilePair` per file built from the change's own paths and blob ids (a working-tree file takes
  the blob its side's listing hashed). The model derives it from the selection on every render and hands its target
  and sources to the same `RenderPipeline`. The blobs are read by id through `cat-file --batch` in the preparer's
  off-main load, and a newer selection bumps the pipeline's generation, so a late result for the previous one is
  dropped.
- **What names it.** A tab reads the file's name and the commit's subject and short id (`name · subject · abc1234`), a
  section's tab the subject and short id; its tooltip adds the header's. The status bar names the file by the change's
  own path and says which section it comes from, and its `+N −M` counts are the shown diff's. A card's header, badge
  letter and fold read the change's own paths and kind; its badge reads committed under a commit.
- **Diagnostics** apply only to a side the change shares with the comparison, the only sides analyzed: the working
  tree's under Uncommitted Changes, none under a commit.

A section row therefore stops being an AppKit group row (those cannot be selected): it becomes an expandable row
drawn as a header. The Ignored Files section keeps its group row.

## The spike

Every command ran read-only through `~/.agent-harness/bin/work run --agent git06 --weight 1`, with the app's pinned
`-c` flags (`diff.autoRefreshIndex=false` among them), `GIT_OPTIONAL_LOCKS=0`, `LANG=C`. A Python harness spawned each
command, warmed it once, then timed 9 runs (Atelier), 7 runs (Homebrew, up to 1,000 commits) or 3 runs (Homebrew,
10,000 and all), wall clock including process spawn. Machine: Apple M3, 8 cores; git 2.55.0; both repositories have
commit-graph files. Ranges are `HEAD~N..HEAD`, so N counts first-parent commits.

This repository has 703 commits, 570 of them first-parent and 2 merges, so a range of 1,000 does not exist here: the
ranges measured are 10, 100, 500 and all. To see 1,000 commits and beyond, the same harness ran on the public
Homebrew/brew clone at `/opt/homebrew` (52,834 commits, 25,333 first-parent, a merge per pull request, 3,391 files).
The `log` format asked for `%H %P %an %aI %s`, NUL-separated, with `--raw`, which carries both blob ids.

### Atelier (`/Users/guillaumecoquard/Developer/g-cqd/Atelier`), median ms (max)

| Command | 10 | 100 | 500 | all (570 fp / 703) |
|---|---|---|---|---|
| `rev-list --count` | 5.2 (5.9) | 5.2 (5.4) | 5.2 (5.4) | 5.6 (6.4) |
| `rev-list --count --first-parent` | 5.9 (6.4) | 5.2 (5.6) | 5.8 (7.2) | 5.4 (5.6) |
| `merge-base --is-ancestor` | 5.0 (6.0) | 5.2 (5.3) | 5.1 (5.3) | — |
| `merge-base` | 4.9 (5.3) | 5.0 (5.7) | 5.1 (5.3) | — |
| `diff --raw -M` (net, left to right) | 6.0 (6.4) | 7.8 (8.0) | 16.0 (16.6) | — |
| `log --first-parent`, headers only | 5.4 (5.7) | 6.7 (8.3) | 10.2 (10.6) | 11.2 (12.1) |
| `log --first-parent --raw -M` | 8.6 (10.2) | 14.0 (14.9) | 26.3 (26.5) | 33.4 (36.9) |
| `log --first-parent --raw --no-renames` | 8.6 (9.2) | 13.7 (14.0) | 26.1 (26.4) | 29.9 (32.1) |
| `log --raw -M` (every commit) | 8.3 (8.5) | 14.1 (14.7) | 26.6 (27.8) | 46.5 (49.9) |
| `log --first-parent --numstat -M` | 10.7 (11.1) | 29.9 (30.2) | 110.5 (112.4) | 153.1 (157.4) |
| `log --first-parent --raw -M -n 100` | 8.1 (8.3) | 13.9 (15.2) | 14.4 (15.1) | 14.2 (15.2) |
| Output of `log --first-parent --raw -M` | 4 KiB | 54 KiB | 322 KiB | 495 KiB |

Working tree, this repository: `status --porcelain=v2 -z --untracked-files=all` 20.8 ms, `diff --raw -M HEAD` 15.1 ms,
`diff --cached --raw -M` 11.7 ms.

### Homebrew/brew (`/opt/homebrew`), median ms (max)

| Command | 10 | 100 | 1,000 | 10,000 | all (25,333 fp / 52,834) |
|---|---|---|---|---|---|
| commits in range (fp / all) | 10 / 23 | 100 / 227 | 1,000 / 2,473 | 10,000 / 28,182 | 25,333 / 52,834 |
| `rev-list --count` | 5.0 | 5.0 | 5.6 | 12.1 | 32.0 |
| `rev-list --count --first-parent` | 5.1 | 4.9 | 5.1 | 12.6 | 22.8 |
| `merge-base --is-ancestor` | 4.8 | 4.9 | 5.1 | 9.4 | — |
| `merge-base` | 4.8 | 4.8 | 5.2 | 13.5 | — |
| `diff --raw -M` (net) | 5.6 | 14.1 | 59.4 | 27.4 | — |
| `log --first-parent`, headers only | 5.2 | 6.7 | 15.2 | 95.1 | 417 |
| `log --first-parent --raw -M` | 6.4 | 19.8 | 100.3 | 1,589 | 3,509 |
| `log --first-parent --raw --no-renames` | 6.3 | 13.8 | 69.8 | 537 | 1,529 |
| `log --raw -M` (every commit) | 6.8 | 21.5 | 127.0 | 2,286 (max 3,323) | 4,684 |
| `log --first-parent --numstat -M` | 11.7 | 73.9 | 497.2 | 12,621 | 17,642 |
| `log --first-parent --raw -M -n 100` | 6.5 | 19.7 | 20.0 | 52.5 | 42.7 |
| Output of `log --first-parent --raw -M` | 6 KiB | 146 KiB | 1.2 MiB | 17 MiB | 24 MiB |

Paging in Homebrew's 10,000-commit range: 100 commits after `--skip=5000` 136 ms, after `--skip=9900` 64 ms; the
first 500 commits 123 ms.

### Paging under load

A later job compared three ways of listing up to 1,000 commits, interleaved over 7 rounds so that each saw the same
load: one run of 1,000; five pages of 200, each continuing from the first parent of the previous page's oldest
commit; and 200 then the remaining 800. Other agents were loading the machine then (load average 54 at the start,
127 at the end, on 8 cores), so the absolute times are 10 to 17 times the ones above. The ratios are what this run
is for.

| Range | One run of 1,000 | Pages of 200: first, total | 200, then 800: first, total |
|---|---|---|---|
| Homebrew `HEAD~10000..HEAD` | 1,657 ms | 322 ms, 1,833 ms | 292 ms, 1,784 ms |
| Homebrew `HEAD~1000..HEAD` | 1,667 ms | 306 ms, 1,751 ms | 285 ms, 1,911 ms |
| Atelier, whole history (570) | 438 ms | 146 ms, 443 ms (3 pages) | 201 ms, 453 ms |

Pages from a boundary cost 0 to 10 % more in total than one run, and the first page lands after 18 to 33 % of the
total. On a loaded machine, one run of 1,000 commits takes 1.7 s, which is the case progressive loading exists for.
The load average was not recorded for the earlier tables; their maxima sit within 10 % of their medians, so each was
taken under steady load.

### What the numbers say

- **The checks are free.** `rev-list --count`, `merge-base` and `--is-ancestor` sit at the spawn floor (about 5 ms) up
  to 1,000 commits and stay under 35 ms for 52,834. They run before anything else, every time.
- **The listing grows with commits and files, and renames dominate at scale.** `--raw -M` costs about 0.1 ms per
  first-parent commit at Homebrew's density (100 ms per 1,000) and 0.06 ms at this repository's, but 0.16 ms per commit
  at 10,000 (rename detection over large merges). `--numstat` multiplies it by 3 to 8, which rules line counts out.
- **The first page is cheap whatever the range.** 100 commits cost 14 to 53 ms however long the range. `--skip` walks
  the skipped commits again (136 ms at 5,000 deep), so pages continue from a boundary instead: the next page is
  `left..P` where `P` is the first parent of the oldest commit loaded, which starts the walk where the last one ended.
- **The output fits.** 1,000 commits produce 1.2 MiB, far under the runner's 512 MiB cap and the 60 s timeout.
- **Rows grow faster than paths.** Listing each commit's files repeats rows: 2,186 rows for 855 paths here (500
  commits), 10,234 rows for 2,660 net paths on Homebrew (1,000 commits).

### Cap and progressive loading, derived

1. **Check** (off the main actor, about 10 ms): resolve both sides, `merge-base --is-ancestor`, and
   `rev-list --count --first-parent left..right` for the header count. A failure or "no" ends here with the
   "doesn't apply" state.
2. **First page: 200 commits** (`log --first-parent --raw -M -z -n 200 left..right`): between the measured 100
   (14 to 20 ms idle) and 500 (26 ms here, 123 ms on Homebrew), so about 20 ms here and 50 ms on Homebrew when the
   machine is idle, and about 150 to 300 ms under the heavy load measured. The grouped list appears after it, with the
   unloaded remainder in a trailing **Earlier Changes** section (below).
3. **Following pages of 200** from the boundary, one at a time, each merging into the groups off the main actor,
   until the range ends or the cap is reached. Each page is one git run and one rebuild of the list; paging costs at
   most 10 % more than one run, and the list never waits on more than one page.
4. **Cap: 1,000 commits**, 5 pages: about 100 ms of git in all on Homebrew when idle (1.7 s under heavy load), 33 ms
   for this repository's whole history, 1.2 MiB of output, at most about 10,000 rows. The next step, 10,000 commits,
   costs 1.6 s of git idle, 17 MiB and 100,000 rows, and nobody reads a thousand sections in a sidebar. The cap is of
   the order of GitHub's own limit (250 commits listed on a pull request).
5. **Beyond the cap**, the net files no loaded commit touched go into **Earlier Changes**, with a row "N older commits
   not listed; Compare This Range…" that opens the comparison from `left` to the oldest listed commit's first parent,
   a range the grouping can then list in turn.

Every run is cancelled by a new comparison, a reload or turning the setting off (cancelling terminates git). A
reload of the same range with the same commit ids reuses the loaded groups; with the right side moved by a commit on
top (GIT-01), only `oldRight..newRight` is listed and prepended when `oldRight` is an ancestor of `newRight`.

Sections default to expanded when the range holds 20 commits or fewer, and to collapsed beyond, except Uncommitted
Changes, so that a long range opens as a list of headers, a few hundred rows at most, not 10,000.

## UI sketch

### The sidebar, grouped

```
┌ Sidebar (merged tree, flat list, grouped by commit) ─────────────┐
│ ▾ Uncommitted Changes                                        3   │
│     [M] Apps/GitDiffViewer/Sources/.../ExplorerTrees.swift       │   stroked badge: unstaged
│     [A] Apps/GitDiffViewer/docs/commit-grouping-design.md        │   stroked A: untracked
│     [M] docs/requirements/book.md                                │   filled badge: staged
│ ▾ Docs: record GIT-06, the flat file list grouped by commit  1   │
│     [M] docs/requirements/book.md                                │
│ ▾ AtelierQuery: never read a quoted predicate argument as…   2   │
│     [M] Packages/AtelierCore/Sources/AtelierQuery/QueryPar…      │
│     [M] Packages/AtelierCore/Tests/AtelierQueryTests/Query…      │
│ ▸ AtelierQuery: move QueryParser's scanner into its own f…   3   │
│ ▸ Merge branch 'feature/tabs'                               41   │
│ ▾ Fix the ref menu's order                                       │
│     No net changes: later commits changed these files back       │   inert, secondary text
│ ▸ Earlier Changes                                           12   │
│     212 older commits not listed · Compare This Range…           │
│ ▸ Ignored Files                                                  │   unchanged, when shown
└──────────────────────────────────────────────────────────────────┘
```

- **Section rows**: disclosure triangle, the subject (tail-truncated), the file count trailing in secondary text.
  Tooltip: `3f2a9c1 · Guillaume Coquard · 25 Sep 2026 at 14:02 (2 hours ago)`, then the message's first paragraph,
  then "1 file changed back" or "Merge of 14 commits" when they apply. Uncommitted Changes and Earlier Changes read
  as fixed titles.
- **File rows**: the same row as the flat list (full path, new name only, D14), indented one level under their
  section. The tooltip adds "Named `old/path` in this commit" when the path then differed.
- **Order**: Uncommitted Changes, then commits newest first, then Earlier Changes, then Ignored Files. Within a
  section, files in the flat list's order (`localizedStandardCompare`).
- **Disclosure**: each section folds on its own; the state is kept in the window's `ExplorerUIState` under
  `commit:<full id>`, `uncommitted` and `earlier`, so it survives reloads, re-comparisons, style and placement changes
  (GIT-03, GIT-06 criterion 3). ⌥-click folds or unfolds every section, as outlines do.
- **While loading**: the previous grouping stays on screen, marked updating as the cards are (GIT-03, D13); the first
  time, the flat list shows until the first page lands, then turns into sections in one step, keeping the selection.

### Badges and filters

- **Badge letter**: the net status of the file (A, M, D, R), the same in every section it appears in, so a badge means
  the same thing everywhere (CARD-09 criterion 4). The commit's own action on the file (it may have added a file the
  net diff shows as modified) is in the row's tooltip, not the badge.
- **Badge fill**: unchanged, from `BadgeChangeStates` (staged, unstaged, untracked), so it only varies when the right
  side is the working tree, and it varies the same way in every section.
- **Selection inversion and focus** (CARD-10): unchanged.
- **Show changed files only**: grouped rows are changed files by construction, so the filter has nothing to remove;
  it keeps its value and applies again when grouping is off or does not apply.
- **Show ignored files**: the Ignored Files section stays as the last section, unchanged.
- **The file list tab** (TAB-10) still shows every changed file in path order; grouping changes the sidebar only.

### The setting

- **Label**: `SettingLabel.groupsByCommit = "Group changed files by commit"`, one label on every surface (settings
  design R3). Off by default (P6).
- **Settings ▸ General ▸ File Explorers**, right after "Arrange files as", as a toggle; overridable per project like the
  tree style (no `.appWide`). Caption: "Lists the files each commit changed under a section of its own. Applies to
  the flat list in the merged sidebar, when the left side is an ancestor of the right in one repository."
- **View options menu**, under "Arrange files as", as a checkmark item with the same label. When it does not apply to
  this window, the item stays enabled (it is still the preference) and carries the reason as its subtitle
  (`NSMenuItem.subtitle`), e.g. "Needs the flat list of paths".

### The "doesn't apply" state

Grouping applies when all hold, checked in this order; the first that fails names the reason. While the setting is
off nothing shows. While it is on and does not apply, the sidebar keeps the plain flat list (or tree) and shows one
line above it, in secondary text, with the action as a link-style button; the same reason is the menu subtitle.

| Condition that fails | Line shown | Action |
|---|---|---|
| Placement is not the merged sidebar | Grouping by commit needs the merged sidebar. | Use Merged Sidebar |
| Style is not flat | Grouping by commit needs the flat list of paths. | Use Flat List |
| A side is a folder, a file or a patch | Grouping by commit needs two states of one repository. | — |
| Two different repositories | The two sides are in different repositories. | — |
| No common history | These states share no history. | — |
| Right is an ancestor of left | The newer state is on the left. | Swap Sides |
| Diverged | `main` is not an ancestor of `feature`. | Compare from Merge Base (`3f2a9c1`) |
| Git refused the configuration, or failed | Couldn't read the history: the error's text | — |

Equal states with the working tree on the right are not a failure: the list holds Uncommitted Changes only. Equal
refs show the usual empty comparison.

## Build plan

Each step builds, keeps every suite green, and lands as its own commit. Core git code lives in `AtelierGit` (GIT-02
criterion 2: git operations reusable by the terminal editor).

1. **AtelierGit: ancestry checks.** `GitClient.isAncestor(_:of:) async throws -> Bool` (exit 0 true, exit 1 false,
   anything else throws) through a status-reading `execute` path; `GitClient.mergeBase(_:_:) async throws -> String?`
   (nil for unrelated histories, exit 1); `commitCount(range:firstParent:)`. Arguments through `checked` and
   `--end-of-options`.
   Files: `Packages/AtelierCore/Sources/AtelierGit/GitClient+History.swift` (new), `GitParsers.swift`;
   tests `Packages/AtelierCore/Tests/AtelierGitTests/GitClientHistoryTests.swift` with `FakeProcessRunner`.
2. **AtelierGit: the commit listing.** `GitCommitChanges` (id, parent ids, author, author date, subject, changes: status,
   old path, new path, old and new blob ids) and `GitParsers.commitChanges(_:)` for
   `log --no-show-signature --no-ext-diff --no-textconv --raw -M -z --format=%x1e%H%x1f%P%x1f%an%x1f%aI%x1f%s`;
   `GitClient.commitChanges(from:to:firstParent:limit:)`. Parser tests: a merge with its first-parent diff, a rename,
   a delete, an empty commit, paths with spaces, newlines and non-ASCII, a subject with a unit separator.
   Files: `GitClient+History.swift`, `GitParsers.swift`, `GitTreeEntry.swift` or a new `GitCommitChanges.swift`;
   tests `GitParsersCommitChangesTests.swift`.
3. **DiffComparison: attribution, pure.** `CommitGrouping.build(comparison:commits:uncommitted:isComplete:)` returning
   ordered groups (`uncommitted`, `commit(id)`, `earlier`) of left paths: each commit lists every net file it touched,
   renames chained oldest to newest and mapped through `Comparison.renames`, changed-back files dropped and counted,
   unattributed net files in `earlier`, and the "not on the first-parent chain" signal. `@concurrent` off-main entry
   like `ExplorerTrees.buildOffMain`.
   Files: `Apps/GitDiffViewer/Sources/DiffComparison/CommitGrouping.swift` (new);
   tests `Apps/GitDiffViewer/Tests/GitDiffViewerTests/CommitGroupingTests.swift`.
4. **DiffComparison: eligibility, pure.** `CommitGroupingEligibility` from placement, style, both `ComparisonSource`s
   and the ancestry answers, yielding `.applies(range, includesWorkingTree:)` or `.doesNotApply(reason)` with the
   reason's text and action, in the table's order.
   Files: `DiffComparison/CommitGroupingEligibility.swift` (new); tests `CommitGroupingEligibilityTests.swift`.
5. **The setting.** `ViewerSettings.groupsByCommit` (off, stored under `groupsByCommit`, `.trees` change), restore,
   project override key, `SettingsScope` label and value, `SettingLabel.groupsByCommit`; the General toggle and
   caption; the View options menu item.
   Files: `ViewerSettings.swift`, `ViewerSettings+Restore.swift`, `ViewerSettings+ProjectOverrides.swift`,
   `SettingsScope.swift`, `SettingLabels.swift`, `GitDiffViewer/Views/SettingsView.swift`,
   `GitDiffViewer/Views/ViewOptionsMenu.swift`; tests in the existing settings and overrides suites.
6. **The model: loading.** `DiffViewerModel+CommitGroups.swift`: after a comparison lands, check eligibility, run the
   checks, load pages of 200 up to 1,000 from the boundary, rebuild groups off the main actor per page, cancel on
   any new comparison, reload or setting change, keep the previous groups while updating, reuse them for an unchanged
   range and prepend for a moved right side. `ExplorerSection.Kind` gains the commit, uncommitted and earlier kinds
   (its id stops being the raw value); `unifiedSections` returns them when grouping applies.
   Files: `DiffViewerModel+CommitGroups.swift` (new), `DiffViewerModel.swift`, `ExplorerSection.swift`,
   `DiffViewerModel+Loading.swift`; tests `DiffViewerModelCommitGroupsTests.swift` with `FakeProcessRunner`,
   `TaskProviderSpy` and `TestClock`, covering the pages, the cap, cancellation and reload continuity.
7. **The outline.** `FileOutlineView`: commit sections as selectable header rows with the trailing count and tooltip;
   rows keyed by section and path so one path can appear several times; selection maps a path to the clicked row, or
   the newest; fold state keyed `commit:<id>`; the default fold rule (20 commits); the "doesn't apply" line with its
   action; the inert "No net changes" and "older commits" lines.
   Files: `GitDiffViewer/Views/FileOutlineView.swift`, `GitDiffViewer/Views/FileExplorerView.swift`,
   `DiffComparison/ExplorerUIState.swift`; then `Apps/GitDiffViewer/scripts/main-actor-budget.sh` alone at weight 8.
8. **Selecting a section.** A tab target for a commit's files (`DiffTab` gains a target: a path or a commit group),
   rendering their cards in list order, titled by the subject; context menu Compare This Commit and Copy Commit
   ID; Compare This Range for Earlier Changes. D39 then made a section and each file under it show the commit's own
   change (question 8).
   Files: `DiffTabs.swift`, `DiffViewerModel+Selection.swift`, `DiffViewerModel+Presentation.swift`,
   `GitDiffViewer/Views/TabBarView.swift`, `FileOutlineView.swift`; tests in `DiffTabsTests.swift` and
   `DiffViewerModelSelectionTests.swift`.
9. **The actions of the "doesn't apply" state.** Use Merged Sidebar, Use Flat List, Swap Sides (existing), Compare
   from Merge Base (sets the left side to the merge base's commit).
   Files: `DiffViewerModel+CommitGroups.swift`, `SideState.swift`; tests in `DiffViewerModelCommitGroupsTests.swift`.
10. **A benchmark, env-gated.** Grouping and outline rebuild for 1,000 commits and 10,000 rows under `GDV_BENCH`,
    recording the rebuild time against the explorer's `PhaseTrace` line.
    Files: `Tests/GitDiffViewerTests/CommitGroupingBenchmark.swift` (new).

Steps 1 and 2 are core and independent of the app; 3 and 4 are pure and can run in parallel after 2; 5 is independent
of 1 to 4; 6 needs 1 to 5; 7 needs 6; 8 and 9 need 7; 10 can follow 7.

## Left for later

- Nesting a merge's branch commits under its section.
- Per-commit line counts, if a cheaper source than `--numstat` appears (for example computing them from the loaded
  blobs of the files already rendered).
- Linked worktrees as one repository (`--git-common-dir`).
- Grouping in the two-explorer sidebar or under the hierarchy styles.
- Ordering the file list tab's cards by commit.

## Sources

- GitHub, [Repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits)
  (250 commits listed on a pull request, 10,000 on the Commits tab).
- GitHub changelog, [Review commit-by-commit … in the pull request "Files changed" public preview](https://github.blog/changelog/2025-12-11-review-commit-by-commit-improved-filtering-and-more-in-the-pull-request-files-changed-public-preview/),
  2025-12-11, and [Improved pull request "Files changed" page on by default](https://github.blog/changelog/2026-01-22-improved-pull-request-files-changed-page-on-by-default/), 2026-01-22.
- GitHub Docs, [Reviewing proposed changes in a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/reviewing-proposed-changes-in-a-pull-request).
- Apple, Xcode documentation, *Tracking code changes in a source control repository* (Source Control navigator,
  Repositories and Changes tabs, commit history and detail).
- Apple Developer Forums, [Xcode 15, how to not stage all new…](https://developer.apple.com/forums/thread/738501)
  (explicit staging since Xcode 15).
- git 2.55 `git-log(1)`: `--first-parent` implies `--diff-merges=first-parent`; checked on Homebrew/brew.
