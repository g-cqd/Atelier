# Settings design: research grounding and redesign

Derived from HCI literature and an audit of the current Settings window (2026-09).
Principles P1–P10 cited inline; full sources at the end.

## Principles (evidence level noted)

- **P1 Cognitive load** (Sweller): cut *extraneous* load (presentation) before cutting options.
  A screen repeating the same 3-row block eight times is the problem, not the option count. [strong]
- **P2 Hick–Hyman**: applies to *predictably ordered* lists; unordered walls are scanned linearly.
  Grouping and ordering by frequency beat deletion. [strong, conditional]
- **P3 Fitts**: full-row targets; Reset adjacent to what it resets; paired controls adjacent. [strong]
- **P4 Chunking**: working memory ~4 chunks (Cowan); 7±2 is a myth for visible UI (recognition,
  not recall). Keep *sections* graspable (3–5 items); don't cap tabs by folklore. [refined consensus]
- **P5 Progressive disclosure** (NN/g): few important options first; specialized ones on request. [strong]
- **P6 Defaults** (Johnson & Goldstein, Science 2003): most users keep defaults; the default *is*
  the recommendation. Make deviation visible and reversal one click. [strong]
- **P7 Choice overload**: mean effect ~0 across studies (Scheibehenne 2010); appears under
  moderators (Chernev 2015): set complexity, decision difficulty, preference uncertainty,
  effort-minimization — settings screens hit three of four. Reduce *complexity* (jargon,
  comparability) at least as much as count. [nuanced]
- **P8 HIG Settings**: general/infrequent → Settings window; task-specific → the view it affects;
  fixed-size window, toolbar pane switcher, restore last pane. [platform expectation]
- **P9 "Avoid preferences"** (37signals) + counterpoint: bar for a setting = "do users' correct
  answers differ?", not "couldn't we decide?". Expert diff tool ⇒ real divergence exists. [opinion]
- **P10 Practice**: search once counts hit dozens; reset affordances enable safe exploration;
  sentence captions carry explanation; friction on trust-sensitive settings (running discovered
  binaries). [convergent practice]

## Audit verdicts

- Right already: 4 tabs, grouped forms, captions (mostly), per-path Reset, status dots.
- **A1** Tab boundaries follow implementation, not user questions (layout settings across 3 tabs;
  "Algorithm" section named after internals, jargon labels, and the one section with NO captions).
- **A2** ~12 settings are view-scope per HIG and already live in ViewOptionsMenu/toolbar — Settings
  duplicates them 1:1; the window's role needs sharpening.
- **A3** Labels diverge across the three surfaces ("Sync scroll" vs "Keep split panes scrolled
  together") — pure extraneous load; prerequisite fix before per-project overrides.
- **A4** Tools tab: 8 sections × identical 3-row scaffolding ≈ 24 near-identical rows; path row is
  rare-use (disclosure miss); everything visible while master toggle is off.
- **A5** Missing: restore-defaults, deviation indicators, first-enable trust note; search not yet
  warranted (~29 settings) but will be with per-project scopes.

## Redesign (prioritized)

- **R1** Tools tab → one list, one summary row per tool (dot + name + toggle + status);
  DisclosureGroup reveals path/Locate/Reset; auto-expand pinned-broken; dim when master off.
- **R2** Rebalance tabs around questions, same count: General (window & files, 8 controls),
  Diff → sections "What's compared / Matching" with heuristics behind an "Advanced matching"
  disclosure + captions, Appearance (text look incl. wrap), Tools (R1). Each tab 4–9 controls.
- **R3** One canonical label per setting across Settings/View menu/toolbar.
- **R4** "Restore Defaults" per tab + subtle differs-from-default indicator.
- **R5** Per-project overrides: Settings window stays app defaults; the comparison window's View
  options become the per-project surface (writes to a project scope keyed by repo identity);
  Settings gains one "overridden in N projects — review…" affordance per tab. Overridable set
  limited to genuinely project-varying settings (whitespace, heuristics, granularity, ignored
  files, tool enablement, analyzed sides).
- **R6** Captions on the 5 heuristic toggles; one-sentence trust note on first diagnostics enable;
  defer search until scopes double the surface.

Sources: Sweller 2010 · Cowan 2001 (BBS) · MacKenzie 1992 · Johnson & Goldstein 2003 (Science
302:1338) · Scheibehenne et al. 2010 · Chernev et al. 2015 (JCP) · NN/g progressive disclosure &
Hick's-law-for-menus · Apple HIG Settings · archived Android settings pattern · 37signals Getting
Real + Shah counterpoint · UX Myths #23.
