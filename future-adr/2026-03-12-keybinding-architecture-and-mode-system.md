# Future ADR: Keybinding Architecture and Mode System

Status: Proposed
Date: 2026-03-12

## Goal

Refactor KittyCode input handling so the app has:

- fuller and more coherent `nano` support
- fuller and more coherent `vim` support
- a new GUI-like `kittycode` preset
- command-based, config-driven keybinding resolution
- consistent behavior across editor, tree, sidebar, search, prompts, and context menus

## Refined Product Target

### Supported mode families

- `nano`
  - terminal-first
  - non-modal editor behavior
  - Ctrl-based shortcuts remain first-class
- `vim`
  - modal editing
  - broader support than today across editor and adjacent panels
  - classic motions and search navigation
- `kittycode`
  - GUI-like defaults
  - command/super-centric shortcuts as primary bindings
  - terminal-safe fallback bindings where needed

### Expectations

- A command should have one canonical meaning regardless of where it is invoked.
- Shortcuts shown in hints and context menus should match the active mode.
- Config should allow mode-specific defaults plus user overrides.
- The app should stay optimized for kitty keyboard protocol, but degrade cleanly when some chords are unavailable.

## Current Codebase Findings

- `keybindingMode` only supports `.nano` and `.vim` in `Sources/KittyCode/Config.swift`.
- CLI `--mode` only accepts `nano` and `vim` in `Sources/KittyCode/CLIArguments.swift`.
- Most shortcuts are hardcoded in `Sources/KittyCode/EventHandling.swift`.
- Editor motions are hardcoded in `Sources/KittyCode/EditorInput.swift`.
- Tree navigation is hardcoded in `Sources/KittyCode/TreeInput.swift`.
- Context menus display hardcoded labels like `Ctrl+O` and `Ctrl+W` in `Sources/KittyCode/EditorContextMenu.swift`.
- Config fields `keybindings.tabNext`, `tabPrev`, `tabClose`, and `toggleSidebar` are decoded but never used at runtime.
- Only clipboard and history modifier families are truly configurable, via `Sources/KittyCode/ShortcutMatching.swift`.
- Current vim support is shallow:
  - only editor normal/insert split exists
  - normal mode covers a small subset of motions
  - no visual mode
  - no operator-pending mode
  - no real command-line mode
  - no mode-specific handling for tree, sidebar, prompts, or future search UI
- `KittyWidgets.FocusEngine` exists but is not used by KittyCode. Focus routing is still mostly `tree` vs `editor`.
- Tests cover clipboard and history modifier matching, but not a unified command or preset layer.

## Key Problems To Solve

- There is no action layer between raw keys and behavior.
- There is no reusable parser for user-configured keybinding strings.
- There is no resolver that considers focus context, mode family, and fallback priority.
- Vim needs stateful multi-key sequence handling, not only single-key conditionals.
- GUI-like mode needs richer defaults than the current terminal-centric bindings.
- Status hints and menus cannot stay correct while bindings remain hardcoded in UI strings.

## Decision

### 1. Introduce a command layer

Raw key events should resolve to command ids before business logic runs.

Examples:

- `global.save`
- `global.newFile`
- `global.closeTab`
- `global.toggleSidebar`
- `navigation.nextTab`
- `navigation.focusTree`
- `search.openFile`
- `search.openWorkspace`
- `search.nextMatch`
- `search.previousMatch`
- `editor.moveLeft`
- `editor.wordForward`
- `tree.openSelected`

This is the core change that unlocks consistent presets and UI hints.

### 2. Separate focus context from editing mode

The resolver should work from context, not only from `EditorState.Mode`.

At minimum:

- editor
- tree
- sidebar.search
- sidebar.openDocuments
- prompt
- contextMenu
- overlayCommandLine

Editing mode like vim insert/normal/visual sits on top of focus context, not instead of it.

### 3. Support both chord bindings and stateful sequences

The system needs two levels:

- regular key chords for `nano` and `kittycode`
- stateful sequences for `vim`

That means:

- `Cmd+S`
- `Ctrl+O`
- `Cmd+Shift+F`
- `g g`
- `d d`
- `:w`
- `/pattern`

cannot all be modeled by the current hardcoded checks.

### 4. Add a first-class `kittycode` preset

`kittycode` should be the app's own desktop-like preset, tuned for kitty and terminal realities.

Principles:

- prefer GUI-like bindings where kitty can deliver them reliably
- provide terminal-safe fallback bindings for commands that may be intercepted elsewhere
- never require impossible shortcuts as the only way to access a feature

### 5. Preserve backward compatibility

Existing config should continue to load.

Legacy fields can be mapped forward:

- `clipboardModifier`
- `historyModifier`
- `tabNext`
- `tabPrev`
- `tabClose`
- `toggleSidebar`

These should become compatibility shims on top of the new command map until later cleanup.

## Proposed Architecture

### New KittyCode-side types

- `CommandID`
- `CommandCategory`
- `KeyStroke`
- `KeyChord`
- `KeySequence`
- `KeyContext`
- `ResolvedCommand`
- `KeymapPreset`
- `KeymapResolver`
- `InputDispatchState`
- `VimState`

Keep this in `KittyCode` first. Extracting a reusable package can wait until a second consumer exists.

### Resolution pipeline

1. `InputEvent.key`
2. normalize into `KeyStroke`
3. determine active `KeyContext`
4. consult preset + overrides
5. if a command resolves, dispatch by `CommandID`
6. if no command resolves:
   - allow vim sequence state to continue
   - or fall through to text insertion / raw navigation behavior where appropriate

Suggested resolution order:

