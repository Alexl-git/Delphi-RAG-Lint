# v0.32 — Code Lens + Extended Lint Pack

**Date:** 2026-05-29
**Status:** Design approved
**Branch:** `v0.32-codelens` off `main`

## 1. Goal

Two independent features:

1. **Inline code lens** — paint `[N callers]` next to each method
   declaration in the editor view.
2. **Extended lint pack** — 6 more built-in tree-sitter-query rules on
   top of v0.28 + v0.31.

## 2. F1 — Code lens

### Paint flow

In `TDragLintEditViewNotifier.PaintLine` (from v0.29), after the
existing diagnostic paint:

1. Query the symbol cache (new): does this row contain a method/proc/
   function declaration?
2. If yes: query `FindCallersByName(symbol.name)` to get caller count.
3. Cache the count per (file, line) to avoid re-query every repaint.
4. Paint dim grey `[N callers]` text at the end of the line (after the
   text width).

### New module

`src/delphi-plugin/DragLint.Plugin.CodeLensCache.pas`:
- Singleton `TDragLintCodeLensCache`
- `function GetForLine(AFilePath: string; ALine: Integer): string`
  - Returns "[N callers]" or ""
- Background populate via `IOTAEditServicesNotifier.EditorViewActivated`:
  - When a file becomes active, query its symbols + caller counts once,
    cache per (file, line)

### Settings

`TDragLintSettings.EnableCodeLens: Boolean` (default True).

### Performance guard

Code lens caches per file. Repaint reads from cache only. Cache
invalidated on `BufferSaved` (file write).

## 3. F2 — Extended lint pack (6 more rules)

### 3.1 `nested-with`

Nested `with` statements multiply the scope-ambiguity problem.

`rules/nested-with.scm`:
```
(with
  body: (_
    (with) @inner) @outer)
```

### 3.2 `compiler-magic-comments`

Comments containing TODO/FIXME/HACK/XXX. Useful complementary signal.

```
((comment) @warn
  (#match? @warn "TODO|FIXME|HACK|XXX"))
```

### 3.3 `try-without-finally`

Detect a `try` that's not paired with `finally`. Hard to express in
pure .scm. Programmatic AST check.

(Skip if not feasible in pure query syntax for v0.32.)

### 3.4 `inherited-without-class`

`inherited` used outside a class method body. Pure programmatic check
— skip in v0.32 if AST walking is too heavy.

### 3.5 `large-method` (configurable threshold)

Methods with body > 50 lines.

Programmatic check via `TLargeMethodFinder` (new module). For each
`defProc`, measure body line count. If > threshold (settings field),
flag.

### 3.6 `assert-without-message`

`Assert(condition)` without the second argument is harder to debug.

```
((exprCall
   entity: (identifier) @callee
   arguments: (exprArgs (_) @first . ) @args)
   (#eq? @callee "Assert"))
```

The single-arg detection is harder. Pure version:
```
((exprCall
   entity: (identifier) @callee
   arguments: (exprArgs) @args)
   (#eq? @callee "Assert"))
```

(Catches all Assert calls; false-positive for ones with 2 args.
Acceptable for v0.32; v0.33 may refine.)

### 3.7 `case-magic-numbers`

Integer literals inside case branches. `case X of 42: ...` is harder
to debug than `case X of NAMED_CONST: ...`.

```
(case
  (caseCase
    label: (caseLabel
      (literalNumber) @lit)))
```

## 4. New units

- `src/delphi-plugin/DragLint.Plugin.CodeLensCache.pas`

## 5. Modified

- `src/delphi-plugin/DragLint.Plugin.EditViewNotifier.pas` — paint code lens
  in PaintLine; settings gate
- `src/delphi-plugin/DragLint.Plugin.Settings.pas` — add EnableCodeLens
- `src/delphi-plugin/DragLint.Plugin.SettingsForm.pas` + `OptionsFrame` — checkbox
- `rules/` — 6 new pairs (5 if `try-without-finally` not feasible)

## 6. Stop criteria

### Auto-verifiable

1. New rules fire on RuleTest.pas + supplementary fixtures.
2. T55 — code lens cache smoke test.
3. BPL builds clean.
4. All prior tests pass.

### Manual

5. After install, opening a file with documented public methods shows
   `[N callers]` annotations next to declarations.
6. Toggling `EnableCodeLens` setting removes annotations on next repaint.

## 7. Out of scope (v0.33+)

- Mouse-hover tooltip
- Find-usages tree view
- Workspace mode
- MSI installer

## 8. Push cadence

Spec → push. F1 + F2 land → push. Tag + release.
