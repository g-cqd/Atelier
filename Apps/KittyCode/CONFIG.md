# KittyCode Configuration

KittyCode reads its configuration from `~/.kittycode.json` on launch. All fields are optional — omitted fields use their default values. The file is watched for changes and hot-reloaded automatically.

## Top-Level Options

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `keybindingMode` | `"nano"` \| `"vim"` \| `"kittycode"` | `"nano"` | Keyboard shortcut scheme. Nano uses Ctrl-based shortcuts; Vim uses modal editing; KittyCode uses a custom scheme. |
| `treeWidth` | `int` | `30` | Width of the file tree sidebar in columns. Clamped to half the terminal width. |
| `useSFSymbolsInTerminal` | `bool` | `true` | Use SF Symbol glyphs for file/folder icons when the terminal supports them. |
| `fileWatcherEnabled` | `bool` | `true` | Watch open files for external changes and prompt for reload. |
| `sidebarOverflowMode` | `"truncateEnd"` \| `"marquee"` | `"truncateEnd"` | How long file names are displayed in the sidebar when they overflow the panel width. `"truncateEnd"` shows `...` + the end of the name for the selected row. `"marquee"` scrolls the selected row's text continuously. |

## Editor (`editor`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `editor.highlightCurrentLine` | `bool` | `false` | Highlight the line containing the cursor across the full editor width. |
| `editor.arrowKeysWrapAcrossLines` | `bool` | `true` | Let left/right arrow keys move to the previous/next line at line boundaries. |
| `editor.wrapLines` | `bool` | `false` | Wrap long lines instead of horizontal scrolling. |
| `editor.tabSize` | `int` | `4` | Number of columns per tab stop. |
| `editor.undoCoalescingEnabled` | `bool` | `true` | Merge consecutive edits of the same kind (typing, deleting) into a single undo step. |
| `editor.undoCoalescingMilliseconds` | `int` | `400` | Time window for coalescing consecutive edits into one undo step. |
| `editor.scrollLines` | `int?` | `null` | Lines per scroll-wheel tick. When `null`, vertical scrolling defaults to 1 line per event. |
| `editor.scrollHorizontalStep` | `int` | `4` | Columns per horizontal scroll tick (Shift+scroll or trackpad horizontal). |
| `editor.scrollMomentumBlockMilliseconds` | `int` | `5` | Brief rebound-block window after reversing scroll direction. Set to `0` to disable it. |
| `editor.scrollAccelerationEnabled` | `bool` | `true` | Enable burst-rate acceleration for vertical 1-line scrolling. |
| `editor.scrollAccelerationWindowMilliseconds` | `int` | `120` | Time window used to count same-direction scroll bursts. |
| `editor.scrollAccelerationStepIntervalMilliseconds` | `int` | `1` | Delay between queued accelerated 1-line steps. |
| `editor.scrollAccelerationMaxExtraLines` | `int` | `8` | Maximum extra 1-line steps queued from a single burst event. |
| `editor.keyRepeatIntervalMilliseconds` | `int` | `40` | Minimum interval between processed key-repeat events for navigation commands (arrow keys, j/k, tree up/down). Prevents perceived page jumps from high terminal key-repeat rates. Set to `0` to disable throttling. |
| `editor.maxUndoSteps` | `int` | `200` | Maximum undo history entries per buffer. |
| `editor.maxTreeUndoSteps` | `int` | `50` | Maximum undo history entries for file tree operations (create, rename, delete, etc.). |
| `editor.snapshotMaxFiles` | `int` | `500` | Maximum number of files to include in workspace snapshots. |
| `editor.snapshotMaxBytes` | `int` | `10000000` | Maximum total byte count for workspace snapshots. |

## Tab Ribbon (`tabRibbon`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `tabRibbon.position` | `"top"` \| `"hidden"` | `"top"` | Position of the tab ribbon. `"hidden"` disables the tab bar entirely. |
| `tabRibbon.persistence` | `"pinned"` \| `"preview"` | `"pinned"` | How new file tabs behave. `"pinned"` keeps all opened files as permanent tabs. `"preview"` opens files as a single preview tab that gets replaced by the next file opened; editing or double-clicking a tree entry pins the tab. |

