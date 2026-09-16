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
- redo: `Shift+Cmd+Z`
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

## Deep Technical Analysis

### Codebase Impact Assessment

#### EventHandling.swift Refactoring Scope

The current input dispatch at EventHandling.swift:8-178 is a monolithic function with a fixed priority chain: release guard → context menu → prompt → global Ctrl+key hotkeys → mode-specific dispatch. Every shortcut is a hardcoded `if` or `switch` check against `key.keyCode` and `key.modifiers`.

Concrete changes required:

1. **Extract command resolution from event handling**: The function currently mixes "what key was pressed" with "what action to take." These must separate into: (a) `KeyStroke` normalization from `KeyEvent`, (b) `KeyContext` determination from current focus state, (c) `KeymapResolver.resolve(stroke:context:preset:overrides:)` returning `CommandID?`, (d) `CommandDispatcher.execute(command:state:pipeline:)`.

2. **Preserve the priority chain as resolver layers**: The current priority (overlay → prompt → context menu → global → mode-specific) is correct behavior. The resolver should encode this as an ordered list of keymap scopes, not flatten everything into one map. Each scope can short-circuit resolution.

3. **Migrate incrementally**: The 24 hardcoded shortcut checks (Ctrl+O, Ctrl+N, Ctrl+X, Ctrl+B, Ctrl+W, Ctrl+H, clipboard shortcuts, undo/redo, tab navigation, Escape) should be migrated one command at a time. Each migration replaces one `if` block with a `CommandID` case, preserving existing behavior.

#### ShortcutMatching.swift Evolution

The current configurable matching system (ShortcutMatching.swift:3-91) supports only `ShortcutModifier` selection (`.command`, `.control`, `.both`) for clipboard and history shortcuts. It uses `matchesConfiguredShortcut()` which checks keyCode and modifier flags.

This system should evolve into the general `KeymapResolver`:

1. **Shortcut string parser**: The config already defines strings like `"ctrl+pagedown"` for tab navigation (Config.swift:44-47) but never parses them. A `KeyStroke.parse("ctrl+shift+f")` function is needed that produces a `KeyStroke(keyCode:modifiers:)` from human-readable strings. This parser must handle: modifier names (`ctrl`, `cmd`/`super`, `alt`, `shift`, `meta`), key names (`pagedown`, `home`, `escape`, `enter`, `tab`, `space`), single characters (`f`, `s`, `z`), and key codes (`f1`-`f12`).

2. **Sequence support**: Vim needs multi-key sequences (`g g`, `d d`, `: w`). The resolver must maintain an `InputDispatchState` that accumulates keystrokes with a configurable timeout (default 500ms from the ADR config). On timeout or non-matching keystroke, the pending sequence is discarded and the latest key is re-evaluated as a fresh start.

3. **Backward compatibility**: The existing `clipboardModifier` and `historyModifier` config fields must map into the new command system. During config loading, if legacy fields are present, they should generate equivalent `overrides` entries for `global.copy`, `global.cut`, `global.paste`, `global.undo`, `global.redo`.

#### EditorInput.swift Vim State Machine

The current vim implementation (EditorInput.swift:66-100) is a flat `switch key.keyCode` inside an `if state.config.keybindingMode == .vim && state.vimMode == .normal` guard. It supports only: `i` (insert), `h/j/k/l` (movement), `:` (status message only), `w` after `:` (save), and `Shift+G` (jump to end).

A real vim state machine requires:

1. **VimState struct**: Track `mode` (normal/insert/visual/visualLine/operatorPending/commandLine), `pendingOperator` (d/c/y/none), `pendingCount` (numeric prefix), `commandLineBuffer` (for `:` and `/`), `lastSearch` (for `n`/`N` repeat), `registers` (at minimum the default and clipboard registers).

2. **Motion resolution**: Motions like `w`, `b`, `e`, `0`, `$`, `gg`, `G` must be modeled as `VimMotion` values that compute a target `TextPosition` from the current cursor. Operators combine with motions: `dw` = delete + word-forward, `c$` = change + end-of-line.

3. **Operator-pending mode**: When `d`, `c`, or `y` is pressed in normal mode, the state enters operator-pending. The next keystroke is interpreted as a motion. If a valid motion resolves, the operator acts on the range from cursor to motion target. If the same operator key repeats (`dd`, `cc`, `yy`), it acts on the entire current line.

4. **Visual mode**: `v` enters character-wise visual, `V` enters line-wise visual. Movement extends the selection. Operators act on the visual selection. Escape returns to normal mode.

5. **Command-line mode**: `:` enters command-line mode with a buffer rendered in the status bar. Enter executes. Supported commands in Phase 1: `:w` (save), `:q` (close tab or quit), `:wq` (save and close), `:e <path>` (open file). `/` enters search mode with the same buffer — this integrates with the search ADR.

