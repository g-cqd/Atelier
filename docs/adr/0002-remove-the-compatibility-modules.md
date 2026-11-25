---
status: accepted
date: 2026-10-18
---

# 0002 — Import TerminalKit without compatibility modules

## Context

ADR-0001 replaced six local implementations with re-export shims. Those shims preserved imports
while the implementation and owning tests moved. The requested follow-up removes the old module names.

## Decision

- Remove `KittyTerminal`, `KittyStyle`, `KittyCodecs`, `KittyInput`, `KittyRenderer` and `AtelierText`
  products, targets and shim sources. These are six library products, not five.
- Import `TerminalKitIO`, `TerminalKitStyle`, `TerminalKitCodecs`, `TerminalKitInput`,
  `TerminalKitRender` and `TerminalKitText` directly, with explicit product dependencies replacing
  the old target references. Deduplicate dependencies that already named the canonical product.
- Keep `AtelierTextRendering` and `AtelierTextView`: these are unrelated app modules.
- Remove the four temporary alias-identity tests and their target. With only canonical imports,
  their rewritten assertions would compare each type with itself. Keep app integration tests.
- Replace a parser corpus path referencing the extracted style source with an existing app style
  adapter, so the opt-in parser measurement does not try to read a deleted file.

## Consequences

This is source-breaking for consumers importing the old modules or requesting their products.
The inspected ask, TerminalKit and Aemi repositories had no such consumers; that is not evidence
that no external consumers exist. External callers must update imports and package dependencies.

Extraction and import migration are separate reviewable steps. The extraction kept type identity
through re-exports; direct imports now remove those temporary names without changing algorithms.
Allocation test observations belong in the diary, not in this structural decision.