## Syntax Highlighting (`syntax`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `syntax.enabled` | `bool` | `true` | Enable Tree-sitter-based syntax highlighting. |
| `syntax.disabledLanguages` | `[string]` | `[]` | Language identifiers to exclude from highlighting (e.g. `["python", "ruby"]`). |
| `syntax.xcodeTheme` | `string` | unset | Path of an Xcode `.xccolortheme` (`~` allowed) whose syntax colours replace the `theme.*Foreground` syntax colours. |

## Auto-Save (`autoSave`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `autoSave.enabled` | `bool` | `false` | Automatically save dirty buffers on a timer. |
| `autoSave.interval` | `number` | `30` | Seconds between auto-save checks. |

## Git Integration (`git`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `git.enabled` | `bool` | `true` | Enable git integration (status indicators, branch info, line decorations). |
| `git.refreshInterval` | `number` | `10` | Seconds between background git status refreshes. |

### Git Decorations (`git.decorations`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `git.decorations.showLineChanges` | `bool` | `true` | Show `+`/`~`/`-` gutter symbols for changed lines. |
| `git.decorations.showLineBackgrounds` | `bool` | `false` | Tint changed lines using per-status background overlays. |
| `git.decorations.showLineForegrounds` | `bool` | `false` | Tint changed lines using per-status foreground overlays. |
| `git.decorations.showTabRibbonStatus` | `bool` | `true` | Show git status color on tab labels. |
| `git.decorations.showOpenFilesStatus` | `bool` | `true` | Show git status color in the open files panel. |
| `git.decorations.lineChangeDebounceMilliseconds` | `int` | `150` | Debounce delay before recomputing line-level git decorations after edits. |
| `git.decorations.maxLineDiffBytes` | `int` | `1000000` | Skip line-level git diff for files larger than this byte count. |

## Status Bar (`statusBar`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `statusBar.show` | `bool` | `true` | Show the status bar at the bottom of the editor. |
| `statusBar.leftItems` | `[item]` | `["path", "status"]` | Segments shown on the left side of the status bar. |
| `statusBar.rightItems` | `[item]` | `["visibility", "language", "size", "lineEnding", "git", "position"]` | Segments shown on the right side. |
| `statusBar.showContextHints` | `bool` | `true` | Show contextual keyboard hints in the status bar. |

Available status bar items: `path`, `file`, `status`, `language`, `size`, `lineEnding`, `git`, `position`, `visibility`, `undo`.

## Activity Bar (`activityBar`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `activityBar.show` | `bool` | `true` | Show the activity bar on the left side of the editor. |
| `activityBar.position` | `"left"` \| `"right"` | `"left"` | Position of the activity bar. |
| `activityBar.items` | `[string]` | `["explorer", "openDocuments", "search"]` | Sidebar panels, in display order. |

## Keybindings (`keybindings`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `keybindings.tabNext` | `string` | `"ctrl+pagedown"` | Key combo to switch to the next tab. |
| `keybindings.tabPrev` | `string` | `"ctrl+pageup"` | Key combo to switch to the previous tab. |
| `keybindings.tabClose` | `string?` | `null` | Optional key combo to close the current tab. |
| `keybindings.toggleSidebar` | `string` | `"ctrl+b"` | Key combo to toggle the sidebar. |
| `keybindings.clipboardModifier` | `"command"` \| `"control"` \| `"both"` | `"command"` | Modifier family for copy/cut/paste shortcuts (`C`, `X`, `V`). |
| `keybindings.historyModifier` | `"command"` \| `"control"` \| `"both"` | `"command"` | Modifier family for undo/redo shortcuts (`Z`, `Y`, and `Shift+Z` for redo). |

## Whitespace Rendering (`whitespace`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `whitespace.showIndentation` | `bool` | `false` | Show `·` for leading spaces and `→` for leading tabs. |
| `whitespace.showSpaces` | `bool` | `false` | Show `·` for mid-line and trailing spaces. |
| `whitespace.showLineBreaks` | `bool` | `false` | Show `¶` at the end of each line. |
| `whitespace.showUnexpected` | `bool` | `true` | Show `⌀` for non-breaking spaces, zero-width spaces, and other invisible characters. |
| `whitespace.selectionWhitespace` | `string` | `"none"` | Show invisible characters inside selected text. Values: `"none"`, `"indentation"`, `"all"`, `"boundary"`. |