#### Context Menu and Hint Label Migration

EditorContextMenu.swift currently constructs menu items with hardcoded shortcut strings like `"Ctrl+O"` and `"Ctrl+W"` (lines 42-102). The `contextHintText` property (lines 9-26) builds hint text from these hardcoded labels.

After migration:
1. Menu items should be constructed from `CommandID` values: `ContextMenuItem(command: .global.save)`.
2. The display shortcut label should be resolved at render time by querying the keybinding resolver for the active preset: `resolver.shortcutLabel(for: .global.save, preset: config.keybindingMode)`.
3. The hint text builder should compose from resolved labels, not static strings.

#### KeyEvent and KeyModifiers Compatibility

The `KeyEvent` type (KittyCodecs/Types.swift:87-107) uses `keyCode: UInt32` for key identity and `KeyModifiers` as an `OptionSet` with `.shift`, `.alt`, `.ctrl`, `.super`, `.meta`, `.hyper`, `.capsLock`, `.numLock`. The `KeyStroke` normalization step must:

- Strip `.capsLock` and `.numLock` (already done in ShortcutMatching.swift:63-67)
- Map `.super` and `.meta` to a unified `command` concept for cross-terminal compatibility
- Normalize letter keyCodes to lowercase for case-insensitive matching (Shift is tracked separately)
- Handle `associatedText` for text insertion fallback when no command matches

### State of the Art: Terminal Editor Keybinding Systems

#### Neovim Architecture