1. modal overlays
2. prompt
3. context menu
4. search panel
5. focused sidebar panel
6. editor or tree local bindings
7. global bindings
8. text insertion fallback

### Command dispatcher

Centralize command execution in one place, for example:

- `execute(_ command: CommandID, in state: EditorState, pipeline: RenderPipeline)`

That lets:

- UI hints
- menus
- keyboard input
- future command palette
- mouse actions

all share the same action semantics.

### Focus integration

Use shell focus context plus the existing `FocusEngine` for control groups.

This is needed for:

- search panel traversal
- future command line overlays
- consistent `Tab` and `Shift+Tab` behavior in `kittycode`
- cleaner tree/editor/sidebar transitions

## Preset Strategy

### Nano preset

Keep the current terminal-friendly posture, but make it complete and explicit.

Examples:

- save: `Ctrl+O`
- new file: `Ctrl+N`
- close tab: `Ctrl+W`
- toggle sidebar: `Ctrl+B`
- file search: `Ctrl+F`
- replace: `Ctrl+R`
- next tab: `Ctrl+PageDown`
- previous tab: `Ctrl+PageUp`

### Vim preset

Expand from the current partial implementation to a real state machine.

Target phases:

- Phase 1
  - normal, insert, visual
  - `hjkl`, `w`, `b`, `e`, `0`, `$`, `gg`, `G`
  - `/`, `n`, `N`
  - `:w`, `:q`, `:wq`
  - tree/search panel navigation with `j`, `k`, `h`, `l`, `Enter`, `Esc`
- Phase 2
  - operator pending
  - `d`, `c`, `y`
  - linewise actions like `dd`, `cc`, `yy`
  - optional leader mappings

Universal fallbacks like arrows, Enter, and Escape should still work in non-editor UI.

### KittyCode preset

Make this the GUI-like preset with terminal-aware fallbacks.

Examples:

- save: `Cmd+S`, fallback `Ctrl+O`
- new file: `Cmd+N`, fallback `Ctrl+N`
- close tab: `Cmd+W`, fallback `Ctrl+W`
- toggle sidebar: `Cmd+B`, fallback `Ctrl+B`
- file search: `Cmd+F`
- workspace search: `Cmd+Shift+F`
- replace: `Cmd+Shift+H`
- undo: `Cmd+Z`
- redo: `Cmd+Shift+Z`
- copy/cut/paste: `Cmd+C`, `Cmd+X`, `Cmd+V`

Do not depend on OS-reserved shortcuts as the only path to a command.

## Config Direction

Extend config to support command-based overrides.

Suggested shape:

```json
{
  "keybindingMode": "kittycode",
  "keybindings": {
    "sequenceTimeoutMilliseconds": 500,
    "allowPresetFallbacks": true,
    "overrides": {
      "global.save": ["cmd+s", "ctrl+o"],
      "global.newFile": ["cmd+n", "ctrl+n"],
      "global.toggleSidebar": ["cmd+b", "ctrl+b"],
      "search.openFile": ["cmd+f"],
      "search.openWorkspace": ["cmd+shift+f"]
    }
  },
  "vim": {
    "leaderKey": "space",
    "commandTimeoutMilliseconds": 500,
    "useSystemClipboard": true
  }
}
```

Notes:

- Each command may have multiple bindings.
- Preset defaults come from the selected `keybindingMode`.
- `overrides` replace or extend preset bindings.
- Legacy fields should map into this model during load.

## CLI Direction

Update `--mode` to accept:

- `nano`
- `vim`
- `kittycode`

That should match config exactly.

## UI and Documentation Implications

- `contextHintText` should render from resolved command metadata, not hardcoded strings.
- context menus should ask the keybinding resolver for the visible shortcut label.
- `CONFIG.md` should stop claiming configurability for runtime-dead fields.
- status messages for vim should reflect actual mode and command-line state.

## Implementation Plan

1. Inventory all current keyboard-triggered behaviors and map them to `CommandID`s.
2. Add a parser for shortcut strings and a resolver for preset plus override lookup.
3. Introduce focus contexts and route all input through the resolver before direct behavior checks.
4. Migrate hardcoded global bindings first:
   - save
   - new file
   - close tab
   - sidebar toggle
   - tab navigation
   - clipboard
   - undo/redo
5. Add the `kittycode` preset and wire CLI/config support for it.
6. Make UI hints and context menu shortcut labels mode-aware.
7. Expand `nano` coverage so every user-visible shortcut comes from the resolver.
8. Replace the ad hoc vim branch in `EditorInput` with a `VimState` interpreter.
9. Add search-panel and sidebar contexts to the same system so the feature can scale.
10. Remove dead or misleading config paths after compatibility coverage is in place.

## Testing Plan

- parser tests for key strings and sequences
- resolver tests by context and preset
- compatibility tests for legacy config mapping
- CLI tests for `--mode kittycode`
- regression tests for displayed shortcut labels
- vim sequence tests
- end-to-end tests for the highest value commands in all three presets

## Risks and Open Questions

- Vim support can expand indefinitely. The first milestone should stop at a coherent, editor-usable subset.
- Some GUI-like chords may be unavailable or intercepted outside kitty. Fallback bindings are mandatory.
- Mixing text insertion fallback with command resolution needs careful ordering to avoid regressions.
- Sequence timeout policy for vim and multi-stroke bindings needs to be explicit and testable.

## Recommendation

Do not add more feature-specific shortcut checks to `handleEvent`, `handleEditorKey`, or `handleTreeKey`.

Instead:

1. build the command and resolver layer
2. wire focus contexts
3. add `kittycode`
4. migrate nano
5. rebuild vim on top of the same foundation

The search feature ADR should depend on this architecture for mode-aware shortcuts and focus behavior.