### `selectionWhitespace` values

| Value | What is revealed in the selection |
|-------|-----------------------------------|
| `"none"` | Nothing extra (default). |
| `"indentation"` | Leading spaces (`·`) and tabs (`→`). |
| `"all"` | Indentation + mid-line/trailing spaces. |
| `"boundary"` | Indentation + spaces + line-break markers (`¶`). |

## Search (`search`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `search.defaultTarget` | `string` | `"currentFile"` | Default search scope when opening the search panel. |
| `search.includeHiddenByDefault` | `bool` | `false` | Include hidden files in workspace searches by default. |
| `search.includeGitIgnoredByDefault` | `bool` | `false` | Include git-ignored files in workspace searches by default. |
| `search.caseSensitiveByDefault` | `bool` | `false` | Default case sensitivity for search queries. |
| `search.regexByDefault` | `bool` | `false` | Default regex mode for search queries. |
| `search.excludeGlobs` | `[string]` | `["**/.git/**", "**/build/**", "**/.build/**"]` | Glob patterns to exclude from workspace searches. |
| `search.maxResults` | `int` | `5000` | Maximum number of match results returned by workspace search. |
| `search.debounceMilliseconds` | `int` | `150` | Debounce delay before triggering a workspace search after typing. |

## Theme Colors (`theme`)

All color values are CSS-style hex strings. Two formats are supported:

- **`#rrggbb`** — opaque color (alpha defaults to `ff`). Example: `"#c9d1d9"`
- **`#rrggbbaa`** — color with alpha channel. Example: `"#e3b3412e"` (the last two hex digits encode alpha, where `00` = fully transparent and `ff` = fully opaque)

Alpha is meaningful for **git line overlay** colors, where it controls the blending intensity. For all other theme colors (foreground, background, syntax, etc.), the alpha component is accepted but has no visual effect because terminal SGR attributes do not support transparency.

For git line overlays, both notations are equivalent:
```json
"gitModifiedLineBackground": "#e3b3412e"
"gitModifiedLineBackground": { "color": "#e3b341", "alpha": 0.18 }
```

All theme fields are optional — omitted fields use their default values.

> **Tip:** On GitHub, the hex color codes below display with a visual color swatch.

### Core UI

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.editorForeground` | `#c9d1d9` | Editor text color |
| `theme.lineNumberForeground` | `#8b949e` | Line number gutter color |
| `theme.treePanelForeground` | `#c9d1d9` | File tree text color |
| `theme.treeSelectedForeground` | `#58a6ff` | Selected tree item color |
| `theme.treeDirectoryForeground` | `#7ee787` | Directory name color |
| `theme.statusBarForeground` | `#79c0ff` | Status bar text color |
| `theme.titleBarForeground` | `#f0f6fc` | Title bar text color |
| `theme.separatorForeground` | `#30363d` | Panel separator color |

### Syntax Highlighting

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.keywordForeground` | `#ff7b72` | Keywords (`if`, `let`, `func`, etc.) |
| `theme.typeForeground` | `#79c0ff` | Type names |
| `theme.commentForeground` | `#8b949e` | Comments |
| `theme.stringForeground` | `#a5d6ff` | String literals |
| `theme.numberForeground` | `#79c0ff` | Numeric literals |
| `theme.attributeForeground` | `#d2a8ff` | Attributes, properties, function names |

### Editor Line Highlighting

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.cursorLineBackground` | — | Full-width cursor-line background color |
| `theme.cursorLineForeground` | — | Full-width cursor-line foreground color |

### Selection

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.selectionBackground` | `#264f78` | Background color for selected text |
| `theme.selectionForeground` | — | Foreground color for selected text |

### Search Highlighting

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.searchMatchBackground` | `#3a3d41` | Background for non-active search matches |
| `theme.searchMatchForeground` | — | Foreground for non-active search matches |
| `theme.activeSearchMatchBackground` | `#614f0e` | Background for the active (current) search match |
| `theme.activeSearchMatchForeground` | `#ffffff` | Foreground for the active search match |