Neovim's keybinding system is the gold standard for modal editing in terminals:
- **Keymap layers**: Global keymaps, buffer-local keymaps, and mode-specific keymaps are stored in separate tables. Resolution checks buffer-local first, then global, within the active mode.
- **Operator-pending**: A first-class mode that tracks the pending operator and awaits a motion or text object. Count prefixes accumulate and multiply (e.g., `3d2w` = delete 6 words).
- **`<Leader>` key**: A configurable prefix key (default `\`) that namespaces user mappings. The leader concept prevents collisions with built-in bindings.
- **`:map` command**: Runtime remapping with mode-specific variants (`:nmap`, `:imap`, `:vmap`). Maps can point to other key sequences or to Lua functions.
- **Timeoutlen**: Configurable delay (default 1000ms) for multi-key sequences. If the timeout elapses, the longest matching prefix is executed.

#### Helix Architecture

Helix uses a statically typed keymap tree:
- **Trie-based resolution**: Keymaps are a trie of `KeyEvent → Action | KeyTrie`. Each node is either a terminal action or a subtree for multi-key sequences.
- **Mode-specific keymaps**: Normal, insert, select modes each have their own trie.
- **No arbitrary remapping in v1**: Keymaps are defined in TOML config but the action set is fixed. Users can rebind keys to existing actions but cannot define new ones.
- **Sticky keys**: Some modes (like select) are "sticky" — they persist across multiple actions until explicitly exited.

#### Zed Architecture

Zed implements a VS Code-like keybinding model:
- **Context predicates**: Each binding can specify a context predicate (e.g., `Editor && mode == normal`). The resolver evaluates predicates against the current focus context to find matching bindings.
- **Multi-stroke sequences**: Supported with `"ctrl+k ctrl+c"` syntax. A pending keystroke buffer tracks partial matches.
- **Keymap JSON**: User keybindings are JSON files with the same schema as built-in defaults. User bindings override by full key match.
- **Action dispatch**: Actions are strongly typed Rust structs. The dispatcher routes by action type to the focused view or its ancestors in the view tree.

#### VS Code Architecture

VS Code's keybinding system handles massive scale:
- **`when` clauses**: Every keybinding has an optional `when` expression evaluated against the current context (e.g., `editorTextFocus && !editorReadonly`). This is the most flexible context model in any editor.
- **Chord sequences**: Supports two-part chords like `Ctrl+K Ctrl+C`. The first key puts the system into a "chord pending" state shown in the status bar.
- **Default → User → Extension layering**: Three layers of keybinding definitions. Later layers can override or remove bindings.
- **Command palette integration**: Every keybinding maps to a command ID. The command palette shows the resolved keybinding next to each command.

### Recommended Technical Approach for KittyCode

#### Command and Keybinding System: SOTA Architecture

1. **When-clause predicate engine with AST evaluation**: Implement a rich contextual predicate system modeled after VS Code's `when` clauses. Every keybinding specifies a boolean expression evaluated against the current editor context: `editorHasFocus && !suggestWidgetVisible && vim.mode == 'normal'`, `treeViewFocus && !readOnly`, `searchInputFocus && hasResults`. Parse when-clause strings into an AST of `AndExpr`, `OrExpr`, `NotExpr`, `EqualsExpr`, and `ContextKeyExpr` nodes at configuration load time. At evaluation time, resolve each `ContextKeyExpr` against a `ContextKeyService` that maintains a stack of context key-value maps (global context, editor context, widget context). This completely eliminates the 24 hardcoded shortcut priority chains in EventHandling.swift and makes the entire binding system fully declarative and extensible.

2. **Full Neovim-compatible vim emulation**: Target compatibility with the complete Neovim editing model, not a "useful subset." Implement all 8 modes: normal, insert, visual (character), visual-line, visual-block, command-line, operator-pending, replace, and select. Implement the full verb-object grammar: operators (`d`, `c`, `y`, `>`, `<`, `=`, `gq`, `gU`, `gu`, `g~`, `!`) compose with motions (`w`, `W`, `b`, `B`, `e`, `E`, `0`, `^`, `$`, `f`, `F`, `t`, `T`, `;`, `,`, `gg`, `G`, `{`, `}`, `(`, `)`, `%`, `/`, `?`, `n`, `N`) and text objects (`iw`, `aw`, `iW`, `aW`, `is`, `as`, `ip`, `ap`, `i"`, `a"`, `i'`, `a'`, `i(`, `a(`, `i{`, `a{`, `i[`, `a[`, `it`, `at`). Count prefixes apply to all composable commands: `d2w`, `3ci"`, `5>>`, `gUiw`. Support registers: unnamed (`"`), numbered (`0`-`9`), named (`a`-`z`, `A`-`Z` for append), clipboard (`+`, `*`), small-delete (`-`), last-inserted (`.`), command (`:`), search (`/`), expression (`=`), black hole (`_`). Support marks: local (`a`-`z`), global (`A`-`Z`), special (`` ` ``, `'`, `[`, `]`, `<`, `>`, `.`, `^`). Implement the jump list (`Ctrl-O`, `Ctrl-I`) and change list (`g;`, `g,`). Implement the `.` (dot) repeat command, which replays the last change — this requires recording the full keystroke sequence of each change operation, including the operator, count, motion/text-object, and inserted text.

3. **Macro recording and playback**: `q{register}` begins recording all keystrokes into the named register. `q` again stops recording. `@{register}` replays the macro. `@@` repeats the last played macro. Count prefixes work: `100@a` replays macro `a` 100 times. Macros store raw keystroke sequences (not resolved commands) so they interact correctly with mode switches, counts, and operators. Recursive macros are supported — `@a` can contain `@b` which can contain `@a` (with a recursion depth limit of 1000 to prevent infinite loops). Macros are stored in the same register namespace as yank/delete, enabling `"ayy` followed by `@a` to execute the current line as a sequence of editor commands.

4. **Leader key sequences with which-key popup**: Support a configurable `<Leader>` key (default: `Space` in normal mode). Leader sequences like `<Leader>ff` for find-files, `<Leader>ca` for code-action, `<Leader>gs` for git-status open a namespace for user-defined multi-key bindings. After pressing `<Leader>`, if no further key arrives within a configurable timeout (default: 500ms), display a Helix/which-key-style popup panel showing all available continuations grouped by category: `f` file..., `c` code..., `g` git..., `b` buffer..., `w` window.... Each subsequent key narrows the popup until a leaf command is reached and executed. The popup renders as an overlay panel using the existing terminal UI framework.

5. **Trie-based keymap resolution with timeout and conflict detection**: Build a `KeyTrie` per mode. Each node is either a leaf (resolved `CommandID`), a branch (more keys expected), or a timeout-leaf (execute if no further key within timeout, otherwise continue). On each keystroke, walk the trie. If at a leaf, execute immediately. If at a branch, enter "pending chord" state with a visible indicator in the status bar (e.g., "Ctrl+K ..."). If the timeout expires at a timeout-leaf, execute that command. If no match exists at any point, fall through to text insertion (insert mode) or bell (normal mode). At configuration load time, detect and warn about conflicts: if binding A is a prefix of binding B, flag it unless A has `"allowPrefix": true`.

6. **Chord support for VS Code-style multi-key sequences**: Support `Ctrl+K Ctrl+C` style two-part chord sequences alongside vim-style sequences. The trie naturally handles this: `Ctrl+K` reaches a branch node, the resolver enters "chord pending" state, and the next key (`Ctrl+C`) resolves to the leaf. Chords and vim sequences coexist in the same trie, differentiated by mode context. The status bar shows the pending chord in real-time.

7. **User keymap overlay with per-mode, per-context bindings**: User keybindings are loaded from `~/.config/kittycode/keybindings.json` and overlaid on top of defaults with identical resolution semantics. Support three override operations: `"command"` to bind, `"command": "-"` to remove/unbind a default, and `"command": "noop"` to suppress without replacement. Each user binding can specify `"mode"` (vim mode), `"when"` (context predicate), and `"args"` (command arguments). Multiple user keymap files are supported and merged in order, enabling per-language or per-project keybinding overrides.

8. **Keymap introspection and debugging**: Provide a `:keybindings` command (and command palette entry) that renders a searchable, filterable table of all active bindings for the current context. Columns: key sequence, command, when-clause, source (default / user / extension), mode. Add a "keyboard logging" mode (`:keylog on`) that prints each keypress, the trie walk path, the resolved command (or "unmatched"), and the active context keys to a dedicated log panel. This is invaluable for debugging custom bindings and understanding why a binding does or does not trigger.

## SOTA Review and Accuracy Assessment

This section evaluates the ADR's technical claims and recommendations against verified state-of-the-art knowledge as of March 2026.

### Verified Accurate

1. **Neovim's keymap architecture** — verified. Keymap layers (global, buffer-local, mode-specific), operator-pending as a first-class mode, `timeoutlen` for multi-key sequences, and `<Leader>` key namespacing all accurately described.

2. **Helix's trie-based keymaps** — verified. Helix stores keymaps in a `KeyTrieNode` containing `HashMap<KeyEvent, KeyTrie>`. Resolution returns Execute/Pending/NotFound/Cancelled. "Sticky" keys (`Z` vs `z`) keep the trie position at a sub-trie root for repeated commands.

3. **VS Code's when-clause system** — verified. Boolean expressions over context keys evaluated by `KeybindingResolver`. Supports `&&`, `||`, `!`, `==`, `!=`, `<`, `>`, `=~`, `in`. Rules filtered by key chord first, then when-clauses evaluated. The first matching rule wins.

4. **Zed's context predicates** — verified. Structurally similar to VS Code but resolved via the focus tree hierarchy. Actions are strongly-typed Rust structs. Context is pushed by views during rendering.

5. **The proposed resolution pipeline** (normalize keystroke → determine context → consult preset + overrides → dispatch command) is standard across all reviewed editors.

6. **The EventHandling.swift refactoring scope analysis** correctly identifies the 24 hardcoded shortcut checks that need migration.

### Requires Qualification

1. **"Full Neovim-compatible vim emulation"** (point 2) — **Extremely ambitious scope**. The ADR proposes implementing all 8 modes, the full verb-object grammar, 20+ operators, 30+ motions, 20+ text objects, 30+ registers, marks, jump list, change list, and dot-repeat. This is the scope of a project like vim-mode-plus (Atom), evil-mode (Emacs), or VSCodeVim — each representing person-years of development. The ADR correctly notes "Vim support can expand indefinitely" in the risks section, but the recommended approach lists this as a target rather than a stretch goal. Consider: Helix deliberately chose a Kakoune-inspired selection-first model to avoid the full Vim complexity. The Phase 1/Phase 2 split in the preset strategy section is more realistic.

2. **Macro recording** (point 3) — **Also very ambitious for initial implementation**. Macros store raw keystroke sequences and support recursion with depth limits. While architecturally sound, this is a significant feature that should be explicitly deferred to a later phase.

3. **When-clause predicate engine** (point 1) — **Performance consideration**. VS Code mitigates evaluation cost by first filtering by key chord before evaluating when-clauses. The ADR should mention this optimization: evaluate predicates only for rules whose key pattern matches the pressed key, not for all rules.

4. **Kakoune's selection-first model** — The ADR focuses on Vim emulation but does not discuss the Kakoune/Helix selection-first paradigm as an alternative. In Kakoune, you select first (seeing visual feedback), then act — lower cognitive load for complex operations but more keystrokes for simple ones. The `kittycode` preset could benefit from selection-first principles for non-modal editing contexts.

5. **ARM NEON and keyboard protocol** — The KeyEvent normalization step should explicitly address the kitty keyboard protocol's enhanced key reporting (CSI u encoding), which provides unambiguous key identification that traditional terminals cannot. The `kittycode` preset can rely on this for reliable Cmd+key chords, while nano/vim presets should not assume it.

### References

- Neovim map documentation: https://neovim.io/doc/user/map.html
- VS Code when-clause contexts: https://code.visualstudio.com/api/references/when-clause-contexts
- Helix keymap system: https://docs.helix-editor.com/keymap.html
- Zed key bindings: https://zed.dev/docs/key-bindings
- Kakoune design philosophy: https://kakoune.org/why-kakoune/why-kakoune.html
- which-key.nvim: https://github.com/folke/which-key.nvim
- Cassowary algorithm paper: https://constraints.cs.washington.edu/solvers/cassowary-tochi.pdf
