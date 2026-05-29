# v0.35 — Final Polish

**Date:** 2026-05-29
**Status:** Design approved (final intended version of this marathon)
**Branch:** `v0.35-final-polish` off `main`

## 1. Goal

Three closing improvements that round out the v0.16-v0.34 work:

1. **Mouse-hover tooltip** in editor (long-deferred from v0.29)
2. **Comprehensive README rewrite** — getting-started, install, command reference
3. **8 more built-in lint rules** to round the .scm pack to ~20 total

## 2. F1 — Mouse-hover tooltip

### Approach

OTAPI doesn't fire on mouse move. Use a TTimer polling
`Mouse.CursorPos`:

1. `TDragLintHoverTracker` — class with a TTimer (interval 200ms)
2. Each tick:
   - Get screen cursor position
   - Find which IOTAEditView contains that screen point
   - Translate to row/col via `IOTAEditView.PosToCharPos` (or compute
     from `View.LeftColumn` + `View.TopRow` + cell size)
   - Look up diagnostics in the v0.29 cache for that row/col
   - If a diagnostic is under the cursor AND cursor is stable for ≥3
     ticks (600ms): show `Application.HintWindow.ActivateHint` with the
     message
   - On any cursor move, hide the hint

### Implementation note

This is fragile (OTAPI doesn't expose pixel→cell translation directly).
v0.35 ships best-effort:
- If precise translation fails, fall back to showing the hint when
  hovering over ANY part of a row that has a diagnostic.

### New unit

`src/delphi-plugin/DragLint.Plugin.HoverTracker.pas`:
- Singleton timer started in `RegisterDragLintMenu`
- Stopped in `UnregisterDragLintMenu`
- Settings: `EnableHoverTooltip` (default True)

## 3. F2 — README rewrite

Rewrite the top-level `README.md` to be a real getting-started guide.
Sections:

1. **What is drag-lint?** — 2 paragraph elevator pitch
2. **Architecture** — diagram of CLI ↔ LSP ↔ MCP ↔ IDE Plugin
3. **Install (3 paths)**:
   - Standalone CLI (download .exe + DLLs)
   - LSP server for Zed / VS Code (point to drag-lint.exe + DB)
   - RAD Studio plugin (install BPL)
4. **CLI command reference** — table of all 25+ commands with one-line
   descriptions
5. **MCP tools** — list of all 14+ tools
6. **Lint rule pack** — list of ~20 built-in rules
7. **Plugin features** — Tools menu, keystrokes, settings
8. **Version history** — link to CHANGELOG

## 4. F3 — 8 more lint rules

Add to `rules/`:

1. `string-concat-loop` — string concat inside a for loop (perf)
2. `freeandnil-missing` — `X.Free` without `X := nil` (semi-pattern)
3. `tobject-cast` — `as TObject` (redundant)
4. `pos-with-substring` — `Pos(' ', S) > 0` (clearer with `S.Contains`)
5. `single-line-if-then` — `if X then Y;` (style preference)
6. `boolean-comparison` — `X = True` (redundant)
7. `repeat-without-until` — programmatic check
8. `inherited-without-args` — `inherited;` without args

For each, write the .scm + .json. For ones that are too hard to
express, skip and document.

## 5. New units

- `src/delphi-plugin/DragLint.Plugin.HoverTracker.pas`

## 6. Modified

- `src/delphi-plugin/DragLint.Plugin.Editor.pas` — register HoverTracker
- `src/delphi-plugin/DragLint.Plugin.Settings.pas` — EnableHoverTooltip
- `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` + OptionsFrame —
  checkbox
- `README.md` — full rewrite
- `rules/` — 8 new pairs (or fewer if some are infeasible)

## 7. Stop criteria

### Auto-verifiable

1. T61 — HoverTracker compile smoke.
2. T62 — new lint rules fire on RuleTest.pas or supplementary fixtures.
3. BPL builds clean.
4. All prior tests pass.

### Manual

5. After install, hovering over a marked diagnostic in editor for 0.6s
   shows a tooltip with the message.
6. README renders properly on GitHub.

## 8. Out of scope (no further versions planned)

- Pre-built MSI installer (use the current "Component → Install
  Packages" path)
- macOS RAD Studio
- Real-time syntax check
- Inheritance-aware refactoring
- Symbol-id-based precision rename

## 9. After v0.35

This is the final version of this marathon. After it ships:
- 20 versions live on GitHub (v0.16 through v0.35)
- Comprehensive README
- ~20 lint rules
- Full IDE integration with diagnostics + code lens + structure +
  workspace + refactoring

Future work needs its own brainstorm/spec/plan cycle in a fresh session.

## 10. Push cadence

Spec → push. Each feature → push. Tag + release after all three.
