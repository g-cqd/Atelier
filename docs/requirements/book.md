# Requirements book: Atelier (GitDiffViewer, KittyCode, AtelierCore)

This book states what the user asked for between 2026-09-19 00:00 and 2026-09-23 13:29 (CEST), as testable
requirements. It is written from the requesting side: what is needed and why, not how. `plan.md` maps every open
requirement to a wave of the fix plan, the roadmap, a decision, or "unplanned"; `audit.md` gives one status per
requirement at `main` `ebafb9f` (2026-09-23 14:26 CEST).

The first revision, at `10ae905`, covered requests up to 09-23 07:59 and later answers up to 12:06. This revision,
written between 13:40 and 14:40 on 09-23, re-reads every source from 09-19 on. It adds 18 messages and 5 rows of
decisions (R81 to R103), 13 requirements (121 in all), a new area (REND), and amendments to 13 existing
requirements.

## Open questions

None. The twelve questions of 09-23 (OQ1 to OQ12) were answered between 14:45 and 14:53; the answers are D9 to D20
under "Decisions" below. OQ2 needed no answer: D5 already settles the pin, which the coordinator applies when the aemi
fixes land. OQ3's first half was carried out under D6: at 14:40 the six clones outside `~/Developer` were patched
(backup `~/project-hooks-ph6-backup-2.tar.gz`), and no hook on the machine runs a repository's own binary any more.

**Defaults kept unless the user objects.** Chosen without an explicit answer, and listed to the user with the answers:
- A file with both staged and unstaged changes draws a stroked badge (CARD-11).
- A folder draws stroked when git reports any unstaged or untracked file inside it, even one the list hides (CARD-11).
- The SDK documentation tier follows the app-wide sourcekit-lsp setting, since it has no repository (track 1A, Sec L2).
- A Findings row also scrolls to its line, with the toolbar fix of track 2D (DUI-01; GDV S18).
- The layout shortcuts ⌘1, ⌘2 and ⌘3 stay on the toolbar picker; the View menu gets no layout items (CARD-15).

## Reading guide

- **IDs** are `AREA-NN`. The areas are listed in the table below.
- **Source** gives the local time (CEST) and the user's words. Text in quotation marks is verbatim, typos
  included; `…` marks an omission, and square brackets inside a quotation mark a redaction. Everything outside
  quotation marks is a summary.
- **Decision** marks the user's answer to a multiple-choice question from the assistant. The chosen option's label
  is quoted; its description, when it matters, is quoted as the option's text.
- **Derived** marks a requirement that follows from a request without being stated in it.
- **Priority:** *Must* is a stated need or a reported bug. *Should* is a request phrased as a wish ("we might",
  "it would be nice"). *Could* is explicitly optional or research-first.
- **Superseded** entries keep their ID so the audit can close them; each names what replaced it.
- Employer repositories are called "a work repository". No work repository name, path or email appears here.

| Area | Scope |
|---|---|
| PROC | Delivery and process: clone, toolchain, install, mirrors, main branch, roadmap, fix waves, machine upkeep |
| DIAG | Diagnostics tools and what they report |
| TOOL | Tool discovery and user-set tool locations |
| HOVER | Hover documentation: content, tiers, languages, panel design, system API docs |
| DUI | Diagnostics UI: findings list, markers, popovers |
| SET | Settings: research-based design, per-project scope, appearance, live propagation, badge scheme |
| CARD | The card list (file list) and file badges |
| TAB | Native window tabs and the in-app tab bar |
| GIT | Git features, freshness and reload continuity |
| WIN | Window chrome and stability: toolbar, source selectors |
| PERF | Performance and non-blocking work |
| JSON | AemiJSON adoption |
| MOD | Modularization for GUI and terminal reuse |
| QUAL | Code quality, review processes, safety |
| DIFF | Diff interaction refinements and their Xcode reference |
| REND | A text renderer of our own and its pluggable backends |
| LANG | A file's language: detection and choice |

## Sources

Counts are for this revision's window, 2026-09-19 00:00 to 2026-09-23 13:29 CEST.

| Source | Read | Kept |
|---|---|---|
| `~/.claude/history.jsonl` | 192 entries: 103 from `~/Developer`, 89 from the employer project folders, none from a path under `Atelier`. No entry falls between 09-19 00:00 and 09-21 09:18; the first `~/Developer` entry is 09-21 13:47. | 98 prompts. 5 commands dropped: `/model` twice, `!pwd`, `/background`, and `!open` of the Xcode playground (09-23 11:57). None of the 89 employer-folder prompts mentions GitDiffViewer, Atelier or KittyCode. |
| Session transcripts in `~/.claude/projects/-Users-guillaumecoquard-Developer/`, 2 files modified since 09-19 | Main session: 96 messages, of which 64 typed turns, 5 sent while the assistant was busy and delivered as turns, and 27 mid-turn messages carrying "The user sent a new message while you were working:". Second session: 2 turns. | 98 messages, each matching a history entry. 3 pasted crash reports (676, 573 and 592 lines) are summarised in R31, R89 and R99, not copied. |
| Answers to the assistant's multiple-choice questions, and plan approvals, in the main transcript | 3 question sets with 7 answers (09-21 14:30: 2; 09-23 12:34: 4; 09-23 12:37: 1), and 1 plan approval (09-21 14:45) | All 8 kept as decisions D1 to D8 (see "Decisions"). The first revision had missed D1 to D3. |
| Screenshots (base64 image blocks, decoded to `/tmp/regather-screens`) | 20 images, numbered 02 to 10 (09-22) and 12 to 23 (09-23) by the user | 19 distinct: image 10 is byte-identical to image 09. Each was viewed. |
| Codex sessions under `~/.codex/sessions` | 3 sessions in the window; 1 has its working directory in Atelier | 0 prompts. That session's only prompt is the coordinator-generated review prompt ("You are reviewing one day's work on this monorepo"), excluded; the user's request for it is R48. The other two sessions run in employer folders and do not mention this project. |
| Subagent transcripts | about 210 files | Skipped: they hold the coordinator's briefs. |

The request index at the end has 103 rows: 98 messages and 5 rows of decisions. 2 messages concern the global
agent model configuration and are out of scope (R69, R70). What is new since the first revision's R80: R81 to R83
(three decisions of 09-21 the first pass missed) and R84 to R103 (09-23 09:03 to 13:29).

## Screenshots

| Image | Time | Sent with | What it shows | Criteria it produced |
|---|---|---|---|---|
| 02 | 09-22 11:30 | "this is how it looks for xcode" | Xcode Quick Help for `Int`: the name as a bold title, a one-sentence abstract, the declaration `@frozen struct Int` in a rounded box with a light stroke and syntax colors, hairline separators, an "Overview" section with inline code in a monospaced font, a "Relationships / Conforms To" list, and a panel that scrolls | HOVER-05, HOVER-06, HOVER-12 |
| 03 | 09-22 11:30 | "this is how it looks for us, it does not even adapt to the size of the content" | The old NSPopover: an uncolored monospaced declaration and one paragraph at the top of a panel that is mostly empty | HOVER-06, HOVER-07 |
| 04 | 09-22 14:18 | "that's also not very useful to only have that" | The panel for `StateObject`: only the declaration, with four `@_originallyDefinedIn` lines, a large empty area, and a "sourcekit-lsp" footer | HOVER-04, HOVER-07, HOVER-13 |
| 05 | 09-22 14:19 | "as you can see a lot of negative space, only the signature and not more information" | A one-line struct declaration, a "doc comment" footer, and a mostly empty panel | HOVER-03, HOVER-07, HOVER-13 |
| 06 | 09-22 14:27 | "some have duplicated informations somehow" | The same struct declaration listed three times: two identical, one an older version with one conformance fewer | HOVER-11 |
| 07 | 09-22 15:40 | "also sizing and content of hover is still not dynamic and not showing the doc content" | A dark theme's token colors washed out on a light panel, an empty area, and a "doc comment" footer | HOVER-03, HOVER-06, HOVER-07 |
| 09 | 09-22 16:20 | the 16:19 message on spacing and fonts | A computed property declared in an extension, with two `///` lines above it in the code. The panel shows only the declaration on a white chip, empty space, and a "sourcekit-lsp" footer | HOVER-03, HOVER-07, HOVER-12, HOVER-13 |
| 10 | 09-22 16:37 | the badge, appearance, tab and sticky-header message | The same bytes as image 09. The Xcode badge colors the message describes are not in any screenshot | CARD-09 and SET-07 rest on the text alone (see Q4) |
| 12 | 09-23 12:00 | "[Image #12] … [Image #21]", taken in the Xcode playground the user asked for at 11:55 | Xcode's inline modification: the old line on a gray background with no line number, the new line (416) on light blue, the changed token tan on the old line (`100`) and blue on the new one (`120`), and a solid blue change bar at the gutter's leading edge | DIFF-05; the "Xcode diff palette" idea (OQ11) |
| 13 | 09-23 12:00 | same batch | A folded `actor SyncEngine` that contains changes: a dark tab with `›` in the fold ribbon, a gray `•••` capsule between the braces, line numbers jumping from 12 to 495, and a dotted blue change bar | DIFF-03 |
| 14 | 09-23 12:00 | same batch | A folded function: the dark `›` tab, the `•••` capsule, line numbers jumping from 53 to 72 | DIFF-03 |
| 15 | 09-23 12:00 | same batch | Hovering a function: its scope outlined as a rounded capsule in the ribbon, `⌄` at its first line and `⌃` at its last, its braces lit in blue; two inner loops folded | DIFF-03 |
| 16 | 09-23 12:00 | same batch | The ribbon shaded darker for each nesting level, with an inner `if` folded; the folded line wraps and keeps one ribbon segment | DIFF-03 |
| 17 | 09-23 12:00 | same batch | Hovering the inner `if` (lines 60 to 62) outlines only that block | DIFF-03 |
| 18 | 09-23 12:00 | same batch | The ribbon at rest: gray steps by depth, and a hairline where a scope ends | DIFF-03 |
| 19 | 09-23 12:00 | same batch | A gap handle between lines 18 and 237: a small rounded grabber with two lines, centred on a hairline across the gutter | DIFF-02 |
| 20 | 09-23 12:00 | same batch | A gap handle at the top of the file, above line 12 | DIFF-02 |
| 21 | 09-23 12:00 | same batch | A gap handle above a change, above line 82 and its blue change bar | DIFF-02 |
| 22 | 09-23 12:05 | "[Image #22] [Image #23]", after "reopen xcode for the rename thing please" | Xcode's navigator row for a staged rename, selected in a focused list: "HTTPClient.swift ← APIClient.swift" in white on the blue selection, and a white badge with a blue "M" | CARD-09, CARD-10 |
| 23 | 09-23 12:05 | same | The same row unselected: the old name grayed after "←", and a filled blue "M" badge | CARD-09; the `new ← old` label (OQ9) |

There is no image 01 (the number went to the pasted crash text), no image 08, no image 11 (the 10:42 crash
report) and no image 24 (the 12:06 crash report). Images 12 to 21 are in the repository, re-encoded, under
`Apps/GitDiffViewer/docs/assets/xcode-reference/`; images 22 and 23 are not.

## Changes of mind

