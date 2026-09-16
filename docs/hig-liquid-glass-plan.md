# HIG and Liquid Glass review

Reviewed against Apple's "Adopting Liquid Glass" technology overview and the Human Interface Guidelines for
toolbars and sidebars (macOS 26 SDK). The app requires macOS 26.1, so every Liquid Glass API is used directly, without
availability checks.

## Where we stand

| Area | Guideline | Today | Gap |
|---|---|---|---|
| Window title | Don't title windows with the app name; title the content, under 15 characters | "Git Diff Viewer" | Title should name the comparison or the open file |
| Toolbar groups | At most three groups; leading = navigation, centre = common controls, trailing = important items, search, More | Three groups, but the trailing one holds five items | Trim trailing to layout + options; move change navigation into the centre or a Go menu |
| Toolbar items | Symbols over text, no bezels, every item also a menu-bar command, fixed spacers between text items | Native pull-downs with spacers; only Open Patch is in the menu bar | Add View and Go menus mirroring every toolbar action |
| Custom bars | Reduce custom backgrounds; let the system draw bars; use scroll edge effects where content scrolls beneath | Soft scroll edge effect on the card list and the sidebar; tab bar and status bar still draw `.bar`; no background extension under the sidebar (a text pane gains nothing from it, and it was dropped after a crash inside SwiftUI layout) | Drop custom backgrounds; the AppKit panes start below the tab bar, so they need no edge effect |
| Sidebar | Use split views so the sidebar floats in the glass layer, can hide, auto-collapses, extends content beneath | `NavigationSplitView` for the sidebar placements, toolbar toggle, View ▸ Show/Hide Sidebar (⌃⌘S), visibility persisted | Done |
| Sidebar content | Disclosure controls, familiar symbols, accent-coloured icons, two levels max | `NSOutlineView` explorer: native disclosure and selection, arrow keys, type-select, return pins | Done |
| Search | Trailing-edge search field for navigation | None | `.searchable` filtering the explorers by name |
| Controls | Standard sizes and shapes, concentric corners, no hard-coded metrics | Cards with 10pt corners, custom tab pills | Concentric shapes for cards and tabs |
| Menus | Standard selectors get standard icons; context-menu order matches primary actions | Custom native menus without icons | Add symbols to menu items |
| Settings | Grouped forms, title-case headers | Tabbed Settings (General, Diff, Appearance), each a scrolling grouped form in a fixed-size window | Done |
| App icon | Layered icon composed in Icon Composer | None | Create one |
| Accessibility | Labels on every symbol; test Reduce Transparency, Increase Contrast, Reduce Motion | Buttons carry titles | Audit representables (pull-downs, gutter, tabs) and the palette under Increase Contrast |

## Plan

1. **Chrome and commands (small).** Window title from the comparison ("snackbar: develop ↔ feature/…", or the
   open file); View menu (Inline ⌘1, Side by Side ⌘2, Stacked ⌘3, Isolate Changes ⌘4, Wrap Lines, Minimap, Status
   Bar, explorer placement) and Go menu (Next/Previous Change, Next/Previous File) so no toolbar item is the only
   way to a command; trailing group reduced to layout and view options; `ToolbarSpacer` between text items.
2. **Sidebar placements on `NavigationSplitView` (medium, done).** Sidebar and unified-sidebar placements become a real
   sidebar column with the system toggle, automatic collapse on narrow windows, and Show/Hide Sidebar commands.
   The explorer gets keyboard navigation back through an `NSOutlineView`-backed representable (arrow keys,
   type-select, native selection), which also restores accent-coloured selection.
3. **Search (small).** `.searchable` in the trailing group filtering the explorer trees by file name; ⌘F focuses it.
4. **Scroll edge effects and backgrounds (small).** Cards and panes register a soft scroll edge effect under the
   toolbar; the tab bar and status bar lose their custom `.bar` fills and take the window background, with the
   tabs grouped in a `GlassEffectContainer` on macOS 26 only if they read as navigation, not decoration.
5. **Shapes (small).** Cards and tabs use concentric corner radii relative to the window; hover and selection
   states come from the system where a standard control exists.
6. **Settings (small, done).** Tabbed Settings: General (explorers, status bar), Diff (heuristics, whitespace,
   granularity, context lines), Appearance (theme, line height, wrap column).
7. **App icon (small).** A layered icon built in Icon Composer with the standard grid.
8. **Verification.** Light and dark, Reduce Transparency, Increase Contrast, Reduce Motion, VoiceOver labels on
   the native controls, and window widths down to the minimum for overflow behaviour.

Items 1, 3, 4 and 6 are independent; 2 is the largest and the one that changes structure; 5 and 7 are polish.
