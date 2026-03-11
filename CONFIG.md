# KittyCode Configuration

KittyCode reads its configuration from `~/.kittycode.json` on launch. All fields are optional — omitted fields use their default values.

## Editor Behavior

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `keybindingMode` | `"nano"` \| `"vim"` | `"nano"` | Keyboard shortcut scheme. Nano uses Ctrl-based shortcuts; Vim uses modal editing. |
| `wrapLines` | `bool` | `false` | Wrap long lines in the editor instead of horizontal scrolling. |
| `treeWidth` | `int` | `30` | Width of the file tree sidebar in columns. Clamped to half the terminal width. |
| `useSFSymbolsInTerminal` | `bool` | `true` | Use SF Symbol glyphs for icons when the terminal supports them. |

## Tab Ribbon

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `tabRibbonPosition` | `"top"` \| `"hidden"` | `"top"` | Position of the tab ribbon. `"hidden"` disables the tab bar entirely. |
| `tabPersistence` | `"pinned"` \| `"preview"` | `"pinned"` | How new file tabs behave. `"pinned"` keeps all opened files as permanent tabs. `"preview"` opens files as a single preview tab that gets replaced by the next file opened; editing or double-clicking a tree entry pins the tab. |

## Syntax Highlighting

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `syntaxHighlighting` | `bool` | `true` | Enable Tree-sitter-based syntax highlighting. |
| `disabledLanguages` | `[string]` | `[]` | List of language identifiers to exclude from syntax highlighting (e.g. `["python", "ruby"]`). |

## File Watching

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `fileWatcherEnabled` | `bool` | `true` | Watch open files for external changes and prompt for reload. |

## Auto-Save

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `autoSave` | `bool` | `false` | Automatically save dirty buffers on a timer. |
| `autoSaveInterval` | `number` | `30` | Seconds between auto-save checks. |

## Git Integration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `showGitStatus` | `bool` | `true` | Show git status indicators in the file tree and status bar. |
| `gitRefreshInterval` | `number` | `10` | Seconds between git status refreshes. |

## Activity Bar

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `activityBar.show` | `bool` | `true` | Show the activity bar on the left side of the editor. |
| `activityBar.position` | `"left"` \| `"right"` | `"left"` | Position of the activity bar. |
| `activityBar.items` | `[string]` | `["explorer", "openDocuments"]` | Activity bar panels, in display order. |

## Keybindings

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `keybindings.tabNext` | `string` | `"ctrl+pagedown"` | Key combo to switch to the next tab. |
| `keybindings.tabPrev` | `string` | `"ctrl+pageup"` | Key combo to switch to the previous tab. |
| `keybindings.tabClose` | `string?` | `null` | Optional key combo to close the current tab. |
| `keybindings.toggleSidebar` | `string` | `"ctrl+b"` | Key combo to toggle the sidebar. |

## Theme Colors

All color values are CSS-style hex strings (e.g. `"#c9d1d9"`). All are optional.

### Core

| Field | Default | Description |
|-------|---------|-------------|
| `theme.treePanelForeground` | `#c9d1d9` | File tree text color |
| `theme.treeSelectedForeground` | `#58a6ff` | Selected tree item color |
| `theme.treeDirectoryForeground` | `#7ee787` | Directory name color |
| `theme.editorForeground` | `#c9d1d9` | Editor text color |
| `theme.lineNumberForeground` | `#8b949e` | Line number gutter color |
| `theme.statusBarForeground` | `#79c0ff` | Status bar text color |
| `theme.titleBarForeground` | `#f0f6fc` | Title bar text color |
| `theme.separatorForeground` | `#30363d` | Panel separator color |

### Syntax

| Field | Default | Description |
|-------|---------|-------------|
| `theme.keywordForeground` | `#ff7b72` | Keywords (`if`, `let`, `func`, etc.) |
| `theme.typeForeground` | `#79c0ff` | Type names |
| `theme.commentForeground` | `#8b949e` | Comments |
| `theme.stringForeground` | `#a5d6ff` | String literals |
| `theme.numberForeground` | `#79c0ff` | Numeric literals |
| `theme.attributeForeground` | `#d2a8ff` | Attributes, properties, function names |

### Git

| Field | Default | Description |
|-------|---------|-------------|
| `theme.gitModifiedForeground` | `#e3b341` | Modified files |
| `theme.gitAddedForeground` | `#3fb950` | Added files |
| `theme.gitUntrackedForeground` | `#8b949e` | Untracked files |
| `theme.gitDeletedForeground` | `#f85149` | Deleted files |
| `theme.gitConflictedForeground` | `#ff7b72` | Conflicted files |

### Tab Ribbon (optional)

| Field | Description |
|-------|-------------|
| `theme.tabActiveBackground` | Active tab background |
| `theme.tabActiveForeground` | Active tab text color |
| `theme.tabInactiveBackground` | Inactive tab background |
| `theme.tabInactiveForeground` | Inactive tab text color |
| `theme.tabDirtyIndicator` | Dirty indicator color |

### Activity Bar (optional)

| Field | Description |
|-------|-------------|
| `theme.activityBarBackground` | Activity bar background |
| `theme.activityBarForeground` | Activity bar icon color |
| `theme.activityBarActiveForeground` | Active panel icon color |

### Open Files Panel (optional)

| Field | Description |
|-------|-------------|
| `theme.openFilesForeground` | Open files list text color |
| `theme.openFilesSelectedForeground` | Selected file text color |

## Complete Example

```json
{
  "keybindingMode": "vim",
  "wrapLines": false,
  "treeWidth": 35,
  "useSFSymbolsInTerminal": true,
  "syntaxHighlighting": true,
  "disabledLanguages": [],
  "tabRibbonPosition": "top",
  "tabPersistence": "pinned",
  "fileWatcherEnabled": true,
  "autoSave": false,
  "autoSaveInterval": 30,
  "showGitStatus": true,
  "gitRefreshInterval": 10,
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
  "theme": {
    "editorForeground": "#c9d1d9",
    "keywordForeground": "#ff7b72",
    "typeForeground": "#79c0ff",
    "commentForeground": "#8b949e",
    "stringForeground": "#a5d6ff"
  }
}
```