1. **Bundling became optional; discovery and user-set locations became mandatory.** TOOL-04 ("we could
   bundle swiftlint, swift format, arcleak, dolly and deadwood", 09-21 14:22) → decision D2, "Bundle + discovery"
   (09-21 14:30) → TOOL-03, TOOL-01 and TOOL-02 ("we don't necessarily have to bundle things in the app, but we
   definitely have to propose a way to locate the binaries in the settings of the application", 09-21 15:20).
2. **The apple-docs corpus was declined for on-device Xcode documentation.** HOVER-17 (the assistant's
   proposal, 09-22 11:21) → HOVER-04 ("i truly believe we should be able to utilize the on device xcode
   documentation, preferably not apple-docs", 09-22 11:24).
3. **The provenance footer was removed.** HOVER-18 (the panel design, commits `27bc8c3` and `b30579b`) →
   HOVER-13 ("the source of the documentation is not really necessary in this hover popup", 09-22 16:20).
4. **The tab-styling request was first misread as native window tabs, then corrected to the app's own tab
   bar.** TAB-06 (roadmap at `eeb7ffa`: "Tab bar styling (user-requested; needs investigation) … Native
   NSWindow tab restyling is largely private API") → TAB-02 to TAB-05 (corrected 09-23 07:51; roadmap at
   `10ae905`: "In-app tab bar styling (user-requested; shipped)").
5. **Pinned SwiftUI sections gave way to a custom card container.** CARD-01 was built with SwiftUI's pinned
   section headers (09-22) → CARD-12 (09-23 09:05, "maybe for the cards with sticky header in the scrollview, we
   want to go completely custom"). CARD-01's criteria stand; only the means changed.
6. **Cards dropped the stacked layout.** The card list offered inline, side by side and stacked → CARD-15 (09-23
   11:44, "file list cards should only support inline or horizontal split, but not stacked split"). The
   single-file view keeps stacked, and DIFF-01 still resizes stacked panes there.
7. **A rename is blue but keeps its R.** Q4's answer left renamed open ("renamed is unknown", 09:37) → the Xcode
   screenshots showed a blue "M" for a rename (images 22 and 23, 12:05) → the user kept the letter ("i'd prefer we
   use R for renamed though", 12:05) and gave the reason ("so it's clearer than an M that means the same thing
   than the other files", 12:06). CARD-09 records the result.
8. **JSON verdicts per call site became AemiJSON everywhere.** JSON-02 allowed a "keep Foundation" verdict per
   call site, and settings stayed on Foundation → JSON-04 (09-23 13:06, "can you make sure we use aemijson
   whenever we do json interaction to accelerate performances"). JSON-02's fast-path criterion stands.

## Decisions (09-21 and 09-23)

The user's answers to the assistant's multiple-choice questions, and one plan approval. The first revision missed
D1 to D3. D9 to D20 answer the open questions of 09-23.

| # | Time | Question, summarised | Answer | Requirements |
|---|---|---|---|---|
| D1 | 09-21 14:30 | Should the first plan land diagnostics first, everything at once, or hover first? | Typed instead of an option: "everything, incremental, atomic, fully tested, split in both parallel and sequential tracks" | PROC-09 |
| D2 | 09-21 14:30 | Should the five tools be found only, or bundled and found? | "Bundle + discovery" | TOOL-04, superseded at 15:20 |
| D3 | 09-21 14:45 | The written plan for diagnostics and hover | Approved (tool result: "User has approved your plan") | PROC-07 |
| D4 | 09-23 12:34 | Start Wave 1 (security, data loss, crashes) now as parallel agents, each on its own files? | "Start Wave 1 now (Recommended)" | PROC-11 |
| D5 | 09-23 12:34 | How to handle fixes that belong to aemi, AemiJSON, project-hooks, arcleak, dolly and deadwood? | "Mirror into g-cqd (Recommended)"; the option's text: "Create g-cqd mirrors where missing (aemi, project-hooks and the analyzers), fix there, and point Atelier at the aemi mirror by pinned revision, the way AemiJSON already works." | PROC-12 |
| D6 | 09-23 12:34 | Patch the hook script the global git template installs, and the copies in existing clones, so a clone cannot get its own project-hooks binary run? | "Patch now (Recommended)" | QUAL-09 |
| D7 | 09-23 12:34 | How should the app ask before starting sourcekit-lsp in an untrusted repository? | "Prompt on first hover (Recommended)"; the option's text: "The first hover in an unknown repository asks once whether to trust it. Doc comments and SDK docs keep working meanwhile. A Settings list lets you review and revoke." | QUAL-07 |
| D8 | 09-23 12:37 | The GitHub Copilot for Xcode extension had leaked 1,809 zombie processes and made builds fail; end it? | "End it now (Recommended)" | PROC-10 |
| D9 | 09-23 14:47 | Start Wave 2, and when do the requested features no wave holds go in? | "Wave 2 now, then features (Recommended)": Wave 2 as parallel agents grouped by files, DIFF-02 with track 2B; then a feature wave before Wave 3: TAB-07 (⌃Tab and ⌃⇧Tab between file tabs, ⌘⇧] and ⌘⇧[ keep switching windows), card-list diagnostics, the hover panel and its title row, DIFF-01, DIFF-03, DIFF-04 | PROC-11, TAB-07, DIAG-03, DUI-03, HOVER-14, HOVER-08, HOVER-05, DIFF-01 to DIFF-04 |
| D10 | 09-23 14:47 | Build the custom text renderer? | "Seam, then CoreText M1 (Recommended)": finish M0 and the switchable backend seam, then M1 time-boxed by its exit criteria, with TextKit as the fallback. The Dynamic Type reading (⌘+, ⌘− and ⌘0 on the Mac; Dynamic Type where the platform scales text) drew no objection | REND-02, REND-03 |
| D11 | 09-23 14:47 | Which settings can differ per project? | "Comparison and tools (Recommended)": per project, diff options, layout, wrapping, minimap, isolation, context, granularity, hover, diagnostics, analyzed sides, auto-refresh, tool and server locations; app-wide, appearance, theme matching and badge colors; Settings gets the scope selector and an editable project list | SET-03 |
| D12 | 09-23 14:47 | Which sides do the analyzers run on? | "Both, left, right, none (Recommended)": four modes, right side by default; a ref side is exported into a private temporary folder, analyzed with its own configuration, and its findings show on its own rows; an untrusted repository has only its working tree analyzed | DIAG-08 |
| D13 | 09-23 14:50 | What does the viewer show while Swap, another ref or another folder loads? | "Old cards, marked updating (Recommended)": the previous cards stay, visibly marked as updating, until the new comparison lands; never "Comparing…" | GIT-03 |
| D14 | 09-23 14:50 | How should a renamed file read? | Typed: "new and old on cards, not in the sidebar list". The `new ← old` label goes on card headers only; the sidebar list, tabs and status bar keep the new name | CARD-09 |
| D15 | 09-23 14:50 | Once fixed, how do arcleak, dolly and deadwood reach the app? | "Bundle into the app only": built into the bundle's helpers from the fixed `g-cqd` revisions; nothing installed on the user's `PATH` | DIAG-01, TOOL-03 |
| D16 | 09-23 14:50 | Once its fixes pass, may the fixed project-hooks be installed? | "Install, keep a backup (Recommended)": the old binary kept as `~/.local/bin/project-hooks.bak`, the hooks regenerated in every clone after a backup, and the trust opt-in shown to the user before the hooks are regenerated | QUAL-09, PROC-12 |
| D17 | 09-23 14:53 | The backdrop under the tabs in the single-file view | "AppKit route first (Recommended)": AemiSDR only if that fails, and no dependency without asking | TAB-09 |
| D18 | 09-23 14:53 | An Xcode diff palette? | "Yes, later, off by default (Recommended)": an "Xcode" choice for the diff colors, independent of the badge scheme, built with DIFF-03 | DIFF-05, SET-07 |
| D19 | 09-23 14:53 | Commit titles from now on | "<Scope>: <sentence>, short (Recommended)": under about 72 characters, the detail in the body | PROC-09 |
| D20 | 09-23 14:53 | Should deadwood keep refusing to follow links out of the repository? | "Keep containment (Recommended)": never follow links out of the repository, and make baselines stable under that rule | DIAG-01 |
| D21 | 09-24 05:25 | Codex is out of credits until 09-30 20:43, with four jobs stopped mid-work. How should the remaining work continue? | "Claude agents (Recommended)": finish the interrupted jobs and the rest of the queue with Claude subagents, from the saved `wip/*` branches, reviewed and tested the same way before anything merges | PROC-11 |
| D22 | 09-24 05:25 | Which git identity should Atelier's future commits use? | "Keep the global one": change nothing; history stays as it is | PROC-09 |
| D23 | 09-24 13:06 | LANG-01: a language-detection toggle, a status-bar language menu, or both? | "lang-01, we can plan for all the things later": both are planned later | LANG-01 |
| D24 | 09-24 | Was line wrapping on when rows misaligned or scrolling stopped short (DIFF-06, CARD-17)? | "no": the fix for unwrapped panes covers what the user saw; queue item 20 closes | DIFF-06, CARD-17 |
| D25 | 09-24 | Should the card list itself stop bouncing at its ends, like its code panes? | "no": the list keeps its bounce | CARD-18 |
| D26 | 09-24 | Keep Fable 5.1 for the security-auditor and orchestrator agents (2.5 times Opus 5.5's price)? | "keep" | PROC (agent roster) |
| D27 | 09-24 | The order of the remaining work | "reassess and reorder, maybe use work to prioritize even": the backlog is loaded into the shared work queue and ordered by value per effort, correctness first | PROC-13 |
| D28 | 09-24 | A card for a file without a changed line (DIFF-07): a "Renamed without changes" note, the whole content, or the header alone? | "header only in the file list": the card keeps its header alone; only the single-file view shows such a file whole | DIFF-07 |
| D29 | 09-25 | GIT-06: where does a file changed by several commits appear? | "Under each commit (Recommended)": a section means what that commit did | GIT-06 |
| D30 | 09-25 | GIT-06: which sidebar gets the grouping? | "Merged sidebar, flat style (Recommended)" | GIT-06 |
| D31 | 09-25 | GIT-06: what does selecting a commit's section show? | "Its files' net diff (Recommended)": a context menu adds Compare This Commit | GIT-06 |
| D32 | 09-25 | GIT-06: diverged histories? | "Offer to compare from the merge base (Recommended)": the list stays ungrouped and says why | GIT-06 |
| D33 | 09-25 | PERF-11: for Swift, does swift-syntax replace the GLR Swift grammar? | Typed: "merged but glr as background and not prioritized": swift-syntax is the Swift structural tier; the GLR Swift grammar still runs, in the background at low priority, and its layer merges in when it lands | PERF-11 |
| D34 | 09-25 | PERF-11: how is grammar color turned on per language? | "On once a language qualifies (Recommended)": on by default once its corpus, gate and speed checks pass; a setting per language turns it off | PERF-11 |
| D35 | 09-25 | PERF-11: how are sourcekit-lsp semantic tokens offered? | "On by default where possible": used automatically for every working-tree side and KittyCode file once the language server is trusted | PERF-11 |
| D36 | 09-25 | Fix KittyCode dropping grammar color on refresh ahead of the tier work? | "Yes, keep grammar color now (Recommended)" | PERF-11 |
| D37 | 09-25 | What comes first in the plan? | Typed: "i'd prefer that you cancel the work you started on kitty code, what has priority to me is core shared code or gitdiffviewer relevant improvement, reschedule the roadmap accordingly please": core shared code and GitDiffViewer improvements first; work that only improves KittyCode is deferred | PROC |
| D38 | 09-25 | What comes first now? | Typed: "the gitdiffviewer ui and ux topics related to the gutter, and the rendering and hover work are right now what i would prioritize, i was not expecting you to do the commit grouping stuff now": GitDiffViewer's gutter UI and UX (DIFF-02 to DIFF-04, DIFF-06), the rendering work (CARD-12, PERF-09, PERF-11, REND) and hover (HOVER-16) come first; commit grouping gets only its fix | PROC |
| D39 | 09-25 | GIT-06: what does a file under a commit show? | Typed: "when using grouping the diff happens against the previous commit state so we should always have the net difference between 2 commits not a weird sum": that commit's change, from its first parent to the commit; replaces D31 | GIT-06 |
| D40 | 09-25 | How do agents build, hand back and use worktrees? | Typed (R124 to R126): build once per completed step in one configuration, with no combination matrix; the agent's final run after rebasing onto main is the verification and the coordinator does not rebuild it; few long-lived worktrees. Written into the skills (`3ac96f9`, `515e4e0`) and `AGENTS.md` (`eeba05e`) | PROC |

## Answered questions (09-23 09:37)

- **Q1 (TAB-01).** Answer: "native behaviour for the in-app file tabs?", the second of the two options offered,
  echoed with a question mark. TAB-01 (native window tabs) stays as built; the ask is recorded as TAB-07, whose
  criteria (drag, shortcuts, middle click, overflow, accessibility) are the book's reading, not the user's list.
- **Q2 (SET-03).** Answer: "yes, but i think we should keep a list shown, editable in the settings of the app to
  see and manage settings for different project and add a selector to the settings window for which
  configuration we're changing, the default one or the project ones". Read as "every setting becomes
  overridable"; SET-03 gains a scope selector and a managed project list. The question offered two options, so
  "yes" is ambiguous: OQ5 asks which settings.
- **Q3 (HOVER-08).** Answer: "i was more talking about liquid glass, but providing both options could be
  interesting". HOVER-08 now asks for Liquid Glass, with the popover material as an option.
- **Q4 (CARD-09, SET-07).** Answer: "added green, modified blue, deleted red, renamed is unknown i didn't see xcode
  with it for quite some time so i don't remember". Renamed stays blue until someone checks Xcode. Settled at 12:05
  and 12:06: blue, lettered R (change of mind 7).
- **Q5 (DIAG-08).** Answer: "we should be able to have either both sides, one side or none, ran on the
  corresponding files". DIAG-08 now asks for four modes; OQ6 confirms the reading and how a ref side is analyzed.

## Requirements

### PROC: Delivery and process

#### PROC-01 · One local source of truth: the full Atelier monorepo
- **Statement:** The machine holds one working copy of GitDiffViewer: the full Atelier monorepo cloned from
  GitHub. Older standalone copies are removed.
- **Source:** 09-21 13:47, "bring in https://github.com/g-cqd/Atelier's version of it please"; 13:47, "clean
  the old ones"; 13:57, "why didnt you clone the whole atelier project, i was expecting that from you"; 14:05,
  "kill and unstinall the old ones please"; 14:06, "i'd like that you clone atelier and not just gitdiffviewer".
- **Rationale:** The app depends on `Packages/AtelierCore` through a monorepo-relative path, so only a full
  clone builds without edits. A second copy makes it unclear which build runs.
- **Acceptance criteria:**
  1. `~/Developer/Atelier` is a git clone with full history, both apps and `Packages/AtelierCore`.
  2. No other GitDiffViewer working copy or vendored AtelierCore exists under `~/Developer`.
  3. The app builds from `Apps/GitDiffViewer` with an unmodified `Package.swift`.
- **Priority:** Must. **Related:** PROC-02, PROC-04.

#### PROC-02 · The local toolchain matches the packages
- **Statement:** The toolchain that builds and tests the packages matches their declared tools version.
- **Source:** 09-21 13:48, "please update the local toolchain to match".
- **Rationale:** The manifests declare `swift-tools-version: 6.4`; the installed Xcode shipped Swift 6.3.3.
- **Acceptance criteria:**
  1. `swift --version`, run in the repository, reports 6.4.
  2. The repository pins the version (`.swift-version`).
- **Priority:** Must. **Related:** PROC-01, QUAL-06.

#### PROC-03 · Each batch ends with install, local re-sign and relaunch
- **Statement:** After each coherent batch, the release bundle is rebuilt, running instances are stopped,
  `~/Applications/GitDiffViewer.app` is replaced and re-signed with the local development identity, and the app
  reopens on the repositories that were open.
- **Source:** 09-21 13:55, "can you install the new gitdiffviewer, kill the previous ones and replace and reopen
  on the same repos/folders (re-sign locally)"; 16:39, "at the end please install re-sign the app locally and
  open it on the 2 currently open repo"; 09-23 10:11, "please reinstall and re-sign the current version of the
  release app and open it on [a work repository] (~/Developer)".
- **Rationale:** The user judges each change in the installed app, on real repositories.
- **Acceptance criteria:**
  1. The installed bundle contains the latest commit on `main`.
  2. `codesign --verify --deep --strict` passes and the signature carries the local team.
  3. The app runs on the same repositories as before the install.
- **Priority:** Must. **Related:** PROC-05, PERF-07.

#### PROC-04 · Work from the g-cqd mirror
- **Statement:** The repository, and the owned dependencies the build needs, are mirrored under the
  `g-cqd` account, and work is pushed there.
- **Source:** 09-21 16:12, "mirror things in the g-cqd scope please, and let's work things through from
  this scope".
- **Rationale:** The user sanctioned the mirror as the working scope.
- **Acceptance criteria:**
  1. `origin` points at `g-cqd/Atelier` and `upstream` at `g-cqd/Atelier`.
  2. After each push, `origin/main` equals local `main`.
  3. Dependencies the build needs (AemiJSON) resolve from the mirror.
- **Priority:** Must. **Related:** PROC-05, JSON-02.

#### PROC-05 · Commit straight to main
- **Statement:** Work lands as commits on `main`, not on feature branches.
- **Source:** 09-21 16:21, "i'd rrather make it straight into main, since it'S a mirror the bisect with the
  original upstream one would be easy to do".
- **Rationale:** The mirror shares history with upstream up to `7853f42`, so a bisect across the divergence
  stays simple.
- **Acceptance criteria:**
  1. Every change since `7853f42` is on `main`.
  2. Branches used for parallel work are replayed onto `main` and deleted.
  3. Each commit builds and passes the hooks, so a bisect stays usable (derived).
- **Priority:** Must. **Related:** QUAL-03, QUAL-06.

#### PROC-06 · Keep a roadmap of the insights and implement it
- **Statement:** Insights gathered during the work go into a roadmap in the repository, and its items get
  implemented or explicitly deferred.
- **Source:** 09-21 15:52, "you can definitely add all those insights to the roadmap and go over their
  implementation"; 09-22 14:13, "please go ahead with the implementation" (answering the list of remaining tasks).
- **Rationale:** The roadmap is the one list of promised follow-ups.
- **Acceptance criteria:**
  1. `Apps/GitDiffViewer/docs/roadmap.md` lists every open follow-up.
  2. Each section's status matches the code.
  3. Every item on the list the user approved on 09-22 14:13 is implemented or deferred with a reason.
- **Priority:** Should. **Related:** all areas; `plan.md`.

#### PROC-07 · Plan before implementing
- **Statement:** Non-trivial work starts from a written plan the user can review.
- **Source:** 09-21 14:27, "enter plan mode".
- **Acceptance criteria:** A plan naming the steps and their order exists before implementation starts.
- **Priority:** Should. **Related:** QUAL-01.

#### PROC-08 · Load the relevant skills and instruction files
- **Statement:** Work follows the global standard (`~/.claude/CLAUDE.md`), the repository's `AGENTS.md` and the
  skills that apply.
- **Source:** 09-22 10:04, "load all relevant skills and main claude.md files please"; 09-23 07:59, "load all
  the relevant skills and generals agents.md/claude.md files and knowledge".
- **Acceptance criteria:**
  1. Work sessions load the skills that apply to the task.
  2. The code obeys `AGENTS.md` and the Definition of Done (audited as MOD-03 and QUAL-06).
- **Priority:** Must. **Related:** MOD-03, QUAL-06.

#### PROC-09 · Incremental, atomic, tested work in parallel and sequential tracks
- **Statement:** Work lands in small atomic steps, each fully tested, organised as tracks that run in parallel when
  they can and in sequence when they must.
- **Source:** decision D1, 09-21 14:30, typed in answer to the plan's scope question: "everything, incremental,
  atomic, fully tested, split in both parallel and sequential tracks".
- **Rationale:** The user wanted the whole feature set at once without giving up reviewable, bisectable steps.
- **Acceptance criteria:**
  1. Each commit holds one coherent change together with its tests.
  2. Parallel tracks own disjoint files; a sequential track names the track it waits for.
  3. Each new behavior has a test that fails without the change.
- **Priority:** Must. **Related:** PROC-05, PROC-07, PROC-11, QUAL-06.

#### PROC-10 · The machine stays usable while agents work
- **Statement:** When the machine runs short of disk space or processes, temporary files and scratch projects are
  removed and runaway helpers are ended, with the user's consent.
- **Source:** 09-23 10:50 (mid-turn), "please clean all temporary files and project, we're running out of space";
  decision D8, 09-23 12:37, "End it now (Recommended)", about the GitHub Copilot for Xcode helper that had leaked
  1,809 zombie processes.
- **Acceptance criteria:**
  1. Free disk space is restored; the assistant reported 3.8 GB before and 69 GB after the 10:50 cleanup.
  2. The leaking helper is ended, and builds no longer fail on the per-user process limit.
- **Priority:** Must.

#### PROC-11 · Fix the review's findings in waves, Wave 1 first
- **Statement:** The fixes of `docs/reviews/2026-09-23-fix-plan.md` run wave by wave, starting with Wave 1
  (security, data loss, crashes), as parallel agents that each own a disjoint set of files.
- **Source:** decision D4, 09-23 12:34, "Start Wave 1 now (Recommended)", answering "Should I start Wave 1
  (security, data loss, crashes) now as parallel agents, each on its own set of files, while the card fix finishes?"
- **Acceptance criteria:**
  1. Tracks 1A to 1K each land on `main` with their tests and meet their acceptance criteria in the fix plan.
  2. Each track works in its own worktree and branch, touches only its files, and merges once its checks pass.
  3. Later waves follow in the fix plan's order.
- **Priority:** Must. **Related:** QUAL-05, PROC-09, PROC-12.

#### PROC-12 · External fixes happen in g-cqd mirrors
- **Statement:** Findings in aemi, AemiJSON, project-hooks, arcleak, dolly and deadwood are fixed in private
  `g-cqd` mirrors, and Atelier resolves aemi from its mirror at a pinned revision.
- **Source:** decision D5, 09-23 12:34, "Mirror into g-cqd (Recommended)", whose text reads "Create
  g-cqd mirrors where missing (aemi, project-hooks and the analyzers), fix there, and point Atelier at the aemi
  mirror by pinned revision, the way AemiJSON already works."
- **Rationale:** It extends R19 ("mirror things in the g-cqd scope please") to the dependencies the review
  found defects in.
- **Acceptance criteria:**
  1. `g-cqd` holds private mirrors of aemi, arcleak, dolly, deadwood and project-hooks, next to AemiJSON.
  2. The external findings of the fix plan (§7.1) are fixed in those mirrors.
  3. Atelier's three manifests resolve aemi from the `g-cqd` mirror at a pinned revision, and AemiJSON's own
     aemi dependency switches in the same step, so SwiftPM sees one aemi.
- **Priority:** Must. **Related:** PROC-04, JSON-02, QUAL-09.

#### PROC-13 · Work runs in order, validity before everything
- **Statement:** Tasks, their increments and the work around them run first in, first out. A regression that breaks
  validity is fixed at once, before the work lands; a regression or shortfall that costs only performance does not
  hold the work back, and goes to the end of the work queue.
- **Source:** 09-24, "it would be interesting to work on the tasks and increments in FIFO within them and in the
  surroundings of them, and not fifo, as in for example, an implementation work is done, but then a regression is
  detected, if impact is not validity, but rather performance, the regression topic should be queued in the list of
  things to do".
- **Acceptance criteria:**
  1. The fix plan keeps the work queue in order, each item with its origin and the date it was queued.
  2. Work lands with every validity regression it caused fixed; a performance regression or missed performance
     target found in it becomes a queue item instead of blocking it.
  3. Queue items are taken in order, oldest first.
- **Priority:** Must. **Related:** PROC-09, PROC-11.

### DIAG: Diagnostics tools

#### DIAG-01 · Run the five Swift analyzers on the compared project
- **Statement:** For a Swift project, GitDiffViewer runs SwiftLint, swift-format, arcleak, dolly and deadwood on
  the compared working tree and shows their findings.
- **Source:** 09-21 14:22, "it could be interesting to provide a warning and inline error, we could bundle
  swiftlint, swift format, arcleak, dolly and deadwood into gitdiffviewer viewing of swift based project".
- **Rationale:** The user reviews Swift changes and wants each analyzer's findings next to the diff. The
  bundling part of this request is superseded (TOOL-04).
- **Acceptance criteria:**
  1. Each of the five tools runs when enabled and installed, and its findings reach the UI keyed by
     root-relative path.
  2. A missing tool reports "not found" without failing the others.
  3. No tool runs for a project without Swift files (derived from "swift based project").
- **Priority:** Must. **Related:** DIAG-02 to DIAG-07, TOOL-01 to TOOL-04.

#### DIAG-02 · Diagnostics switch on and off, globally and per tool
- **Statement:** Settings turn diagnostics on or off as a whole and per tool.
- **Source:** 09-21 14:22, "toggleable in settings, toggleable for each tools".
- **Acceptance criteria:**
  1. Settings has a master toggle and one toggle per tool.
  2. Turning the master toggle off cancels runs and clears findings.
  3. A disabled tool never runs.
- **Priority:** Must. **Related:** SET-03.

#### DIAG-03 · Findings show on their lines
- **Statement:** Each finding appears inline on the line it concerns.
- **Source:** 09-21 14:22, "provide a warning and inline error"; "with inline warnings".
- **Acceptance criteria:**
  1. A finding with a column draws a squiggle under its range.
  2. The line carries a severity marker.
  3. Both hold in every view that shows code, including the card list, which is the default view (derived).
- **Priority:** Must. **Related:** DUI-02, DUI-03, HOVER-14.

#### DIAG-04 · A summary in the status bar
- **Statement:** The status bar shows warning and error totals.
- **Source:** 09-21 14:22, "summary of the warnings and errors in the status bar".
- **Acceptance criteria:**
  1. While diagnostics are on, the status bar shows warning and error counts.
  2. The counts update when a run finishes.
  3. A per-tool breakdown is reachable.
- **Priority:** Must.

#### DIAG-05 · A summary in a toolbar component
- **Statement:** A toolbar item shows the same totals.
- **Source:** 09-21 14:22, "and in a toolbar component as well".
- **Acceptance criteria:**
  1. A customizable toolbar item shows the counts.
  2. It appears and updates as soon as a run lands findings, with no other interaction.
- **Priority:** Must. **Related:** DUI-01.

#### DIAG-06 · Findings respect the project's reviewed configuration
- **Statement:** The app reports only what the project's own configured lint runs would report.
- **Source:** 09-21 17:15, "somehow the warnings seems to be over computed and not respecting the reviewed
  project configs"; 17:15, "for the 2 scopes opened right now you can inspect that".
- **Rationale:** A finding the project's own lint run would not report is noise.
- **Acceptance criteria:**
  1. SwiftLint applies the project's `included:` and `excluded:` lists exactly as the project's own run does.
  2. A formatter runs only when the project carries its configuration file.
  3. Displayed findings are limited to the changed files.
  4. On the two work repositories that were open, the counts match the projects' own lint output for the same
     files.
- **Priority:** Must.

#### DIAG-07 · Lockwood's SwiftFormat is supported
- **Statement:** Nick Lockwood's SwiftFormat is a supported tool, separate from Apple's swift-format.
- **Source:** 09-21 17:18, "lockwood swift format should be implemented and handled, we definitely use it a lot".
- **Acceptance criteria:**
  1. It has its own toggle, discovery row and bundle staging.
  2. It runs in lint mode under the project's `.swiftformat`.
  3. Its `(rule)` message prefix becomes the finding's rule ID.
- **Priority:** Must.

#### DIAG-08 · Choose which sides are analyzed
- **Statement:** A setting chooses which sides diagnostics cover: both, the left only, the right only, or none.
- **Source:** 09-22 10:04, "i'd like that we add more features in regard of what we want to be analyzed,
  whether we want both sides to be analyzed or only (the considered "newer" one for example)".
- **Refined:** 09-23 09:37 (Q5), "we should be able to have either both sides, one side or none, ran on the
  corresponding files".
- **Acceptance criteria:**
  1. A setting offers both sides, left only, right only and none; the default is the newer (right) side.
  2. The tools run on each selected side's own files. A side that is a git ref is analyzed from its content,
     materialized outside the working tree.
  3. Each side's findings appear on that side's rows only.
- **Priority:** Should. **Related:** SET-03.

### TOOL: Tool discovery and user-set locations

#### TOOL-01 · Discover installed tools dynamically
- **Statement:** The app finds each tool wherever the user installed it, without configuration.
- **Source:** 09-21 14:25, "we should have dynamic discovery of how the tools are installed".
- **Rationale:** An app launched from Finder does not inherit the shell's `PATH`.
- **Acceptance criteria:**
  1. Discovery finds a tool installed with Homebrew, swiftly, Mint, in `~/.local/bin`, in the active
     toolchain, or on the login shell's `PATH`, whatever the login shell (zsh, bash or fish).
  2. Settings shows where each tool was found and its version.
  3. A Refresh control re-probes after an install.
- **Priority:** Must. **Related:** TOOL-02.

#### TOOL-02 · Set each binary's location in Settings
- **Statement:** Settings let the user point the app at the executable of every tool and language server.
- **Source:** 09-21 14:25, "maybe we should be able to specify the location of some tool"; 15:20, "we
  definitely have to propose a way to locate the binaries in the settings of the application".
- **Acceptance criteria:**
  1. Every binary the app runs, the diagnostics tools and sourcekit-lsp alike, has Locate… and Reset controls,
     usable whatever the state of other settings.
  2. A pinned path wins over discovery.
  3. A pinned path that stops being executable shows an error state instead of falling back silently (derived).
  4. A new pin takes effect without restarting the app (derived).
- **Priority:** Must. **Related:** TOOL-01, TOOL-03, SET-03.

#### TOOL-03 · Bundling tools inside the app is optional
- **Statement:** The app works without bundled helpers; bundling is an extra, optional source.
- **Source:** 09-21 15:20, "we don't necessarily have to bundle things in the app".
- **Acceptance criteria:**
  1. The app works with no bundled helpers.
  2. When the bundle script finds a tool, it stages and signs it under `Contents/Helpers`; a missing tool is
     skipped with a warning.
- **Priority:** Could. **Related:** supersedes TOOL-04.

#### TOOL-04 · Bundle the five analyzers into the app (Superseded)
- **Source:** 09-21 14:22, "we could bundle swiftlint, swift format, arcleak, dolly and deadwood into
  gitdiffviewer"; decision D2, 09-21 14:30, "Bundle + discovery".
- **Superseded by:** TOOL-03, TOOL-01 and TOOL-02 on 09-21 15:20.

### HOVER: Hover documentation

#### HOVER-01 · Hover documentation from sourcekit-lsp and swift-syntax, toggleable
- **Statement:** Resting the pointer on an identifier shows its documentation, from sourcekit-lsp and from a
  swift-syntax index of the sources. A setting turns the feature on and off.
- **Source:** 09-21 14:22, "could you investigate implementation over the sourcekit lsp and swiftsyntax power to
  provide on-hover documentation on the items hovered (this should be a toggleable feature)".
- **Acceptance criteria:**
  1. Resting the pointer on an identifier shows its documentation after a short delay.
  2. sourcekit-lsp answers for on-disk files; the swift-syntax index answers from source alone, git blobs
     included.
  3. A toggle in Settings and in the view options turns hover on and off.
- **Priority:** Must. **Related:** HOVER-02 to HOVER-16.

#### HOVER-02 · Hover works in every pane, including the card list
- **Statement:** Hover works wherever code is shown.
- **Source:** 09-22 10:21, "also i was not able to make the documentation on hover work"; 10:58, "i still have
  no hover"; 13:03, "the doc hovering is not working correctly, no information displayed".
- **Acceptance criteria:**
  1. A panel appears in the card list (the default view), in the single-file view, and in every layout
     (inline, side by side, stacked).
  2. Both the old and the new side answer.
- **Priority:** Must.

#### HOVER-03 · The project's own doc comments appear
- **Statement:** A symbol's `///` documentation from the project appears in its hover.
- **Source:** 09-22 13:35, "the doc comment are not showing in the doc popover"; 14:15, "when hovering anything
  else only the signature is shown and no other documentation information are shown"; 15:40, "not showing the
  doc content"; images 05, 07 and 09.
- **Acceptance criteria:**
  1. Hovering a symbol declared with a `///` comment shows the comment's text under the declaration, whether
     or not the language server answers.
  2. This holds for a documented computed property declared inside an extension (image 09).
  3. It holds while a large card list is still streaming in.
  4. A symbol with no documentation says "No documentation" instead of showing blank space. Superseded on 09-24
     by HOVER-20's criterion 6: such a symbol shows its declaration alone.
- **Priority:** Must. **Related:** HOVER-07, PERF-08.

#### HOVER-04 · System APIs are documented from on-device documentation
- **Statement:** Apple SDK symbols get their declaration and documentation from the toolchain and Xcode on the
  machine.
- **Source:** 09-22 11:21, "somehow it does not cover the system apis and framework provided by apple"; 11:24,
  "i truly believe we should be able to utilize the on device xcode documentation, preferably not apple-docs";
  13:35, "i still have no native documentation for system api and frameworks"; image 04.
- **Acceptance criteria:**
  1. Hovering an Apple SDK symbol (for example `Int`, `StateObject`, `URLSession`) shows its declaration and,
     when the SDK carries it, its prose, with no network access.
  2. The source is the on-device toolchain or Xcode, not the apple-docs corpus.
  3. Symbols from iOS-only frameworks such as UIKit resolve, since the work repositories are iOS projects
     (derived).
  4. A transient failure, such as a cold server timing out, does not hide a symbol's documentation for the rest
     of the session (derived).
- **Priority:** Must. **Related:** supersedes HOVER-17.

#### HOVER-05 · A dense, sectioned panel in Xcode's Quick Help style
- **Statement:** A custom AppKit panel replaces NSPopover and presents documentation the way Xcode's Quick
  Help does.
- **Source:** 09-22 11:21, "i'd like that you investigate how to leverage cocoa, ns, appkit, to create a custom
  popover that can handle more than what the current popover does and provides a more dense compact and
  beautiful ui for popover"; 11:30, "[Image #2] this is how it looks for xcode".
- **Acceptance criteria (from image 02):**
  1. The panel is a custom AppKit window, not an NSPopover.
  2. In order: the symbol's name as a bold title, the abstract, the declaration in a rounded box with a light
     stroke, then titled sections (such as Discussion, Parameters, Returns) separated by hairlines.
  3. Inline code uses a monospaced font.
  4. Long content scrolls inside the panel.
- **Priority:** Must. **Related:** HOVER-06 to HOVER-13.

#### HOVER-06 · Declarations are syntax-colored and legible in any theme
- **Statement:** The declaration uses the pane's syntax colors on a background those colors were designed for.
- **Source:** 09-22 11:21, "without color syntaxing"; image 07.
- **Acceptance criteria:**
  1. The declaration uses the token colors of the pane the hover came from.
  2. It sits on the theme's own background, so it stays legible whatever the window appearance.
  3. Both hold on every path, including a hovered row that carries a diagnostic.
- **Priority:** Must.

#### HOVER-07 · The panel fits its content
- **Statement:** The panel is exactly as tall as what it shows.
- **Source:** 09-22 11:30, "it does not even adapt to the size of the content"; 14:19, "as you can see a lot of
  negative space"; 15:40, "sizing and content of hover is still not dynamic"; 16:19, "there is still a lot of
  wasted space"; images 03, 04, 05, 07 and 09.
- **Acceptance criteria:**
  1. The panel height equals its laid-out content plus its insets, with no fixed minimum.
  2. A declaration-only answer yields a panel one declaration tall.
  3. Content taller than the cap scrolls inside the body while the other sections stay visible.
- **Priority:** Must.

#### HOVER-08 · Glass material clipped by rounded corners
- **Statement:** The panel is made of glass, and its rounded corners clip that glass.
- **Source:** 09-22 13:35, "the hover popover should be glassmade and rounded corner should also clip the
  background of the popover, if the popover is glass made then that is already good".
- **Acceptance criteria:**
  1. The panel background is Liquid Glass (`NSGlassEffectView`) by default (Q3, 09-23 09:37: "i was more talking
     about liquid glass").
  2. A setting offers the popover material as an alternative ("providing both options could be interesting").
  3. No square corner of the material shows past the rounded shape.
- **Priority:** Should.

#### HOVER-09 · The panel follows its line while scrolling
- **Statement:** The panel moves with the hovered line and closes when the line leaves the view.
- **Source:** 09-22 13:35, "it should scroll and disappear with the line it follows when scrolled through and
  out the viewport".
- **Acceptance criteria:**
  1. Scrolling moves the panel with the hovered identifier.
  2. The panel closes when the identifier leaves the visible area.
- **Priority:** Should.

#### HOVER-10 · The panel does not flash
- **Statement:** A panel that opens stays open until there is a reason to close it.
- **Source:** 09-22 14:15, "when hovering view the hover appears and disappears instantly".
- **Acceptance criteria:** A panel stays open until the pointer leaves both the identifier and the panel, a scroll
  moves the identifier out of view, or another identifier is hovered.
- **Priority:** Must.

#### HOVER-11 · No duplicated information
- **Statement:** Each declaration appears once.
- **Source:** 09-22 14:27, "[Image #6] some have duplicated informations somehow".
- **Acceptance criteria (from image 06):**
  1. A declaration appears once, even when its file is indexed from the old blob, the working copy and the
     corpus.
  2. Hovering the new side never lists the old side's version of the same declaration.
  3. Distinct declarations with the same name in different files remain listed.
- **Priority:** Must.

#### HOVER-12 · Typography and spacing
- **Statement:** The panel uses the system font and a consistent spacing scale, and strokes the declaration.
- **Source:** 09-22 16:19, "the font is sometimes helvetica instead of the system font for some descriptions";
  "inter elements spacing is not mastered and some things are too stuck together"; "a light stroke could be
  around the signature block".
- **Acceptance criteria:**
  1. All prose uses the system font, with bold, italic and inline code preserved.
  2. Spacing between sections follows one scale; a section header sits close to its content.
  3. A light stroke surrounds the declaration block.
- **Priority:** Should.

#### HOVER-13 · No source label in the panel
- **Statement:** The panel does not name the tier that answered.
- **Source:** 09-22 16:20, "the source of the documentation is not really necessary in this hover popup".
- **Acceptance criteria:** No text such as "sourcekit-lsp", "doc comment" or "Apple SDK" appears in the panel.
- **Priority:** Should. **Related:** supersedes HOVER-18.

#### HOVER-14 · Hover joins documentation and the diagnostic under the pointer
- **Statement:** Hovering an underlined problem shows that finding with the symbol's documentation, and an
  explicit path to either exists.
- **Source:** 09-22 10:58, "the hovering, should be able to handle documentation and warnings for a specific
  underline problem for example, maybe with some sort of customized context menu or i don't know".
- **Acceptance criteria:**
  1. Hovering an underlined range shows that finding's message and tool with the documentation, in one panel.
  2. This works in the card list and in the single-file view.
  3. A context menu offers Show Documentation and Show Issue (Could).
- **Priority:** Should. **Related:** DIAG-03, DUI-03.

#### HOVER-15 · A design for hover in any language
- **Statement:** A design explains how hover can work for other languages and language servers.
- **Source:** 09-21 15:13, "you should maybe investigate in parallel a design in order to provide hovering for
  any language depending on how documentations could be loaded, or any lsp, like for js, kotlin, c or something
  likethat, this needs investigation".
- **Acceptance criteria:** A design document covers the language servers per language, their discovery, a
  fallback without a server, the tier order and phases.
- **Priority:** Should. **Related:** HOVER-16.

#### HOVER-16 · Hover for other languages (Derived)
- **Statement:** Hover answers for languages other than Swift, following the design.
- **Source:** 09-22 14:13, "please go ahead with the implementation", answering the list of remaining tasks,
  which named multi-language hover as item 6.
- **Acceptance criteria:**
  1. Hovering a TypeScript, JavaScript or Go identifier answers from its language server when it is installed.
  2. Without a server, a doc-comment tier answers from the source's own comments.
  3. Server locations are settable like sourcekit-lsp's (TOOL-02).
- **Priority:** Should. **Related:** HOVER-15, MOD-01.

#### HOVER-17 · The apple-docs corpus as the system-API tier (Superseded)
- **Source:** the assistant's proposal, 09-22 11:21 (roadmap: "apple-docs corpus as the system-API tier").
- **Superseded by:** HOVER-04, 09-22 11:24, "preferably not apple-docs".

#### HOVER-18 · A footer naming the tier that answered (Superseded)
- **Source:** the panel design (commit `27bc8c3`, "a footer naming which tier answered"; commit `b30579b`, "the
  prose winner names itself in the footer").
- **Superseded by:** HOVER-13, 09-22 16:20.

#### HOVER-19 · Only Swift is parsed as Swift, and no file crashes the parse
- **Statement:** Hover reads Swift files only. Any other file gets no hover and is never handed to swift-syntax or
  sourcekit-lsp, and no file, however deeply it nests, crashes the app.
- **Source:** 09-24 12:27 (mid-turn), a pasted crash report: a stack overflow in swift-syntax's parser under the
  doc-comment hover tier; 12:30 (mid-turn), "the swift parser and swift syntax should fail fast and only parse swift
  files, [...] here it's really when i'm opening a python file".
- **Acceptance criteria:**
  1. Hovering in a file whose extension is not Swift's runs no tier: nothing is parsed, no language server is
     asked, and no panel appears.
  2. The doc-comment index parses Swift files only.
  3. Every swift-syntax parse and tree walk runs on a stack that holds it, so a file whose brackets never close
     cannot overflow a worker thread.
  4. When HOVER-16 lands, each tier answers only for the languages it reads.
- **Priority:** Must. **Related:** HOVER-01, HOVER-16, LANG-01.

#### HOVER-20 · The hover panel reads like Xcode's Quick Help
- **Statement:** The documentation panel keeps the structure of what it shows, and lays a symbol out as Xcode's Quick
  Help does.
- **Source:** 09-24 14:57, six screenshots of a hover over `Bool` (images 28 to 33), "the oldest one is ours, the
  others are xcode ones, we should improve". Ours runs code examples, paragraphs and headings together into one block
  of prose; Xcode's shows the name as a title, the abstract, the declaration in a box, an Overview heading, code
  blocks in boxes with syntax colour, section headings, a Relationships section listing what the type conforms to,
  and an "Open in Developer Documentation" link, in a panel that scrolls.
- **Acceptance criteria:**
  1. Code blocks keep their lines and indentation, in a box, with Swift syntax colour.
  2. Paragraphs, headings, lists and rules keep their structure and spacing; nothing runs into the next block.
  3. The panel opens with the symbol's name as a title, its abstract, then its declaration in a box, then the
     discussion under an Overview heading, and scrolls when taller than the space it has.
  4. A Relationships section lists the protocols the symbol conforms to, when a tier can tell.
  5. A system symbol offers a link that opens its page in Apple's developer documentation.
  6. A symbol with nothing but its declaration shows the declaration alone: no title, and no name repeated beneath
     it (09-24, "it makes no sense to show the name of the variable below the variable signature when the only
     information about the variable is the variable itself, let's just show the signature"). This replaces
     HOVER-03's criterion 4 for the panel.
  7. The panel stays open while the pointer moves from the symbol onto it and rests over it, so it can be scrolled:
     an invisible bridge spans the gap between the symbol and the panel, and leaving starts a short grace delay
     before the panel closes, which re-entering cancels (09-24, "i'd like the popover of the documentation to be
     able to stay visible when mousing hover it (means we need an invisible bridge or/and a delay before
     dismounting the popover), so that it can be scrollable").
- **Priority:** Must for 1 to 3, 6 and 7, which fix what the panel shows and let it be read; Should for 4 and 5. **Related:** HOVER-01,
  HOVER-03, HOVER-13.

### DUI: Diagnostics UI

#### DUI-01 · A toolbar list of every finding
- **Statement:** A toolbar item opens a scrollable list of all findings.
- **Source:** 09-22 10:58, "i'd like to be able to have a toolbar element that opens a scrollable list of all
  warnings and errors provided by the analyzers".
- **Acceptance criteria:**
  1. The item appears once findings exist, and opens a scrollable list of every finding, grouped by file.
  2. Choosing a finding shows its file (Must) and scrolls to its line (Should).
- **Priority:** Must. **Related:** DIAG-05.

#### DUI-02 · Markers do not change the gutter layout
- **Statement:** A line's finding marker blends with the gutter and never moves anything.
- **Source:** 09-22 10:58, "the inline badge should not change the layout of the gutter and should blend with
  the gutter and the line".
- **Acceptance criteria:**
  1. The gutter width is the same with and without findings.
  2. The marker blends with the gutter and the line, for example as a tint on the line number.
- **Priority:** Must.

#### DUI-03 · A finding opens from its line
- **Statement:** The user opens a finding from the line it is on.
- **Source:** 09-22 10:58, "being able to be either be open from the line itself, in the gutter, as a decoration
  of the line number, or overlaying the trailing edge of the text container and its line".
- **Acceptance criteria:**
  1. Clicking the line-number decoration opens the finding.
  2. An overlay at the trailing edge of the line opens it too (either option satisfies the request).
  3. Both work in the card list and in the single-file view.
- **Priority:** Should.

#### DUI-04 · The finding popover anchors on its line
- **Statement:** A finding's popover points at the clicked line.
- **Source:** 09-22 11:00, "clicking on a warning on a line right now opens a popover at the top of the text
  container, not on the line, which is definitely bad".
- **Acceptance criteria:** The popover's arrow points at the clicked line, wherever that line is in the pane.
- **Priority:** Must.

### SET: Settings

#### SET-01 · Settings designed from UI and UX research
- **Statement:** The Settings design follows what HCI research says about cognitive load, complexity and layout.
- **Source:** 09-22 10:04, "research what design principles should be applied to settings screen and app
  configuration, what does ui and ux scientific research says about it, about cognitive overload and
  complexity, layouts"; "i'd like that we improve over those concepts and scopes in the app".
- **Acceptance criteria:**
  1. A research document states the principles with their sources and audits the current Settings.
  2. The Settings window applies the redesign: tabs grouped by user question, progressive disclosure, captions,
     one label per setting on every surface, and per-tab Restore Defaults with a deviation count.
- **Priority:** Must.

#### SET-02 · Settings follow platform conventions
- **Statement:** Settings behave the way macOS settings windows do.
- **Source:** 09-22 10:12, "also you could open the macos settings or research how macos and ios natively handle
  settings and we should and could try to align with that".
- **Acceptance criteria:**
  1. The Settings window has a fixed size and a toolbar pane switcher.
  2. It restores the last viewed pane.
  3. App-wide settings live in the Settings window; view settings live in the window they affect.
- **Priority:** Should.

#### SET-03 · Per-project settings
- **Statement:** Each repository can carry its own settings, remembered by a hash of the repository.
- **Source:** 09-22 10:04, "it might be interesting to have save a list of the project repository settings maybe
  through a hash-based memory of them and be able to tune all settings for a specific project".
- **Acceptance criteria:**
  1. Each repository gets an identity from a hash of its root.
  2. From the comparison window, the user overrides settings for that project; overrides persist and apply the
     next time the project opens.
  3. Every setting can be overridden per project (Q2, 09-23 09:37).
  4. The Settings window has a scope selector that chooses which configuration is being edited: the default
     one, or a project's.
  5. Settings lists every project that has overrides; each entry can be inspected, edited through the selector,
     and cleared.
  6. A project never gets an override the user did not make.
- **Priority:** Should. **Related:** DIAG-02, DIAG-08, TOOL-02.

#### SET-04 · A light and dark appearance setting
- **Statement:** The user pins the app's appearance to light or dark, or follows the system.
- **Source:** 09-22 15:39, "it would be nice to have a dark mode and light mode color scheme settings so that we
  it would match and we could adapt the view".
- **Acceptance criteria:** A System, Light and Dark choice applies to every window at once.
- **Priority:** Should.

#### SET-05 · Settings apply live, without a new comparison
- **Statement:** A settings change reaches every open window immediately and redoes only the work it needs.
- **Source:** 09-22 15:44, "also changes in settings window are not directly reflected in the rendering, for
  example the syntax highlighting does not change automatically, it should not trigger a new comparison but just
  change the colors/rendering".
- **Acceptance criteria:**
  1. A change made in the Settings window reaches every open window at once, for every setting those windows use.
  2. A theme change recolors without re-diffing, and keeps the scroll position and revealed lines.
  3. Only settings that change the diff re-diff.
- **Priority:** Must.

#### SET-06 · Optional appearance from the theme
- **Statement:** An option derives the window's light or dark appearance from the selected theme.
- **Source:** 09-22 16:37, "it would be interesting to automatically adopt a light or dark theme for the
  app/window if a selected color scheme is light or dark, this could be a toggleable option to ensure people have
  exactly what they want".
- **Acceptance criteria:**
  1. A toggle makes the window light or dark from the selected theme's background.
  2. An explicit Light or Dark choice wins over it.
  3. It is off by default.
- **Priority:** Could.

#### SET-07 · A badge color scheme: classic or Xcode
- **Statement:** The user chooses red and green badge colors or Xcode's.
- **Source:** 09-22 16:37, "the colors for the diff badges are different in xcode, we could have an appearance
  settings that either use the red/green kind or the xcode kind".
- **Refined:** 09-23 11:37 (mid-turn), "btw the file headers in the list don'T match the badge color scheme tint".
- **Acceptance criteria:**
  1. A setting chooses Classic or Xcode badge colors.
  2. It applies to every badge: explorer rows, tabs, card headers and the status bar.
  3. It applies to open windows at once (SET-05).
  4. A card header's tint follows the same scheme as its badge.
- **Priority:** Should. **Related:** CARD-09.

#### SET-08 · Research accent colors from the theme
- **Statement:** Adapting accent colors to the theme is researched before it is built.
- **Source:** 09-22 16:37, "a further refinement could be that we adapt the accents colors throughout the app to
  the color scheme itself, but this needs further research".
- **Acceptance criteria:** A research note settles the color extraction, the contrast guarantees and the scope
  (controls, selection, badges).
- **Priority:** Could.

#### SET-09 · Scrolling settings
- **Statement:** How code panes scroll is a setting: whether they bounce at their edges, whether they scroll past the
  last line, and whether opening a file scrolls to its first change.
- **Source:** 09-24, "the bouncing of scroll (and the fact we disabled it) should be a setting", with R116's "this
  should be a toggleable behaviour" (DIFF-08) and R117's overscroll report (CARD-19).
- **Acceptance criteria:**
  1. "Bounce at the edges", off by default as CARD-18 left it, makes the single-file view and the cards' code panes
     rubber-band at their edges; the card list keeps its own bounce either way (D25).
  2. "Scroll past the last line", off by default (CARD-19), lets the last line scroll up to the top of the pane.
  3. "Scroll to the first change when a file opens", on by default (DIFF-08).
  4. The three sit together in the settings, apply at once to every open pane, and follow the per-project override
     rules of the other view settings.
- **Priority:** Should. **Related:** CARD-18, CARD-19, DIFF-08.

### CARD: The card list and file badges

#### CARD-01 · Sticky file headers
- **Statement:** A file's title bar stays pinned while any part of its card is on screen, so the file can be
  folded from there.
- **Source:** 09-22 11:21, "in the file list, i'd love that when scrolling down the title-collapsible-expansible
  bar of each file stay fixed/sticky in the view so that we can still collapse it even if the file is half
  scrolled in the view"; 14:39, "the second part of that might have been overlooked".
- **Acceptance criteria:**
  1. While any part of a card is visible, its header stays pinned at the top of the list.
  2. Clicking the pinned header folds the file.
- **Priority:** Must.

#### CARD-02 · A pinned header keeps the card's look
- **Statement:** A pinned header keeps the card's rounding, shadow and spacing.
- **Source:** 09-22 11:21, "we should keep the rounding clipping, shadow and negative space to the toolbar and
  surroundings i think"; 15:39, "it does not have any negative space with the window toolbar when sticking".
- **Acceptance criteria:**
  1. A pinned header rests below the toolbar with the same gap the list keeps at its edges.
  2. It keeps rounded corners and one soft shadow.
- **Priority:** Must.

#### CARD-03 · Content behind a pinned header is clipped
- **Statement:** Scrolled content never shows behind or around a pinned header.
- **Source:** 09-22 15:39, "the scrolling content of the file is not clipped with the rounded corners behind the
  section sticky top bar"; 16:15, "clipping does not work … not clipping to the bounds of the top file header and
  bottom of the file content container".
- **Acceptance criteria:**
  1. No content of the scrolled body is visible behind the pinned header, around its corners or above it.
  2. The body's visible part ends at the header's bottom edge.
- **Priority:** Must.

#### CARD-04 · Header and body read as one card at rest
- **Statement:** An unpinned header and its body look like one card.
- **Source:** 09-22 15:39, "the section header is being separated from the file content"; 16:15, "file content
  is still 16pt apart from the file header"; 16:37, "the stroke that separates the file header from the content is
  now darker"; 16:40, "when the header is not sticky, it seems it is not laid out with the file content and does
  not get any shadow".
- **Acceptance criteria:**
  1. Header and body touch, with no gap.
  2. They share the same width and border, and cast one shadow.
  3. One light hairline separates them.
- **Priority:** Must.

#### CARD-05 · Nothing clips card shadows or the scroll bar
- **Statement:** The list's top edge clips neither card shadows nor the scroll bar.
- **Source:** 09-22 16:37, "the latest change on the sticky file headers creates a white strip at the top that
  clips everything including the shadow of the cards themselves and the scrollbars as well".
- **Acceptance criteria:** No strip or overlay covers the top of the list; card shadows and the scroll bar render
  in full.
- **Priority:** Must.

#### CARD-06 · No square glass layer or extra shadow when pinned
- **Statement:** Pinning changes nothing about a header's shape and shadow.
- **Source:** 09-22 16:37, "the sticky file headers seems to get a not rounded rectangle glass layer beneath them
  when they become sticky as well as additional shadow"; 16:15, "the top file has now more shadow".
- **Acceptance criteria:**
  1. A pinned header shows no square material outside its rounded shape.
  2. Pinning adds no second shadow.
- **Priority:** Must.

#### CARD-07 · Folding keeps the gap between files
- **Statement:** A folded card keeps the spacing to the next card.
- **Source:** 09-22 16:41, "also collapsing one file removes the gap space with the next file/fileheader".
- **Acceptance criteria:** The gap between cards is the same whether a card is expanded or folded.
- **Priority:** Must.

#### CARD-08 · Expand and collapse symbols with an animated transition
- **Statement:** The fold control uses expand and collapse symbols that morph into each other.
- **Source:** 09-22 15:03, "shouldn't we use the collapse/expand icon in the file list file header bar instead of
  the arrow? i think we should animate them and symbol transition them".
- **Acceptance criteria:** The header shows an expand or collapse symbol matching the fold state, and a symbol
  transition animates the swap.
- **Priority:** Should.

#### CARD-09 · Badge states and Xcode's colors
- **Statement:** Badges show whether a change is staged, in the chosen color scheme.
- **Source:** 09-22 16:37, "when a change is not staged, instead of filling the background of the badge it uses a
  strokeborder and text with the color and a transparent background, added is green, modified is blue, and we can
  maybe keep the other ones, when a file is not added/staged yet but new xcode shows a ? instead, but i'd much
  prefer the A with a stroke".
- **Acceptance criteria:**
  1. A staged change shows a filled badge; an unstaged change shows a stroked badge with colored text on a
     transparent background.
  2. In the Xcode scheme, Added is green, Modified is blue and Deleted is red (confirmed 09-23 09:37, Q4).
     Renamed is blue too: Xcode draws a rename as a blue "M" (images 22 and 23, 09-23 12:05), and the user chose to
     keep the letter "R" ("i'd prefer we use R for renamed though", 12:05), "so it's clearer than an M that means
     the same thing than the other files" (12:06).
  3. A new file that is not staged shows "A" with a stroke, not "?".
  4. The same rules apply wherever a badge appears.
- **Open point:** Xcode writes a renamed row as "HTTPClient.swift ← APIClient.swift", the old name grayed after an
  arrow (image 23). The assistant offered that label at 12:06; the user has not answered (OQ9).
- **Priority:** Should. **Related:** CARD-11, SET-07, DIFF-05.

#### CARD-10 · Badges follow the list's selection and focus
- **Statement:** A selected row's badge inverts only while the list has focus.
- **Source:** 09-22 16:37, "when the file is selected in the list then, the background of the selection is blue
  as it is natively but the diff badge color are inverted with white, so for example, added would be green text
  white background for the badge, but this only happens when the focus is on the list, when the focus shift to
  something else, instead of having the list element in the file list selected and blue, the background is tinted
  in some gray transparent but text stays black and badge goes back to normal".
- **Acceptance criteria:**
  1. Selected row in a focused list: native blue selection, and the badge inverts to a white background with its
     color as text.
  2. Selected row in an unfocused list: native gray selection, and the badge keeps its normal look.
  3. Refined 09-23 (mid-turn): "if unstaged (means stroke and text only), stroke and text should be white …
     it should be background white with corresponding text color if the file is staged". On a focused
     selection, a stroked badge draws its outline and letter in white; a staged badge inverts to a white fill
     with its status color as text.
  4. Bug report, 09-23 11:36: "the white badge variant in the side bar file list/trees is not working when the
     sidebar is focused and file selected, i still have plain badges with white text". Criteria 1 to 3 hold in the
     sidebar's file list and in its file trees.
- **Priority:** Should.

#### CARD-11 · Badge states come from git's per-file state (Derived)
- **Statement:** A file's badge state reflects git's index and worktree status for that file.
- **Source:** derived from 09-22 16:37, "when a change is not staged" and "when a file is not added/staged yet".
- **Refined:** 09-23 10:26, "didn't i mention in a previous prompt that staged/tracked (and i guess that includes
  committed files) should have filled background variant of diff badges ?"
- **Acceptance criteria:**
  1. Each file's badge state (staged, unstaged, untracked) comes from git's status for that file, not from which
     side of the comparison it is on.
  2. A committed change, and a staged change with nothing left unstaged, draws filled, in working-tree and
     ref-to-ref comparisons alike.
- **Open point:** two choices the assistant reported at 11:15 without an answer: a file with both staged and
  unstaged changes draws stroked, and a folder draws stroked when git reports any unstaged or untracked file inside
  it, including files the list does not show. Both are kept as defaults unless the user objects (see the
  open questions).
- **Priority:** Should. **Related:** CARD-09.

#### CARD-12 · A custom sticky card container
- **Statement:** The card list's sticky headers, clipping and scrolling are built by a custom container.
- **Source:** 09-23 09:05, "maybe for the cards with sticky header in the scrollview, we want to go completely
  custom as it is really important to get the clipping, sticking and scrolling right without have the issues of
  clipping and not clipping the wrong things".
- **Acceptance criteria:**
  1. A pinned header rests 16 pt below whatever bar sits above the list.
  2. Content scrolling up is clipped at the pinned header's rounded top, and never shows in the gap above it.
  3. A card's bottom pushes its pinned header out.
  4. At rest, a card is one rounded shape with one shadow, one border and one seam line.
  5. Nothing clips the scrollbar or a neighboring card's shadow.
  6. No backdrop blur, and no SwiftUI update, happens per scroll frame.
- **Accepted:** 09-23 09:41, on the agent's review build: "the gdv card review app does exactly what i want, but the
  scrolling is so sluggish". The look is approved; smooth scrolling of these cards is PERF-05.
- **Priority:** Must. **Related:** CARD-02 to CARD-07, PERF-05, PERF-07.

### TAB: Window tabs and the in-app tab bar

#### TAB-01 · Native tabs for comparison windows (investigate)
- **Statement:** Comparison windows can group as native macOS window tabs.
- **Source:** 09-22 13:03, "also i'd prefer that you investigate a native tab implementation ideally".
- **Acceptance criteria:**
  1. Comparison windows merge into native window tabs.
  2. The welcome window never joins them.
  3. The native tab bar's + button opens the welcome window.
- **Priority:** Could. Q1 (09-23) moved the user's ask to TAB-07.

#### TAB-02 · Equal gaps in the in-app tab bar
- **Statement:** The space between tabs equals the space around them.
- **Source:** 09-22 16:37, "for the tabs, we might want to have the same gap between them as we have negative
  space around them in the tab bar".
- **Acceptance criteria:** The gap between tabs equals the bar's inset on every side.
- **Priority:** Should.

#### TAB-03 · Glass tabs with a very light shadow
- **Statement:** Each tab is glass with a very light shadow.
- **Source:** 09-22 16:37, "we might want them to be glass looking with very light shadow".
- **Acceptance criteria:** Each tab renders as glass with a very light shadow; the bar adds no material of its own.
- **Priority:** Should.

#### TAB-04 · The close button takes the badge's place on hover
- **Statement:** The close button reserves no space and appears in the badge's slot on hover.
- **Source:** 09-22 16:37, "the close button should not utilize an additional space on the leading side … and
  the close icon should appear in place of the diff badge when the tab is hovered".
- **Acceptance criteria:**
  1. No leading space is reserved for the close button.
  2. On hover, the close button replaces the badge in the same slot.
- **Priority:** Should.

#### TAB-05 · The badge replaces the document icon; tabs stay neutral
- **Statement:** A tab's leading visual is its diff badge, and tabs carry no color of their own.
- **Source:** 09-22 16:37, "we should display the diff badge instead of the doc icon, tab should be of neutral
  color because the diff badge handles the visual cue".
- **Acceptance criteria:**
  1. A tab with a change shows its diff badge where the document icon was.
  2. Tabs carry no accent tint.
- **Priority:** Should.

#### TAB-06 · Restyle native macOS window tabs (Superseded)
- **Source:** the assistant's first reading of the 09-22 16:37 request (roadmap at `eeb7ffa`: "Tab bar styling
  (user-requested; needs investigation)").
- **Superseded by:** TAB-02 to TAB-05 (corrected 09-23 07:51).

#### TAB-07 · Native behavior for the in-app file tabs
- **Statement:** The in-app file tabs behave like a native macOS tab bar.
- **Source:** 09-23 09:37 (Q1), "native behaviour for the in-app file tabs?"
- **Acceptance criteria:**
  1. Tabs reorder by dragging.
  2. ⌘W closes the active tab; ⌃Tab and ⌃⇧Tab (and ⌘⇧] and ⌘⇧[) move between tabs.
  3. A middle click closes a tab; the context menu offers Close Other Tabs and Close Tabs to the Right.
  4. The active tab scrolls into view, and tabs that do not fit stay reachable.
  5. Tabs expose accessibility labels and actions.
- **Priority:** Should. **Related:** TAB-01, TAB-08.

#### TAB-08 · Tab hover, close button, capsule shape and pin symbol
- **Statement:** Tabs are capsules that respond to hover, with a clear close target and a mark for kept-open tabs.
- **Source:** 09-23 (mid-turn), "a slight toning of the tab when hovering it, and when hovering the close button
  especially, background of the button also indicates the hovering, and in my opinion, those tabs should be
  capsule shape, also a pinned tab could have at the trailing side of its content a pin symbol"; 09-23 09:37,
  "tab hovering background could be lighter and leading padding with the file diff badge in the tab could be
  increased or badge scaled down … also the close x mark in the close button does not seem to be vertically
  aligned".
- **Acceptance criteria:**
  1. Tabs are capsule-shaped.
  2. A hovered tab takes a light tint.
  3. The close button shows a round background while hovered, and its × is centered vertically.
  4. The badge sits concentric with the capsule's leading curve, never crowding it.
  5. A kept-open tab shows a pin symbol at the trailing end of its content.
- **Priority:** Should. **Related:** TAB-02 to TAB-05.

#### TAB-09 · A native backdrop beneath the tab bar
- **Statement:** Content scrolls beneath the tab bar with the system's own scroll edge effect.
- **Source:** 09-23 (mid-turn), "we could reuse the backdrop effect beneath them to have the same effect that
  natives provide, else investigate variable blur from {g-cqd,aemi-studio}/AemiSDR".
- **Acceptance criteria:**
  1. In both the card list and the single-file pane, content scrolls beneath the tab bar and shows the system
     scroll edge effect, as under the toolbar.
  2. If no native mechanism works, AemiSDR's variable blur is evaluated and a recommendation is made before any
     dependency is added.
- **Priority:** Should. **Related:** TAB-03.

#### TAB-10 · The file list as a fixed tab
- **Statement:** While files or folders are open in tabs, the file list is one more tab, fixed first, so going back
  to it closes nothing.
- **Source:** 09-24 13:14 (mid-turn), "it would also be interesting to be able to go back to file list viewing from a button
  somewhere and without closing all tabs, it would just appear as another fixed tab when viewing single files or
  folders".
- **Acceptance criteria:**
  1. With single files or folders open in tabs, a fixed first tab shows the file list, and selecting it shows the
     list without closing any tab.
  2. The other tabs stay open and keep their state, scroll position included.
  3. The fixed tab cannot be closed or moved.
- **Priority:** Should. **Related:** TAB-01, PERF-10.

### GIT: Git features, freshness and reload continuity

#### GIT-01 · Watch the repository and refresh automatically
- **Statement:** Changes made outside the app appear without a manual refresh.
- **Source:** 09-22 10:04, "also do we have watchers for changes on a repo, because i think right now i have not
  that, so i need to refresh the state of the repo manually".
- **Acceptance criteria:**
  1. An edit to a tracked file in the working tree shows up without a manual reload.
  2. A commit, a checkout or a branch switch updates the comparison and the ref menus.
  3. Linked worktrees behave the same way.
  4. No edit is lost while a reload is running.
  5. A setting turns the watcher off.
- **Priority:** Must. **Related:** GIT-03, PERF-03.

#### GIT-02 · Fetch, reusable by the terminal editor
- **Statement:** The app fetches from the remote to update remote-tracking branches, through git code the terminal
  editor can reuse.
- **Source:** 09-22 10:04, "it could be interesting to provide a subset of git features for example allowing to
  fetch the latest information about the repository to update the known origin main branch for example … but we
  should make sure that those git features are compatible and generic enough to be used in the
  atelier/kittyterminal editor".
- **Acceptance criteria:**
  1. The source menus offer Fetch; afterwards the branch lists update and a comparison against a
     remote-tracking ref shows the new tip.
  2. The git operations live in the shared core (`AtelierGit`) with no GitDiffViewer dependency.
- **Priority:** Should. **Related:** QUAL-07.

#### GIT-03 · A reload never collapses the viewer
- **Statement:** Reloads keep what is on screen.
- **Source:** 09-22 13:03, "as well as not collapsing the viewer when a file reload or when a comparison reload".
- **Acceptance criteria:**
  1. During a file reload, an automatic refresh or a full re-comparison, the card list or the file pane stays on
     screen and never switches to "Comparing…".
  2. Scroll position, folds and revealed lines survive.
  3. This holds for one-sided and two-sided reloads (the Reload button, Swap, a commit in a terminal).
- **Priority:** Must. **Related:** GIT-04.

#### GIT-04 · A re-comparison keeps loaded files
- **Statement:** A re-comparison redoes only the files whose state changed.
- **Source:** 09-22 13:04, "also ideally the comparison should not discard the already loaded file and only
  change the content if the comparison renders differently or the changeset provide a different state for a said
  file".
- **Acceptance criteria:**
  1. A file whose path and blobs did not change is neither re-read, re-diffed nor re-rendered.
  2. Only files whose state changed re-render.
  3. A change of diff options re-renders everything.
- **Priority:** Must.

#### GIT-05 · The repository watcher never crashes the app (Derived)
- **Statement:** Watching a repository can never make the app read freed memory.
- **Source:** 09-23 10:42, a pasted crash report (573 lines) from the installed app, 18 minutes after launch:
  `EXC_BAD_ACCESS (SIGSEGV)` on the watcher's dispatch queue (`com.kittycode.fswatcher`), inside
  `AsyncStream.Continuation.yield` called from the FSEvents callback in `FileWatcher.watchDirectory`
  (`AtelierFileWatcher.swift:102`), reading a garbage type-metadata pointer.
- **Rationale:** The review had flagged the watcher box's lifetime as unproven (Core S15, Aemi #27); the crash
  proved it.
- **Acceptance criteria:**
  1. An FSEvents callback still in flight when a watcher stops or is released never touches freed memory.
  2. A watcher released without `stop()` shuts its stream down.
  3. A stress test that stops or drops watchers while events arrive passes repeatedly.
- **Priority:** Must. **Related:** GIT-01.

#### GIT-06 · The flat file list grouped by commit
- **Statement:** When the two compared states of a repository share their history, a setting groups the flat file
  list into disclosable sections, one per commit, each holding the files that commit changed.
- **Source:** 09-25, "i'd like that we investigate ways to improve the one flat sidebar file list, by having a
  toggleable setting to group through disclosable section diffed files by commit when the 2 compared repo states
  share the same ancestry, it can only work in flat sidebar, for repos".
- **Acceptance criteria:**
  1. A research note settles, before building: how a changed file is attributed to commits (each commit that touched
     it, or the last one), merges and first-parent history, renames across commits, uncommitted changes as a section
     of their own, what "share the same ancestry" admits (one side an ancestor of the other, or a common merge base),
     the section header (subject, author, date, counts), what selecting a section does, and a cap for long ranges.
  2. A setting, off by default, turns the grouping on; it applies only to the flat list style, and only when both
     sides are states of one repository whose histories connect. Otherwise the list stays as it is and the setting
     says why it does not apply.
  3. Each section can be disclosed and collapsed, and remembers that state through a reload.
  4. Building the groups never blocks the interface, and a range of many commits stays responsive.
  5. A file selected under a commit shows that commit's own change to it, from the commit's first parent to the
     commit, never the whole range's sum; a selected commit shows its own changes the same way, and Uncommitted
     Changes shows HEAD against the working tree (D39).
  Criterion 1 is settled by `Apps/GitDiffViewer/docs/commit-grouping-design.md` and decisions D29 to D32; D39
  replaces D31's net diff.
- **Priority:** Should. **Related:** CARD-09, GIT-03.

### WIN: Window chrome and stability

#### WIN-01 · The toolbar customization persists
- **Statement:** A customized toolbar survives a relaunch.
- **Source:** 09-22 10:04, "i also noted that the toolbar was not persisting across restart of the app".
- **Acceptance criteria:** After quitting and relaunching the installed app, the toolbar looks as the user left it.
- **Priority:** Must.

#### WIN-02 · Restoring a saved toolbar never crashes the app (Derived)
- **Statement:** A saved toolbar customization can never crash the app.
- **Source:** 09-22 11:08, a pasted crash report: `EXC_BREAKPOINT (SIGTRAP)` on the main thread in
  `AppKitToolbarStrategy.applyItemCustomizations(toolbar:customizations:storage:toolbarStorage:)`.
- **Acceptance criteria:**
  1. The app launches and runs with a toolbar customization saved by any earlier build.
  2. Adding or removing toolbar items in a new build does not crash an existing customization.
- **Priority:** Must.

#### WIN-03 · Both source selectors show the same kind of information
- **Statement:** The left and right selectors describe their source the same way.
- **Source:** 09-22 10:04, "also the repo selectors are weird because they don't display the same information for
  both sides one with the folder and branch, one with the branch and something els".
- **Acceptance criteria:** Both selectors show the repository name and the side's ref, with the working tree
  shown as "Working Tree" and matching icons.
- **Priority:** Should.

### PERF: Performance and non-blocking work

#### PERF-01 · Tool runs never block the UI
- **Statement:** Running the analyzers never blocks the interface or the rest of the app.
- **Source:** 09-21 14:27, "the run of a tool should not be blocking the ui or the app, as much should be handled
  in parallel and not blocking".
- **Acceptance criteria:**
  1. Tool processes run in parallel, off the main actor, on a pool separate from git's.
  2. Output parsing runs off the main actor.
  3. The UI stays responsive during a lint of the whole repository.
- **Priority:** Must.

#### PERF-02 · Main-actor work is offloaded with `@concurrent`, and tests prove it
- **Statement:** A review of the whole codebase moves heavy work off the main actor with `@concurrent`, and tests
  check that it runs off the main thread.
- **Source:** 09-21 16:25, "i'd much prefer across the whole codebase that we review all the opportunities to
  offload work from mainactor by using the `@concurrent` decoration so that we ensure it really goes off the
  mainactor, and we could add some tests using Thread.isMainThread and using the pthread variant to ensure we do
  execute work off the main actor".
- **Acceptance criteria:**
  1. The review covers every package: GitDiffViewer, KittyCode and AtelierCore.
  2. Heavy passes that must not run on the main actor are `@concurrent`.
  3. Tests prove each such seam runs off the main thread (`pthread_main_np`, and `Thread.isMainThread` where the
     language allows it).
- **Priority:** Must.

#### PERF-03 · No feedback loops
- **Statement:** Nothing the app does triggers its own reloads.
- **Source:** 09-22 13:02, "the hovering or the loading of documentation is triggering recomparison of the whole
  scope every 2 seconds"; 09-23 07:59, "feedback-loop free".
- **Acceptance criteria:**
  1. Nothing the app or the tools it starts write (language-server indexes, caches, tool output) triggers a reload.
  2. A regression test pins each loop that was fixed.
- **Priority:** Must. **Related:** GIT-01.

#### PERF-04 · Hovering folded headers costs nothing
- **Statement:** Pointer movement over a fully folded list does no work.
- **Source:** 09-22 16:47, "it seems that when all the files are collapsed the hovering creates a big overhead in
  resources even though i cannot hover any meaningful things, i only hovering collapsed section file headers".
- **Acceptance criteria:** Moving the pointer over folded headers does no resolver, hit-test or layout work,
  measured.
- **Priority:** Must.

#### PERF-05 · The file list scrolls smoothly
- **Statement:** Scrolling the card list is smooth.
- **Source:** 09-22 16:48, "and the scroll is very slow and sluggish on the file list"; 09-23 09:41, on the custom
  card container's review build, "the gdv card review app does exactly what i want, but the scrolling is so
  sluggish".
- **Acceptance criteria:**
  1. Scrolling a list of 33 or more files holds the display's frame rate, measured with Instruments.
  2. A scroll frame re-evaluates no card body unless the card's pinned state changes.
- **Priority:** Must.

#### PERF-06 · Few live materials
- **Statement:** The list uses live blur only where it is needed.
- **Source:** 09-22 16:53, "could that be because it seems that we render 2 material layer per file headers and i
  can have a list of 33 files or more, times 2... that definitely creates a lot of graphical computation as well".
- **Acceptance criteria:**
  1. No header carries two materials.
  2. Resting cards use opaque fills; live blur appears only where content scrolls beneath (a pinned header).
  3. The number of live blur surfaces does not grow with the number of files.
- **Priority:** Must.

#### PERF-07 · The app on screen does not slow the whole machine
- **Statement:** Showing the app costs the window server no more than an idle window does.
- **Source:** 09-22 17:01, "but then how do you explain that as soon as the app is on display, the whole computer
  becomes super laggy".
- **Acceptance criteria:** With the app visible on a comparison of 33 or more files, WindowServer CPU stays at its
  idle level (single digits), measured before and after the fix. The measurement before the fix was 38.4%
  (09-22 17:02).
- **Priority:** Must. **Related:** PERF-06.

#### PERF-08 · No unnecessary work (Derived)
- **Statement:** The app does work only when its inputs changed.
- **Source:** 09-23 07:59, "performance, fidelity to the requirements, memory efficiency, feedback-loop free,
  unnecessary work, safety, security" (the review criteria).
- **Acceptance criteria:**
  1. Unchanged inputs trigger no re-read, re-parse or re-render (hover index, diagnostics, relayout).
  2. Work scales with what changed, not with the repository's size.
  3. Caches have a memory bound.
- **Priority:** Should.

#### PERF-09 · Text first, then diff and syntax color in parallel
- **Statement:** Text renders first; diff structure and syntax color follow in parallel, off the main thread,
  without blocking, safely, and within a small time budget.
- **Source:** 09-23 (mid-turn), "micro optimizations towards improving rendering speed across gui/tui, for all
  files and diff and syntax highlighting, as well as making each aspect non blocking with having rendering text
  become the utmost priority, and syntax highlighting and diff rendering being done in parallel, non blocking,
  failsafe and instantaneous".
- **Acceptance criteria:**
  1. In both apps, a file's plain text is drawn before any diff or syntax color is computed.
  2. Diff structure and syntax color run in parallel, off the main thread, visible lines first.
  3. Each stage can be cancelled, has a measured time budget, and fails safe: a failure or timeout leaves plain
     text, never a blank or a stall.
  4. Color arrives as attribute-only updates that cause no relayout.
  5. Each budget is set from a measurement, and a benchmark guards it.
- **Priority:** Must. **Related:** PERF-01, PERF-08, QUAL-08.

#### PERF-11 · Syntax color arrives in tiers, each richer than the last
- **Statement:** A file's syntax color is a tiered job. The lexer and the grammar parse start together; the lexer's
  color shows at once and the grammar's replaces it when its parse lands; for Swift, swift-syntax and sourcekit-lsp's
  semantic tokens refine it further when those tiers are enabled. Each tier also keeps what it learns, for the
  features that can use it.
- **Source:** 09-25, "imo, the highlighting should be a tiered job, lexer and grammar started in parallel, swift
  syntax and sourcekit when enabled, used to also enrich the color syntaxing ideally and provide more information at
  that moment as well".
- **Acceptance criteria:**
  1. The lexer and the grammar parse start in parallel, off the main thread. The first paint uses the lexer's color;
     the grammar's replaces it once its parse passes the quality gate, as an attribute-only update (PERF-09).
  2. For Swift, a swift-syntax tier and a sourcekit-lsp semantic-token tier each refine the color when enabled,
     merged by layer, then width, then priority (3G's merger), without blocking the tiers below.
  3. A slow, failing or disabled tier leaves the color of the tiers below it; nothing blanks or stalls.
  4. What a tier learns (declaration kinds, symbol roles, semantic token types) is kept with the file for other
     features, such as hover and navigation, rather than thrown away after coloring.
  5. Both apps get the tiers through the shared core (MOD-01), and GitDiffViewer gains grammar color (4A).
- **Priority:** Should (a design note first). **Related:** PERF-09, MOD-01, HOVER-16, LANG-01.

#### PERF-10 · Switching between the file list and a single file is quick
- **Statement:** Opening a file from the file list, and returning to the list by closing the file tabs, happen
  without a visible stall.
- **Source:** 09-24 13:14 (mid-turn), "closing all inner tabs and going back to file list is very slow, and going from file list
  to single file viewing is very slow".
- **Acceptance criteria:**
  1. Opening a file from the list shows it within a budget set from a measurement of the current cost.
  2. Closing the last file tab shows the list within its own measured budget.
  3. A benchmark guards each.
- **Priority:** Should. **Related:** PERF-09, TAB-10.

### JSON: AemiJSON

#### JSON-01 · Measure Foundation against AemiJSON on the app's JSON
- **Statement:** Benchmarks compare Foundation and AemiJSON on the app's real JSON workloads.
- **Source:** 09-21 15:24, "do we use the native json of apple or the aemijson implementation ? aemijson should
  usually be faster, could you probe speed for the use cases we have in the app regarding json".
- **Acceptance criteria:**
  1. A benchmark covers SARIF decoding, LSP messages and settings blobs.
  2. It lives in the repository, gated by an environment variable as `AGENTS.md` requires, so the numbers can be
     reproduced.
- **Priority:** Must.

#### JSON-02 · Use AemiJSON's fast paths wherever the numbers justify
- **Statement:** Each JSON call site uses the fastest correct path the measurements support.
- **Source:** 09-21 15:24, "make sure to investigate fast paths of aemijson and audit how we can leverage the
  performance of aemijson to the largest extent".
- **Acceptance criteria:**
  1. Each JSON call site has a recorded verdict (adopt, later, keep Foundation) with numbers.
  2. The hot paths (SARIF decoding, LSP envelopes and payloads) use AemiJSON's fastest correct path, with no
     redundant parse or copy.
- **Amended:** 09-23 13:06 by JSON-04 (change of mind 8): "keep Foundation" is no longer an allowed verdict.
- **Priority:** Should.

#### JSON-03 · AtelierLSP's JSON-RPC uses AemiJSON
- **Statement:** The language-server client encodes and decodes JSON-RPC through AemiJSON.
- **Source:** 09-22 14:44, "why is atelierlsp not leveraging aemijson for the jsonrpc for example".
- **Acceptance criteria:** Every JSON-RPC envelope and payload in AtelierLSP is encoded and decoded through AemiJSON.
- **Priority:** Must.

#### JSON-04 · Every JSON read and write goes through AemiJSON
- **Statement:** All JSON the three packages read or write goes through AemiJSON, for speed.
- **Source:** 09-23 13:06, "can you make sure we use aemijson whenever we do json interaction to accelerate
  performances".
- **Acceptance criteria:**
  1. No production code in GitDiffViewer, KittyCode or AtelierCore decodes or encodes JSON with `JSONDecoder`,
     `JSONEncoder` or `JSONSerialization`.
  2. Data the Foundation encoder wrote before the switch, such as settings in `UserDefaults` and on-disk caches,
     still reads back (derived).
  3. Each switched call site that is not trivially small has a before and after measurement, as the Definition of
     Done asks of every performance statement (derived).
  4. Decoders of untrusted or hand-edited JSON cap the nesting depth (derived from review finding Aemi #6).
- **Priority:** Must. **Related:** JSON-01, JSON-02, JSON-03; amends JSON-02.

### MOD: Modularization for GUI and terminal reuse

#### MOD-01 · Generic parts live in the shared core
- **Statement:** Code without a UI dependency moves out of GitDiffViewer into shared Atelier packages.
- **Source:** 09-21 15:05, "should we move more out of gitdiffviewer into more generic reusable parts that can be
  used in the atelier/kitty scope ?".
- **Acceptance criteria:**
  1. Everything with no UI dependency lives in `Packages/AtelierCore`: diagnostics, LSP, doc index, file
     watching, git features, hover structuring.
  2. No duplicate or dead copy stays behind in an app.
- **Priority:** Should.

#### MOD-02 · Plug and play between the terminal and GUI apps
- **Statement:** Every module can serve both the terminal editor and the GUI app.
- **Source:** 09-22 10:04, "i'd like that you review investigate the various module, concerns and scopes and work
  at modularizing everything to make sure everything is plug and play between the terminal use and the gui app".
- **Acceptance criteria:**
  1. A module map lists each concern, its tier and its consumers.
  2. Core modules carry no app-specific names (environment prefixes, queue labels).
  3. Both apps use the same core for shared concerns: file watching, git status and refresh, diagnostics, hover.
- **Priority:** Should.

#### MOD-03 · Core targets honor the AGENTS.md tier rules (Derived)
- **Statement:** Core targets follow the tier contract.
- **Source:** derived from PROC-08 and `AGENTS.md` ("no unstructured tasks and no `TaskProvider`" in the core
  tier).
- **Acceptance criteria:** No core target starts an unstructured `Task` or uses `TaskProvider`; core services
  expose async functions, task groups and streams that the caller drives.
- **Priority:** Must.

### QUAL: Code quality, review processes and safety

#### QUAL-01 · Designs use the latest Swift and SwiftUI APIs
- **Statement:** Plans and code use the newest APIs the version floor allows.
- **Source:** 09-21 14:37, "review the plan and proposed design under a modern prism where we use the latest api
  in regards of swift and swiftui, use all relevant skills".
- **Acceptance criteria:**
  1. The plan review's modernization findings are applied.
  2. No legacy API remains where the version floor (macOS 26.1, Swift 6.4) allows the modern one.
- **Priority:** Should.

#### QUAL-02 · An independent Codex review of the day's changes
- **Statement:** Codex reviews the whole day's changes non-interactively.
- **Source:** 09-22 14:32, "in parallel trigger a codex cli non-interactive review mode inviting to load all
  relevant skills and using gpt-6-astra model for all the changes done throughout the day on the whole codebase,
  both atelier, gitdiffviewer, kitty/aterlier terminal related stuff".
- **Acceptance criteria:**
  1. `codex exec` runs non-interactively with `gpt-6-astra`, read-only, over every change since the day's base,
     with the skills and `AGENTS.md` loaded.
  2. Each finding is verified, then fixed or deferred with a reason.
- **Priority:** Must.

#### QUAL-03 · Strip verbose comments
- **Statement:** Comments state contracts and constraints only.
- **Source:** 09-23 07:52, "could run in parallel an agent dedicated to stripping all the verbose comments all over
  the codebase plesae".
- **Acceptance criteria:**
  1. History, review references and narration leave the comments; contracts and real constraints stay.
  2. The sweep changes no code, as a parse-tree comparison proves.
  3. The sweep lands on `main` (PROC-05).
- **Priority:** Should.

#### QUAL-04 · A requirements book, a plan and an audit
- **Statement:** Every request of the last three days becomes a requirement, ordered and audited.
- **Source:** 09-23 07:59, "could you run a parallel an agent dedicated to find about all the requests i sent in
  the passed 3 days in this projects, draw requirement plan and book, and then audit the codebase for all the
  criterias".
- **Acceptance criteria:** Three documents under `docs/requirements/` cover every request, order the work, and give
  one verdict per requirement with evidence.
- **Priority:** Must.

#### QUAL-05 · A code review of the codebase and the owned dependencies
- **Statement:** The whole codebase and the dependencies the user owns are reviewed against the stated criteria.
- **Source:** 09-23 07:59, "then run in parallel a code review throughout all the codebase, submodules and
  dependencies we own (aemi-*, g-cqd/*, g-cqd/*) and use in this project, performance, fidelity to the
  requirements, memory efficiency, feedback-loop free, unnecessary work, safety, security".
- **Acceptance criteria:** Review reports cover GitDiffViewer, KittyCode, AtelierCore, aemi and AemiJSON, the owned
  analyzers and hooks, and security, against the listed criteria.
- **Priority:** Must.

#### QUAL-06 · The global Definition of Done holds (Derived)
- **Statement:** Every change meets the Definition of Done in `~/.claude/CLAUDE.md` and the rules in `AGENTS.md`.
- **Source:** derived from 09-22 10:04 and 09-23 07:59 ("load … main claude.md files").
- **Acceptance criteria:**
  1. No TODO, FIXME or stub in scope, and no deferred work without a tracking reference.
  2. No compiler warning; the tests pass.
  3. Each new behavior has a test that follows `AGENTS.md`: backtick sentence names and event-driven waiting.
  4. Each performance statement has a measurement.
  5. Documentation agrees with the code.
  6. Each commit is scoped and titled in the repository's form.
  7. No force unwrap, no empty catch.
- **Priority:** Must.

#### QUAL-07 · Untrusted repositories cannot run code (Derived)
- **Statement:** Opening, hovering or fetching in a repository runs no command that the repository's own files
  choose, unless the user trusts that repository.
- **Source:** 09-23 07:59, "safety, security" (the review criteria).
- **Decided:** D7, 09-23 12:34, "Prompt on first hover (Recommended)".
- **Acceptance criteria:**
  1. The language server does not start with an untrusted repository as its workspace.
  2. git commands pin or reject every configuration key that can run a command.
  3. Hover links open only safe URL schemes.
  4. The first hover in an unknown repository asks once whether to trust it; doc comments and SDK documentation
     keep answering meanwhile; a list in Settings reviews and revokes trust (D7's option text).
- **Priority:** Must. **Related:** GIT-02, HOVER-01, QUAL-09.

#### QUAL-08 · A measured rendering-performance review
- **Statement:** A dedicated review measures rendering speed across the GUI, the TUI and the shared engines, and
  proposes micro-optimizations and a text-first pipeline.
- **Source:** 09-23 (mid-turn), "could you run a specific review dedicated at micro optimizations towards
  improving rendering speed across gui/tui".
- **Acceptance criteria:** Reports for the GUI, the TUI and the core engines give measured costs, ranked fixes
  with expected gains, and a progressive pipeline design (PERF-09).
- **Priority:** Must. **Related:** PERF-09.

#### QUAL-09 · A cloned repository cannot get its own hook binary run
- **Statement:** The git hooks installed on this machine never run a binary that a repository ships inside itself.
- **Source:** decision D6, 09-23 12:34, "Patch now (Recommended)", answering "Should I patch the hook script your
  global git template installs (and the copies already in your clones), so a cloned repository can no longer get
  its own project-hooks binary run on your first commit?"
- **Rationale:** Review finding PH-6 was reproduced on this machine: a fresh clone ran its own committed
  `.build/release/project-hooks` on its first commit, through the global git template's hooks.
- **Acceptance criteria:**
  1. `~/.git-templates/hooks/pre-commit` and `pre-push` no longer try `$REPO_ROOT/.build/release/project-hooks`.
  2. Neither do the hooks already copied into existing clones.
  3. The original hooks are backed up, so the change can be undone.
- **Priority:** Must. **Related:** QUAL-07, PROC-12 (the proper fix in project-hooks, fix plan track 1K).

#### QUAL-10 · Re-gather the requests, re-assess them, and ask the open questions
- **Statement:** Every request since 09-19 is gathered again, each requirement's status is re-assessed on the current
  code, and the points that need the user are put to the user.
- **Source:** 09-23 13:29, "please perform a regathering of all prompts and requirements and assess their
  implementation or design or preparation status since 3-4 days on the whole scope of this project, and come back to
  me with questions if there are open points".
- **Acceptance criteria:**
  1. The book covers every request and decision since 09-19 00:00.
  2. Each requirement has one status at the current `main`, with evidence.
  3. The open questions give their options and a recommended default.
- **Priority:** Must. **Related:** QUAL-04.

### CARD (continued): Requests after the audit

#### CARD-13 · Folding keeps the text visible and the colours steady
- **Statement:** Folding a card clips its text away as the card shrinks; no frame shows another background colour.
- **Source:** 09-23 (after the audit), "when collapsing the background is darker grayish that's very distracting for
  the file cards, when the text disappears while it collapses, that feels weird".
- **Acceptance criteria:**
  1. On fold, the text stays visible and is clipped progressively until only the header remains.
  2. On unfold, the body is revealed with its content, never as an empty band.
  3. No frame shows a background colour the card does not have at rest.
- **Priority:** Must. **Related:** CARD-12.

#### CARD-14 · Split layouts size cards exactly
- **Statement:** In the side-by-side layout, a card's height equals its content, stays stable while scrolling, and
  unfolding never blanks the list.
- **Source:** 09-23, "when using another layout than the inline, scroll in the file list cards is buggy and sometimes
  big spaces are added to the content of the file cards"; "split layout, plus expanding a file completely erases the
  scrollview content".
- **Acceptance criteria:**
  1. Card heights equal their laid-out content in every layout, with wrapping on and off.
  2. No card height changes during a scroll unless its content changed.
  3. Unfolding a card in the split layout keeps the list's content on screen.
- **Priority:** Must. **Related:** CARD-12, CARD-16 (the NaN height behind criterion 3), PERF-05.

#### CARD-15 · The card list offers inline and side by side only
- **Statement:** The card list supports the inline and side-by-side layouts; stacked is for a single file.
- **Source:** 09-23, "file list cards should only support inline or horizontal split, but not stacked split".
- **Acceptance criteria:**
  1. With Stacked selected, the card list draws side by side, and the stored setting is unchanged.
  2. While the card list shows, Stacked is disabled in the toolbar picker and the View menu, with an explanation.
  3. A single file still honours Stacked.
- **Priority:** Must.

#### CARD-16 · Card geometry is always finite (Derived)
- **Statement:** No card ever hands SwiftUI or AppKit a size or position that is not a finite number.
- **Source:** 09-23 12:06, a pasted crash report (592 lines) from the fold agent's review build: `EXC_BREAKPOINT
  (SIGTRAP)` on the main thread in `_NSViewValidateGeometry`, called from `-[NSClipView setBoundsOrigin:]` inside
  SwiftUI's `HostingScrollView.updateContext`, with the message "Invalid view geometry: y is NaN". It explains R78
  ("expanding a file completely erases the scrollview content"): the same NaN blanked the list on earlier builds.
- **Acceptance criteria:**
  1. Every size and position a card reports is finite and not negative, in every layout and fold state, including
     before the card has a width.
  2. Unfolding a side-by-side card neither blanks the list nor crashes the app.
  3. A regression test reproduces the conditions of the crash.
- **Priority:** Must. **Related:** CARD-14.

#### CARD-17 · Scrolling always reaches the end of a file
- **Statement:** Scrolling reaches every file's last line and never stops responding, even while the file updates.
- **Source:** 09-24 13:14 (mid-turn), "sometimes scrolling through files, maybe being updated at the same time does not allow to
  scroll to the end of files, scrollable content does block sometimes (work and test work for example had the
  issue)", meaning `work.py` and `test_work.py` in a comparison of the skills repository.
- **Acceptance criteria:**
  1. Scrolling reaches the last line of every file, in the card list and in the single-file view.
  2. A file whose content changes while shown (a reload, a card still streaming in) keeps a scroll range that covers
     all of its content.
  3. Scrolling never stops responding to input.
  4. A regression test reproduces the conditions that cut the range short.
  5. A file opened from the list, by a single or a double click, small or large, always scrolls (R115, reported
     after the first fix).
- **Priority:** Must. **Related:** CARD-12, CARD-14, PERF-05, DIFF-08.

#### CARD-18 · No sideways scroll when a file fits, and no bounce in code panes
- **Statement:** A pane scrolls sideways only when its lines are wider than it, and no code pane rubber-bands past
  its edges.
- **Source:** 09-24 13:44 (mid-turn, to the agent fixing DIFF-06 and CARD-17), "while you're at it maybe you can inspect why sometimes the horizontal scroll is possible when
  the file width actually matches or fits the containers / also, in the single file viewing and code scroll context,
  i'd love to have the bouncing effect of the scroll removed".
- **Acceptance criteria:**
  1. A card or a single-file pane whose lines fit has no horizontal scroll range, freshly built and after a
     re-render.
  2. The single-file view and the cards' code panes stop at their edges, sideways and vertically, instead of
     rubber-banding. The card list itself keeps its bounce (D25).
- **Priority:** Must. **Related:** CARD-17, DIFF-06.

#### CARD-19 · A pane's scroll range ends where its file does
- **Statement:** Scrolled to its end, a pane stops with its last line at the bottom, with no empty space below it,
  unless scrolling past the end is turned on (SET-09).
- **Source:** 09-24, "there's a bug with the overscroll that creates a lot of empty space below the file that allows
  for more scrolling than necessary".
- **Acceptance criteria:**
  1. With scrolling past the end off, the default, a pane scrolled to its end shows its last line at the bottom, with
     nothing below it but the pane's inset and any band of a gap at the end of the file.
  2. With it on, the last line can scroll up to the top of the pane and no further.
  3. Estimates of lines not yet laid out never add space or cut the range short: once the end has been laid out, the
     range matches the content, in short and long files, wrapped or not, in the single-file view and in the cards.
- **Priority:** Must. **Related:** CARD-17, CARD-18, SET-09.

### DIFF: Diff interaction refinements (roadmap, 09-23)

#### DIFF-01 · Resizable split and stacked panes
- **Statement:** The divider between the old and new panes can be dragged.
- **Source:** 09-23, "being able to drag the pane width when split or stacked diff are shown".
- **Acceptance criteria:** Dragging the divider resizes the panes, and the ratio persists per window.
- **Priority:** Should.

#### DIFF-02 · Gap-expansion drag behaves predictably
- **Statement:** Dragging a gap handle only reveals lines or returns towards its start, keeps revealing at a bounded
  rate at an edge, and a gap between two changes offers a handle on each side.
- **Source:** 09-23, "when dragging the gutter line shower in the opposite direction … it still expands the line …
  holding the dragger to an edge of the view port or view container should continue to disclose lines (not too fast
  though) … we need to show 2 different drag controls, with hover effect". 09-24, "when at the top or the end of a
  file there should be no line other than the dragger and the dragger should stick to the edge, a dragger gap line
  should only be of the size of 1 line, not more, and when there are 2 draggers, the line separation should also be of
  1 line only in total and the separator should run from the gutter to the trailing edge of the file text view,
  draggers should be slightly smaller".
- **Acceptance criteria:**
  1. A drag against the reveal direction never discloses lines.
  2. Holding a handle at an edge keeps revealing at a bounded rate.
  3. A gap between two changes shows two handles with hover feedback.
  4. A gap takes exactly one row, whether it offers one handle or two.
  5. At the top or the end of a file, the lone handle sits flat against that edge, and nothing else is drawn.
  6. Between two changes, the two handles share the row, split by a separator that runs from the gutter to the text
     view's trailing edge.
  7. The handles are small enough that two fit in one row.
- **Priority:** Should. Reference: Xcode's comparison view, images 19 to 21 (DIFF-05). Criteria 4 to 7 are met at
  `bf5ffad` and `e33fa11`.

#### DIFF-03 · A gutter scope ribbon
- **Statement:** The gutter shows scope indicators and fold controls without growing much wider.
- **Source:** 09-23, "provide in the gutter (without much additional or no extra space allocated to it …) a scope
  indicator and control to disclose and collapse to better identify code blocks".
- **Acceptance criteria:**
  1. Hovering a line highlights its enclosing scope.
  2. A scope can be collapsed and disclosed from the gutter.
  3. The gutter's width grows by at most a few points.
- **Priority:** Could. Reference: Xcode's code folding ribbon, images 13 to 18 (DIFF-05).

#### DIFF-04 · A compact inline view
- **Statement:** A setting shows only the newest content, with gutter markers that disclose each change in place.
- **Source:** 09-23, "an inline (not isolated) but compacted view, where we would just show the end result with the
  newest file, but indicating in the gutter the places where there are changes and proposing to disclose the change
  on top … compatible with the isolated change diff mode".
- **Acceptance criteria:**
  1. The view shows the new side only, with a marker per change.
  2. Clicking a marker discloses that addition, removal or modification in place.
  3. It works with the isolated-changes mode.
- **Priority:** Could.

#### DIFF-05 · Xcode as the visual reference for the diff refinements
- **Statement:** The refinements are designed from what Xcode actually shows, captured in a throwaway project and
  kept in the repository.
- **Source:** 09-23 11:53, "(if you open xcode on a project with big enough files that it would need to show the
  dragging control i can give you a screenshot)" and "xcode also propose interesting things in that regard and i
  can send you screenshot of different ways it does it"; 11:55, "create a dummy xcode project with git various
  things, commited, staged, unstaged changes and i'll show you"; 12:00, images 12 to 21; 12:04, "reopen xcode for
  the rename thing please"; 12:05, images 22 and 23.
- **Acceptance criteria:**
  1. A throwaway Xcode project outside the repository holds committed, staged, unstaged, untracked, renamed and
     deleted changes.
  2. The screenshots, and what each shows, are kept in the repository as the reference for DIFF-02 to DIFF-04.
  3. The rename screenshots settle CARD-09's renamed badge.
- **Priority:** Should. **Related:** DIFF-02, DIFF-03, DIFF-04, CARD-09.

#### DIFF-06 · Revealed lines and their handles stay aligned
- **Statement:** Revealing lines with a gap handle never leaves stray drawing, and the gutter, the text rows and the
  handles' separator stay level.
- **Source:** 09-24 13:14 (mid-turn), "sometimes disclosing lines using the gutter handles creates rendering artifacts and line
  misalignment, as well as handlers line separator misalignement".
- **Acceptance criteria:**
  1. After a handle reveals lines, each line number sits on its text row, and nothing drawn before the reveal is left
     behind.
  2. The separator between two handles runs level with the gap row it belongs to.
  3. Both hold in every layout, in the card list and the single-file view, including while the file updates.
- **Priority:** Must. **Related:** DIFF-02, CARD-14.

#### DIFF-07 · A file without a change still shows its content
- **Statement:** While changes are isolated, a file shown on its own that has no changed line, such as a file renamed
  without changes, shows all of its lines instead of an empty pane.
- **Source:** 09-24, "when changes are isolated, some "renamed" files show empty content in single file viewing",
  then (mid-turn) "it might be due to no change happening within the file / then maybe that's normal but imo we should
  still show the content".
- **Acceptance criteria:**
  1. With changes isolated, the single-file view of a file whose two sides have no changed line shows every line, with
     no gap.
  2. A file with a change keeps its isolated hunks and gaps.
  3. The card list is not affected: a card for such a file shows its header alone (D28).
  4. In the card list, that card has no content section at all: no seam, no empty pane, no fold control. It stays
     collapsed and cannot be expanded (R118).
- **Priority:** Must. **Related:** DIFF-02, CARD-09.

#### DIFF-08 · A file opens on its first change, placed right, and the scroll can be turned off
- **Statement:** Opening a file scrolls to its first change, which lands a few lines below the top of the visible
  area and clear of the toolbar and the tab bar; a setting turns the scroll off, so files open at their top.
- **Source:** 09-24, "the auto scrolling to the first change in the file is not working correctly, it's offset, and
  this should be a toggleable behaviour, add that to the roadmap".
- **Acceptance criteria:**
  1. The first change's first row sits three rows below the top of the visible area, never under the toolbar or the
     tab bar, in the inline, side-by-side and stacked layouts, wrapped or not, with the explorers above the diff or in
     the sidebar. A Findings row's reveal, which centres its line, is placed the same way.
  2. A setting, on by default, chooses whether opening a file scrolls to its first change; off, a file opens at its
     top. It sits with the diff settings and in the view options.
  3. A file tab that comes back to where it was left (TAB-10) keeps that position whatever the setting.
  4. A file that fits in the pane whole opens at its top, fully shown, with no scroll to its first change (R118).
- **Priority:** Must (criteria 1 and 4); Should (criteria 2 and 3). **Related:** TAB-10, PERF-10, CARD-17, SET-09.

### REND: A text renderer of our own

#### REND-01 · A measured design for a custom text renderer
- **Statement:** Before building anything, a design measures TextKit 2 against a renderer of our own and says
  whether and how to build it.
- **Source:** 09-23 10:01, "depending on the performances results regarding textkit and rendering (do we use the
  latest iteration of textkit btw?), we could start designing our own text renderer CoreAnimation/CoreText/Metal
  based with a better more convenient API surface and improved rendering speed, …".
- **Acceptance criteria:**
  1. It answers whether the app uses the latest TextKit, with evidence.
  2. It measures TextKit 2 as the app uses it, TextKit 2 used correctly, and a prototype of the new renderer, on
     the same inputs.
  3. It lists what TextKit provides that a replacement must rebuild.
  4. It gives phases with exit criteria and the decisions that gate each phase.
- **Priority:** Should. **Related:** QUAL-08, PERF-09.

#### REND-02 · The renderer's qualities
- **Statement:** The renderer has a typed API, handles UTF-8 and UTF-16 exactly, supports fonts and their features
  fully, is safe under Swift 6.4's strict concurrency, is reusable outside this app, and supports Dynamic Type.
- **Source:** 09-23 10:01, same message: "a better more convenient API surface and improved rendering speed, accuracy
  over utf8 and utf16 full font support as well as full font feature support, strongly typed, swift 6.4 compliant,
  concurrency safe and more usable for a generic project than textkit, supporting dynamictypesupport in swiftui".
- **Acceptance criteria:**
  1. Styles and attributes are Swift types, not attribute dictionaries.
  2. Text is stored as UTF-8, converted to UTF-16 only at platform boundaries, and hit-testing snaps to grapheme
     clusters.
  3. Font fallback, OpenType features, variable axes and color glyphs render.
  4. Its targets build in Swift 6 mode with warnings as errors and no `@unchecked Sendable`.
  5. The engine knows nothing about diffs.
  6. Text size follows Dynamic Type in SwiftUI where the platform scales text.
  7. It renders faster than TextKit 2 used correctly, measured on the same inputs.
- **Priority:** Could: "we could start designing". **Related:** REND-01, REND-03.

#### REND-03 · Pluggable text backends, switchable during development
- **Statement:** The app's architecture lets each window choose TextKit 2 or the new renderer while the new one is
  being built.
- **Source:** 09-23 10:01, same message: "and work on the app architecture to make them plug n play and have both
  rendering be chosable while we're developing the newer one".
- **Acceptance criteria:**
  1. The diff panes draw through one backend seam, with a TextKit 2 backend and the new one behind it.
  2. A developer setting chooses the backend per window.
  3. A parity harness checks that both backends produce the same geometry and content.
- **Priority:** Should. **Related:** REND-02, MOD-02.

### LANG: A file's language

#### LANG-01 · Choosing a file's language
- **Statement:** A file's language comes from its extension today. Two ways to go further were proposed: detecting
  the language from the content, behind a toggle, or a language menu in the status bar for the file shown.
- **Source:** 09-24 12:30 (mid-turn), "autodetection of the language could be a feature that is toggleable or we
  could propose a selection of the language in a dropdown in the status bar".
- **Acceptance criteria:** to settle with the user, who named both options; whichever lands:
  1. Highlighting, hover and diagnostics all follow the language chosen, so no tier reads a file as another
     language (HOVER-19).
  2. With the feature off or no choice made, the extension decides, as it does now.
- **Decision:** 09-24 13:06, "lang-01, we can plan for all the things later": both options are planned later, not
  now (D23).
- **Priority:** Could, planned later. **Related:** HOVER-19.

## Request index

Times are CEST. "Mid-turn" marks a message the user sent while the assistant was working.

| # | Time | Short quotation | Maps to |
|---|---|---|---|
| R01 | 09-21 13:47 | "bring in https://github.com/g-cqd/Atelier's version of it please" | PROC-01 |
| R02 | 09-21 13:47 (mid-turn) | "clean the old ones" | PROC-01 |
| R03 | 09-21 13:48 (mid-turn) | "please update the local toolchain to match" | PROC-02 |
| R04 | 09-21 13:55 | "install the new gitdiffviewer, kill the previous ones and replace and reopen" | PROC-03 |
| R05 | 09-21 13:57 (mid-turn) | "why didnt you clone the whole atelier project" | PROC-01 |
| R06 | 09-21 14:05 | "kill and unstinall the old ones please" | PROC-01 |
| R07 | 09-21 14:06 | "i'd like that you clone atelier and not just gitdiffviewer" | PROC-01 |
| R08 | 09-21 14:08 | "what syntax highlighting do we use in the gitdiffviewer ?" | Question (Atelier's own stack) |
| R09 | 09-21 14:08 (mid-turn) | "is it the one from atelier ?" | Question |
| R10 | 09-21 14:22 | "provide on-hover documentation on the items hovered (this should be a toggleable feature)" | HOVER-01, DIAG-01 to DIAG-05, TOOL-04 |
| R11 | 09-21 14:25 | "we should have dynamic discovery of how the tools are installed" | TOOL-01, TOOL-02 |
| R12 | 09-21 14:27 | "the run of a tool should not be blocking the ui or the app" | PERF-01, PROC-07 |
| R13 | 09-21 14:37 | "review the plan and proposed design under a modern prism" | QUAL-01, PROC-08 |
| R14 | 09-21 15:05 (mid-turn) | "should we move more out of gitdiffviewer into more generic reusable parts" | MOD-01 |
| R15 | 09-21 15:13 | "a design in order to provide hovering for any language" | HOVER-15 |
| R16 | 09-21 15:20 | "we don't necessarily have to bundle things in the app" | TOOL-03, TOOL-02 |
| R17 | 09-21 15:24 | "could you probe speed for the use cases we have in the app regarding json" | JSON-01, JSON-02 |
| R18 | 09-21 15:52 | "add all those insights to the roadmap and go over their implementation" | PROC-06 |
| R19 | 09-21 16:12 (mid-turn) | "mirror things in the g-cqd scope please" | PROC-04 |
| R20 | 09-21 16:21 | "i'd rrather make it straight into main" | PROC-05 |
| R21 | 09-21 16:25 | "offload work from mainactor by using the `@concurrent` decoration" | PERF-02 |
| R22 | 09-21 16:39 | "at the end please install re-sign the app locally" | PROC-03 |
| R23 | 09-21 17:15 | "the warnings seems to be over computed and not respecting the reviewed project configs" | DIAG-06 |
| R24 | 09-21 17:15 (mid-turn) | "for the 2 scopes opened right now you can inspect that" | DIAG-06 |
| R25 | 09-21 17:18 | "lockwood swift format should be implemented and handled" | DIAG-07 |
| R26 | 09-22 10:04 | "research what design principles should be applied to settings screen" (and six more asks) | SET-01, DIAG-08, SET-03, WIN-01, GIT-01, WIN-03, GIT-02, MOD-02, PROC-08 |
| R27 | 09-22 10:12 (mid-turn) | "research how macos and ios natively handle settings" | SET-02 |
| R28 | 09-22 10:21 | "i was not able to make the documentation on hover work" | HOVER-02 |
| R29 | 09-22 10:58 | "i still have no hover, i'd like to be able to have a toolbar element" | HOVER-02, DUI-01, DUI-02, DUI-03, HOVER-14 |
| R30 | 09-22 11:00 | "opens a popover at the top of the text container, not on the line" | DUI-04 |
| R31 | 09-22 11:08 | a pasted crash report (676 lines) | WIN-02 |
| R32 | 09-22 11:21 | "create a custom popover" and "stay fixed/sticky in the view" | HOVER-05, HOVER-06, HOVER-04, CARD-01, CARD-02 |
| R33 | 09-22 11:24 | "utilize the on device xcode documentation, preferably not apple-docs" | HOVER-04, HOVER-17 |
| R34 | 09-22 11:30 (mid-turn) | "[Image #2] this is how it looks for xcode" | HOVER-05 |
| R35 | 09-22 11:30 (mid-turn) | "it does not even adapt to the size of the content" | HOVER-07 |
| R36 | 09-22 13:02 | "triggering recomparison of the whole scope every 2 seconds" | PERF-03 |
| R37 | 09-22 13:03 (mid-turn) | "the doc hovering is not working correctly, no information displayed" | HOVER-02, HOVER-03 |
| R38 | 09-22 13:03 (mid-turn) | "investigate a native tab implementation ideally, as well as not collapsing the viewer" | TAB-01, GIT-03 |
| R39 | 09-22 13:04 (mid-turn) | "the comparison should not discard the already loaded file" | GIT-04 |
| R40 | 09-22 13:35 | "the hover popover should be glassmade" | HOVER-08, HOVER-09, HOVER-03, HOVER-04 |
| R41 | 09-22 14:05 (mid-turn) | "what are the remaining tasks i asked you to work on?" | Status question |
| R42 | 09-22 14:13 | "please go ahead with the implementation" | Approves the remaining-task list: PROC-06, HOVER-16 |
| R43 | 09-22 14:15 | "the hover appears and disappears instantly" | HOVER-10, HOVER-03 |
| R44 | 09-22 14:18 | "[Image #4] that's also not very useful to only have that" | HOVER-04, HOVER-07 |
| R45 | 09-22 14:19 (mid-turn) | "[Image #5]" | HOVER-07 |
| R46 | 09-22 14:19 (mid-turn) | "a lot of negative space, only the signature and not more information" | HOVER-07, HOVER-03 |
| R47 | 09-22 14:27 | "[Image #6] some have duplicated informations somehow" | HOVER-11 |
| R48 | 09-22 14:32 | "trigger a codex cli non-interactive review mode" | QUAL-02 |
| R49 | 09-22 14:39 | "the second part of that might have been overlooked" | CARD-01, CARD-02 |
| R50 | 09-22 14:44 | "why is atelierlsp not leveraging aemijson for the jsonrpc" | JSON-03 |
| R51 | 09-22 15:03 | "use the collapse/expand icon … animate them and symbol transition them" | CARD-08 |
| R52 | 09-22 15:39 | "the section header is being separated from the file content" | CARD-02, CARD-03, CARD-04, SET-04 |
| R53 | 09-22 15:40 | "[Image #7] also sizing and content of hover is still not dynamic" | HOVER-07, HOVER-03, HOVER-06 |
| R54 | 09-22 15:44 | "changes in settings window are not directly reflected in the rendering" | SET-05 |
| R55 | 09-22 16:15 (mid-turn) | "the top file has now more shadow, clipping does not work" | CARD-03, CARD-04, CARD-06 |
| R56 | 09-22 16:19 | "the negative spacing in the hover view is not handled well" | HOVER-07, HOVER-12 |
| R57 | 09-22 16:20 (mid-turn) | "[Image #9]" | HOVER-03, HOVER-07 |
| R58 | 09-22 16:20 (mid-turn) | "the source of the documentation is not really necessary" | HOVER-13, HOVER-18 |
| R59 | 09-22 16:37 | "the colors for the diff badges are different in xcode" (and four more asks) | SET-07, CARD-09, CARD-10, CARD-11, SET-06, SET-08, TAB-02 to TAB-05, TAB-06, CARD-04, CARD-05, CARD-06 |
| R60 | 09-22 16:40 | "when the header is not sticky, it seems it is not laid out with the file content" | CARD-04 |
| R61 | 09-22 16:41 | "collapsing one file removes the gap space" | CARD-07 |
| R62 | 09-22 16:47 | "the hovering creates a big overhead in resources" | PERF-04 |
| R63 | 09-22 16:48 | "the scroll is very slow and sluggish on the file list" | PERF-05 |
| R64 | 09-22 16:53 | "we render 2 material layer per file headers" | PERF-06 |
| R65 | 09-22 17:01 | "the whole computer becomes super laggy" | PERF-07 |
| R66 | 09-23 07:46 | "continue" | Resumes the session |
| R67 | 09-23 07:52 | "stripping all the verbose comments all over the codebase" | QUAL-03 |
| R68 | 09-23 07:59 | "draw requirement plan and book, and then audit the codebase" | QUAL-04, QUAL-05, QUAL-07, PERF-08, PROC-08 |
| R69 | 09-23 07:47 | "update the model for all agents to be opus in the global agents definition files" | Out of scope (second session) |
| R70 | 09-23 07:49 | "the opus should be 5.5" | Out of scope (second session) |
| R71 | 09-23 09:05 | "go completely custom … the clipping, sticking and scrolling right" | CARD-12 |
| R72 | 09-23 09:10 (mid-turn) | "if unstaged … stroke and text should be white" | CARD-10 |
| R73 | 09-23 09:10 (mid-turn) | "reuse the backdrop effect beneath them … capsule shape … a pin symbol" | TAB-08, TAB-09 |
| R74 | 09-23 09:15 (mid-turn) | "micro optimizations towards improving rendering speed across gui/tui" | PERF-09, QUAL-08 |
| R75 | 09-23 09:37 | "tab hovering background could be lighter" (and the answers to Q1-Q5) | TAB-07, TAB-08, SET-03, HOVER-08, CARD-09, DIAG-08 |
| R76 | 09-23 11:42 (mid-turn) | "when collapsing the background is darker grayish" | CARD-13 |
| R77 | 09-23 11:42 | "when using another layout than the inline, scroll … is buggy" | CARD-14 |
| R78 | 09-23 11:43 | "split layout, plus expanding a file completely erases the scrollview content" | CARD-14 |
| R79 | 09-23 11:44 (mid-turn) | "file list cards should only support inline or horizontal split" | CARD-15 |
| R80 | 09-23 11:53 | "i'd like that you add to the roadmap a few refinements" | DIFF-01 to DIFF-04 |
| R81 | 09-21 14:30 (decision D1, missed by the first pass) | "everything, incremental, atomic, fully tested, split in both parallel and sequential tracks" | PROC-09 |
| R82 | 09-21 14:30 (decision D2, missed by the first pass) | "Bundle + discovery" | TOOL-04 |
| R83 | 09-21 14:45 (decision D3, missed by the first pass) | the plan is approved | PROC-07 |
| R84 | 09-23 09:03 | "continue" | Resumes the session after a network outage |
| R85 | 09-23 09:41 | "the gdv card review app does exactly what i want, but the scrolling is so sluggish" | CARD-12, PERF-05 |
| R86 | 09-23 10:01 | "we could start designing our own text renderer CoreAnimation/CoreText/Metal based" (and "do we use the latest iteration of textkit btw?") | REND-01, REND-02, REND-03 |
| R87 | 09-23 10:11 | "please reinstall and re-sign the current version of the release app" | PROC-03 |
| R88 | 09-23 10:26 | "staged/tracked (and i guess that includes committed files) should have filled background variant" | CARD-11, CARD-09 |
| R89 | 09-23 10:42 | a pasted crash report (573 lines): use-after-free in the file watcher | GIT-05 |
| R90 | 09-23 10:50 (mid-turn) | "please clean all temporary files and project, we're running out of space" | PROC-10 |
| R91 | 09-23 11:36 | "the white badge variant in the side bar file list/trees is not working" | CARD-10 |
| R92 | 09-23 11:37 (mid-turn) | "btw the file headers in the list don'T match the badge color scheme tint" | SET-07 |
| R93 | 09-23 11:55 | "create a dummy xcode project with git various things, commited, staged, unstaged changes and i'll show you" | DIFF-05 |
| R94 | 09-23 12:00 | images 12 to 21 (Xcode's inline change, fold ribbon and gap handles) | DIFF-05, DIFF-02, DIFF-03 |
| R95 | 09-23 12:04 | "reopen xcode for the rename thing please" | DIFF-05, CARD-09 |
| R96 | 09-23 12:05 | images 22 and 23 (Xcode's renamed row) | CARD-09, CARD-10 |
| R97 | 09-23 12:05 (mid-turn) | "i'd prefer we use R for renamed though" | CARD-09 |
| R98 | 09-23 12:06 | "so it's clearer than an M that means the same thing than the other files" | CARD-09 |
| R99 | 09-23 12:06 | a pasted crash report (592 lines): NaN view geometry in the fold review build | CARD-16, CARD-14 |
| R100 | 09-23 12:34 (decisions D4 to D7) | "Start Wave 1 now", "Mirror into g-cqd", "Patch now", "Prompt on first hover" | PROC-11, PROC-12, QUAL-09, QUAL-07 |
| R101 | 09-23 12:37 (decision D8) | "End it now (Recommended)" | PROC-10 |
| R102 | 09-23 13:06 | "can you make sure we use aemijson whenever we do json interaction" | JSON-04 |
| R103 | 09-23 13:29 | "please perform a regathering of all prompts and requirements" | QUAL-10 |
| R104 | 09-24 12:27 (mid-turn) | a pasted crash report: a stack overflow in swift-syntax's parser under the doc-comment hover | HOVER-19 |
| R105 | 09-24 12:30 (mid-turn) | "the swift parser and swift syntax should fail fast and only parse swift files" | HOVER-19, LANG-01 |
| R106 | 09-24 13:06 | "if it does not override the private skills go ahead for the install, don't push to the public one but create a mirror on my g-cqd please" | PROC-12 (skills repository), D23 |
| R107 | 09-24 13:14 (mid-turn) | "sometimes disclosing lines using the gutter handles creates rendering artifacts and line misalignment" | DIFF-06, CARD-17, PERF-10, TAB-10 |
| R108 | 09-24 13:44 (mid-turn, to an agent) | "inspect why sometimes the horizontal scroll is possible when the file width actually matches or fits the containers" | CARD-18 |
| R109 | 09-24 14:57 | "the oldest one is ours, the others are xcode ones, we should improve" (images 28 to 33) | HOVER-20 |
| R110 | 09-24 | "let's just show the signature" when the only information about a variable is the variable itself | HOVER-20 (criterion 6), HOVER-03 (criterion 4 superseded) |
| R111 | 09-24 | "1. no 2. no 3. keep 4. reassess and reorder, maybe use work to prioritize even" | D24 to D27 |
| R112 | 09-24 | "i'd like the popover of the documentation to be able to stay visible when mousing hover it" | HOVER-20 (criterion 7) |
| R113 | 09-24 | "when changes are isolated, some "renamed" files show empty content in single file viewing"; "imo we should still show the content" | DIFF-07 |
| R114 | 09-24 | "header only in the file list" | D28, DIFF-07 |
| R115 | 09-24 | "sometimes, double clicking a file or selecting it in the file list opens it in a completely unscrollable state, it can be for a small or big file, i'm completely unable to scroll" | CARD-17 (criterion 5) |
| R116 | 09-24 | "the auto scrolling to the first change in the file is not working correctly, it's offset, and this should be a toggleable behaviour, add that to the roadmap" | DIFF-08 |
| R117 | 09-24 | "there's a bug with the overscroll that creates a lot of empty space below the file that allows for more scrolling than necessary, the bouncing of scroll (and the fact we disabled it) should be a setting" | CARD-19, SET-09 |
| R118 | 09-24 | "when a file fits in the view, we should not scroll to the first change, we should just display the file fully, and in the card list, a renamed file without change should not change a file content section (be collapsed and not expandable)" | DIFF-08 (criterion 4), DIFF-07 (criterion 4) |
| R119 | 09-25 | "does the git diffviewer use the grammar parser we use in kitty?" (answered: no, it highlights with the shared lexers and swift-syntax) | — |
| R120 | 09-25 | "i'd like that we investigate ways to improve the one flat sidebar file list, by having a toggleable setting to group through disclosable section diffed files by commit when the 2 compared repo states share the same ancestry, it can only work in flat sidebar, for repos" | GIT-06 |
| R121 | 09-25 | "imo, the highlighting should be a tiered job, lexer and grammar started in parallel, swift syntax and sourcekit when enabled, used to also enrich the color syntaxing ideally and provide more information at that moment as well" | PERF-11 |
| R122 | 09-25 | "i'd prefer that you cancel the work you started on kitty code, what has priority to me is core shared code or gitdiffviewer relevant improvement, reschedule the roadmap accordingly please" | D37 |
| R123 | 09-25 | "the agents seem to be waiting a lot again, inspect that please" | PROC-13; exclusive jobs drained the machine (the quiet-window change in the work tool) |
| R124 | 09-25 (mid-turn) | "for future work, we need to stop building and building and increment building every 2 minutes and check build against 10 different combinations of things" | D40 |
| R125 | 09-25 (mid-turn) | "also, when an agent goes back to you it has already build-tested the result" and "also, i'm not convinced by the usage of worktrees at scale" | D40 |
| R126 | 09-25 (mid-turn) | "please maybe refine the skills guidance across the whole skillset to refine a bit further how to handle all of that" | D40 |
| R127 | 09-25 | "i'd prefer that you cancel the one you just started please, and that you gives me the whole list of things we have yet to do" | The grammar table work (queue item 8) stopped before any change |
| R128 | 09-25 | "the gitdiffviewer ui and ux topics related to the gutter, and the rendering and hover work are right now what i would prioritize, i was not expecting you to do the commit grouping stuff now and now it's not working very well, i'd like that when using grouping the diff happens against the previous commit state so we should always have the net difference between 2 commits not a weird sum" | D38, D39, GIT-06 criterion 5 |