### Command Feedback

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.commandFeedbackForeground` | `#8b949e` | Foreground for the command feedback indicator in the status bar |
| `theme.commandFeedbackBackground` | — | Background for the command feedback indicator |

### Git File Status

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.gitModifiedForeground` | `#e3b341` | Modified files |
| `theme.gitAddedForeground` | `#3fb950` | Added files |
| `theme.gitUntrackedForeground` | `#8b949e` | Untracked files |
| `theme.gitDeletedForeground` | `#f85149` | Deleted files |
| `theme.gitConflictedForeground` | `#ff7b72` | Conflicted files |

### Git Line Highlighting

These overlay fields use alpha blending. Accepts `"#rrggbbaa"` hex or the object form `{ "color": "#rrggbb", "alpha": 0.18 }`. Defaults are derived from the corresponding git file status color.

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.gitModifiedLineBackground` | `#e3b3412e` | Modified-line background overlay (18% opacity) |
| `theme.gitModifiedLineForeground` | `#e3b34173` | Modified-line foreground overlay (45% opacity) |
| `theme.gitAddedLineBackground` | `#3fb9502e` | Added-line background overlay (18% opacity) |
| `theme.gitAddedLineForeground` | `#3fb95073` | Added-line foreground overlay (45% opacity) |
| `theme.gitUntrackedLineBackground` | `#8b949e2e` | Untracked-line background overlay (18% opacity) |
| `theme.gitUntrackedLineForeground` | `#8b949e73` | Untracked-line foreground overlay (45% opacity) |
| `theme.gitDeletedLineBackground` | `#f851492e` | Deleted-line background overlay (18% opacity) |
| `theme.gitDeletedLineForeground` | `#f8514973` | Deleted-line foreground overlay (45% opacity) |
| `theme.gitConflictedLineBackground` | `#ff7b722e` | Conflicted-line background overlay (18% opacity) |
| `theme.gitConflictedLineForeground` | `#ff7b7273` | Conflicted-line foreground overlay (45% opacity) |

### Tab Ribbon

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.tabActiveBackground` | — | Active tab background |
| `theme.tabActiveForeground` | — | Active tab text color |
| `theme.tabInactiveBackground` | — | Inactive tab background |
| `theme.tabInactiveForeground` | — | Inactive tab text color |
| `theme.tabDirtyIndicator` | — | Dirty indicator color |

### Activity Bar

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.activityBarBackground` | — | Activity bar background |
| `theme.activityBarForeground` | — | Activity bar icon color |
| `theme.activityBarActiveForeground` | — | Active panel icon color |

### Open Files Panel

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.openFilesForeground` | — | Open files list text color |
| `theme.openFilesSelectedForeground` | — | Selected file text color |

### Whitespace

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.whitespaceIndentationForeground` | `#484f58` | Color for indentation markers |
| `theme.whitespaceSpaceForeground` | `#484f58` | Color for space markers |
| `theme.whitespaceLineBreakForeground` | `#484f58` | Color for line break markers |
| `theme.whitespaceUnexpectedForeground` | `#ff7b72` | Color for unexpected invisible characters |

## Built-in Keyboard Shortcuts

These are hardcoded and not configurable via JSON.

| Shortcut | Mode | Action |
|----------|------|--------|
| `Ctrl+O` | Any | Save current file |
| `Ctrl+N` | Any | Create new untitled buffer |
| `Ctrl+X` | Editor | Switch to tree mode / Quit (from tree mode) |
| `Ctrl+B` | Any | Toggle sidebar |
| `Ctrl+W` | Nano | Close current tab |
| `Ctrl+H` | Any | Cycle file visibility (Default -> Git-filtered -> All) |
| `Ctrl+PageDown` | Any | Next tab |
| `Ctrl+PageUp` | Any | Previous tab |
| `Escape` | Editor (Nano) | Switch to tree mode |
| `Escape` | Editor (Vim) | Enter normal mode |

## Complete Example

