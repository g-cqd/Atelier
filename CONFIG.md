# KittyCode Configuration

KittyCode reads its configuration from `~/.kittycode.json` on launch. All fields are optional — omitted fields use their default values. The file is watched for changes and hot-reloaded automatically.

## Top-Level Options

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `keybindingMode` | `"nano"` \| `"vim"` | `"nano"` | Keyboard shortcut scheme. Nano uses Ctrl-based shortcuts; Vim uses modal editing. |
| `treeWidth` | `int` | `30` | Width of the file tree sidebar in columns. Clamped to half the terminal width. |
| `useSFSymbolsInTerminal` | `bool` | `true` | Use SF Symbol glyphs for file/folder icons when the terminal supports them. |
| `fileWatcherEnabled` | `bool` | `true` | Watch open files for external changes and prompt for reload. |

## Editor (`editor`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `editor.wrapLines` | `bool` | `false` | Wrap long lines instead of horizontal scrolling. |
| `editor.tabSize` | `int` | `4` | Number of columns per tab stop. |
| `editor.highlightCurrentLine` | `bool` | `false` | Highlight the line containing the cursor across the full editor width. |
| `editor.arrowKeysWrapAcrossLines` | `bool` | `true` | Let left/right arrow keys move to the previous/next line at line boundaries. |
| `editor.scrollLines` | `int?` | `null` | Lines per scroll-wheel tick. When `null`, vertical scrolling defaults to 1 line per event. |
| `editor.scrollHorizontalStep` | `int` | `4` | Columns per horizontal scroll tick (Shift+scroll or trackpad horizontal). |
| `editor.scrollMomentumBlockMilliseconds` | `int` | `5` | Brief rebound-block window after reversing scroll direction. Set to `0` to disable it. |
| `editor.scrollAccelerationEnabled` | `bool` | `true` | Enable burst-rate acceleration for vertical 1-line scrolling. |
| `editor.scrollAccelerationWindowMilliseconds` | `int` | `120` | Time window used to count same-direction scroll bursts. |
| `editor.scrollAccelerationStepIntervalMilliseconds` | `int` | `1` | Delay between queued accelerated 1-line steps. |
| `editor.scrollAccelerationMaxExtraLines` | `int` | `8` | Maximum extra 1-line steps queued from a single burst event. |

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
| `statusBar.leftItems` | `[item]` | `["status"]` | Segments shown on the left side of the status bar. |
| `statusBar.rightItems` | `[item]` | `["visibility", "language", "size", "lineEnding", "git", "position"]` | Segments shown on the right side. |
| `statusBar.showContextHints` | `bool` | `true` | Show contextual keyboard hints in the status bar. |

Available status bar items: `file`, `status`, `language`, `size`, `lineEnding`, `git`, `position`, `visibility`.

## Activity Bar (`activityBar`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `activityBar.show` | `bool` | `true` | Show the activity bar on the left side of the editor. |
| `activityBar.position` | `"left"` \| `"right"` | `"left"` | Position of the activity bar. |
| `activityBar.items` | `[string]` | `["explorer", "openDocuments"]` | Sidebar panels, in display order. |

## Keybindings (`keybindings`)

| JSON Key | Type | Default | Description |
|----------|------|---------|-------------|
| `keybindings.tabNext` | `string` | `"ctrl+pagedown"` | Key combo to switch to the next tab. |
| `keybindings.tabPrev` | `string` | `"ctrl+pageup"` | Key combo to switch to the previous tab. |
| `keybindings.tabClose` | `string?` | `null` | Optional key combo to close the current tab. |
| `keybindings.toggleSidebar` | `string` | `"ctrl+b"` | Key combo to toggle the sidebar. |

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

## Theme Colors (`theme`)

All color values are CSS-style hex strings (e.g. `"#c9d1d9"`). All theme fields are optional.

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

### Git File Status

| JSON Key | Default | Description |
|----------|---------|-------------|
| `theme.gitModifiedForeground` | `#e3b341` | Modified files |
| `theme.gitAddedForeground` | `#3fb950` | Added files |
| `theme.gitUntrackedForeground` | `#8b949e` | Untracked files |
| `theme.gitDeletedForeground` | `#f85149` | Deleted files |
| `theme.gitConflictedForeground` | `#ff7b72` | Conflicted files |

### Git Line Highlighting

These fields accept either a plain hex color like `"#3fb950"` or an object with alpha: `{ "color": "#3fb950", "alpha": 0.18 }`.

| JSON Key | Description |
|----------|-------------|
| `theme.gitModifiedLineBackground` | Modified-line background overlay |
| `theme.gitModifiedLineForeground` | Modified-line foreground overlay |
| `theme.gitAddedLineBackground` | Added-line background overlay |
| `theme.gitAddedLineForeground` | Added-line foreground overlay |
| `theme.gitUntrackedLineBackground` | Untracked-line background overlay |
| `theme.gitUntrackedLineForeground` | Untracked-line foreground overlay |
| `theme.gitDeletedLineBackground` | Deleted-line background overlay |
| `theme.gitDeletedLineForeground` | Deleted-line foreground overlay |
| `theme.gitConflictedLineBackground` | Conflicted-line background overlay |
| `theme.gitConflictedLineForeground` | Conflicted-line foreground overlay |

### Tab Ribbon

| JSON Key | Description |
|----------|-------------|
| `theme.tabActiveBackground` | Active tab background |
| `theme.tabActiveForeground` | Active tab text color |
| `theme.tabInactiveBackground` | Inactive tab background |
| `theme.tabInactiveForeground` | Inactive tab text color |
| `theme.tabDirtyIndicator` | Dirty indicator color |

### Activity Bar

| JSON Key | Description |
|----------|-------------|
| `theme.activityBarBackground` | Activity bar background |
| `theme.activityBarForeground` | Activity bar icon color |
| `theme.activityBarActiveForeground` | Active panel icon color |

### Open Files Panel

| JSON Key | Description |
|----------|-------------|
| `theme.openFilesForeground` | Open files list text color |
| `theme.openFilesSelectedForeground` | Selected file text color |

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
  "editor": {
    "wrapLines": false,
    "tabSize": 4,
    "highlightCurrentLine": true,
    "arrowKeysWrapAcrossLines": true,
    "scrollLines": null,
    "scrollHorizontalStep": 4
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
    "leftItems": ["status"],
    "rightItems": ["visibility", "language", "size", "lineEnding", "git", "position"],
    "showContextHints": true
  },
  "activityBar": {
    "show": true,
    "position": "left",
    "items": ["explorer", "openDocuments"]
  },
  "keybindings": {
    "tabNext": "ctrl+pagedown",
    "tabPrev": "ctrl+pageup",
    "tabClose": null,
    "toggleSidebar": "ctrl+b"
  },
  "whitespace": {
    "showIndentation": true,
    "showSpaces": false,
    "showLineBreaks": false,
    "showUnexpected": true,
    "selectionWhitespace": "all"
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
    "gitModifiedForeground": "#e3b341",
    "gitAddedForeground": "#3fb950",
    "gitUntrackedForeground": "#8b949e",
    "gitDeletedForeground": "#f85149",
    "gitConflictedForeground": "#ff7b72",
    "gitModifiedLineBackground": {
      "color": "#e3b341",
      "alpha": 0.18
    },
    "whitespaceIndentationForeground": "#484f58",
    "whitespaceUnexpectedForeground": "#ff7b72"
  }
}
```