```json
{
  "keybindingMode": "vim",
  "treeWidth": 35,
  "useSFSymbolsInTerminal": true,
  "fileWatcherEnabled": true,
  "sidebarOverflowMode": "truncateEnd",
  "editor": {
    "highlightCurrentLine": true,
    "arrowKeysWrapAcrossLines": true,
    "wrapLines": false,
    "tabSize": 4,
    "undoCoalescingEnabled": true,
    "undoCoalescingMilliseconds": 400,
    "scrollLines": null,
    "scrollHorizontalStep": 4,
    "scrollMomentumBlockMilliseconds": 5,
    "scrollAccelerationEnabled": true,
    "scrollAccelerationWindowMilliseconds": 120,
    "scrollAccelerationStepIntervalMilliseconds": 1,
    "scrollAccelerationMaxExtraLines": 8,
    "keyRepeatIntervalMilliseconds": 40,
    "maxUndoSteps": 200,
    "maxTreeUndoSteps": 50,
    "snapshotMaxFiles": 500,
    "snapshotMaxBytes": 10000000
  },
  "syntax": {
    "enabled": true,
    "disabledLanguages": []
  },
  "tabRibbon": {
    "position": "top",
    "persistence": "pinned"
  },
  "autoSave": {
    "enabled": false,
    "interval": 30
  },
  "git": {
    "enabled": true,
    "refreshInterval": 10,
    "decorations": {
      "showLineChanges": true,
      "showLineBackgrounds": true,
      "showLineForegrounds": false,
      "showTabRibbonStatus": true,
      "showOpenFilesStatus": true,
      "lineChangeDebounceMilliseconds": 150,
      "maxLineDiffBytes": 1000000
    }
  },
  "statusBar": {
    "show": true,
    "leftItems": ["path", "status"],
    "rightItems": ["visibility", "language", "size", "lineEnding", "git", "position"],
    "showContextHints": true
  },
  "activityBar": {
    "show": true,
    "position": "left",
    "items": ["explorer", "openDocuments", "search"]
  },
  "keybindings": {
    "tabNext": "ctrl+pagedown",
    "tabPrev": "ctrl+pageup",
    "tabClose": null,
    "toggleSidebar": "ctrl+b",
    "clipboardModifier": "command",
    "historyModifier": "command"
  },
  "whitespace": {
    "showIndentation": true,
    "showSpaces": false,
    "showLineBreaks": false,
    "showUnexpected": true,
    "selectionWhitespace": "all"
  },
  "search": {
    "defaultTarget": "currentFile",
    "includeHiddenByDefault": false,
    "includeGitIgnoredByDefault": false,
    "caseSensitiveByDefault": false,
    "regexByDefault": false,
    "excludeGlobs": ["**/.git/**", "**/build/**", "**/.build/**"],
    "maxResults": 5000,
    "debounceMilliseconds": 150
  },
  "theme": {
    "editorForeground": "#c9d1d9",
    "lineNumberForeground": "#8b949e",
    "treePanelForeground": "#c9d1d9",
    "treeSelectedForeground": "#58a6ff",
    "treeDirectoryForeground": "#7ee787",
    "statusBarForeground": "#79c0ff",
    "titleBarForeground": "#f0f6fc",
    "separatorForeground": "#30363d",
    "keywordForeground": "#ff7b72",
    "typeForeground": "#79c0ff",
    "commentForeground": "#8b949e",
    "stringForeground": "#a5d6ff",
    "numberForeground": "#79c0ff",
    "attributeForeground": "#d2a8ff",
    "cursorLineBackground": "#30363d",
    "selectionBackground": "#264f78",
    "searchMatchBackground": "#3a3d41",
    "activeSearchMatchBackground": "#614f0e",
    "activeSearchMatchForeground": "#ffffff",
    "commandFeedbackForeground": "#8b949e",
    "gitModifiedForeground": "#e3b341",
    "gitAddedForeground": "#3fb950",
    "gitUntrackedForeground": "#8b949e",
    "gitDeletedForeground": "#f85149",
    "gitConflictedForeground": "#ff7b72",
    "gitModifiedLineBackground": "#e3b3412e",
    "gitModifiedLineForeground": "#e3b34173",
    "whitespaceIndentationForeground": "#484f58",
    "whitespaceUnexpectedForeground": "#ff7b72"
  }
}
```
