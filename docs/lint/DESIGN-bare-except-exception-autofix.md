# Design note: auto-name & create exception classes for `bare-except`

Status: **DESIGN ONLY -- not implemented.** Captured 2026-07-15 from a user idea
("might be a good idea for auto-fix"). Needs a `superpowers:brainstorming` pass
before any code, because it introduces a *project convention* (a central
exceptions unit) that does not exist yet -- exactly the kind of creative feature
that must not be built blind.

## The lint being fixed

Rule `bare-except` (severity `info`), e.g. from `uMain.pas`:

```
[I] (1213:5) Bare except (no 'on E: ... do') catches every exception, even
    EOutOfMemory -- catch a specific exception class.  [bare-except]
```

A bare `except ... end` swallows *every* exception (including `EOutOfMemory`,
`EAccessViolation`). The recommended fix is to catch a specific class:
`except on E: ESomeThing do ...`.

## The proposed auto-fix (two moves)

1. **Name an exception class from context.** Look at the guarded code / nearby
   message text and synthesise a class name, e.g. a block that calls
   `LoadFolder` -> `EFolderLoadError`. Fall back to a unit-derived name
   (`E<UnitStem>Error`) when nothing better is inferable.

2. **Create the class once, reuse thereafter.** Declare
   `EFolderLoadError = class(Exception);` in a single **central exceptions unit**
   so the same name is never duplicated across the project. Then rewrite the bare
   `except` into `except on E: EFolderLoadError do <existing body> end;` and add
   the exceptions unit to `uses` (reuse `DLAddUnitsToImplUses`).

## Why this needs a brainstorm first (open questions)

- **Where is the central exceptions unit?** There is no such convention in ORM3
  today. Is it one per project (`<Proj>.Exceptions.pas`), one shared unit, or
  per-layer (CLIENT/SERVER/COMMON)? The dedup registry (names already declared)
  hangs off this answer. The drag-lint index can answer "does class `EX` already
  exist and in which unit" via `query --name EX` -- so dedup is cheap *once the
  home unit is chosen*.
- **Naming heuristic quality.** Auto-named exceptions that are vague
  (`EMainError`) are worse than a hand-picked name. Should the fix *prompt* with
  a suggested name (editable) rather than silently generate? Likely yes -- this is
  a semantic decision, not a mechanical rewrite like H2443 / public-field.
- **Semantics change, not just syntax.** `except` (catch-all) -> `on E: EFoo do`
  *narrows* what is caught. If the block was genuinely meant to swallow
  everything (cleanup that must not propagate), narrowing is wrong. The fix must
  either (a) only offer itself where a re-raise/`on E: Exception` is clearly
  intended, or (b) generate `on E: Exception do` (specific *type*, still broad)
  as the safe default and let the user narrow. This is the crux -- get it wrong
  and the auto-fix introduces bugs.
- **Interaction with existing rules.** `empty-except` / `try-except-swallowed`
  already flag the swallow; the exception-class fix should compose with those,
  not fight them.

## Building blocks that already exist (reuse, don't rebuild)

- `DLAddUnitsToImplUses` (DragLint.Plugin.Editor) -- undoable uses insertion.
- The index answers "is `EFoo` already declared, and where" (`query --name`),
  giving free cross-project dedup once the home unit is decided.
- The `public-field -> property` and `H2443` quick-fixes (shipped 2026-07-15) are
  the template for a caret-line, cache-driven, undoable quick-fix.

## Recommended next step

Run `superpowers:brainstorming` on the two crux questions -- *home unit
convention* and *safe default (narrow to `EFoo` vs keep `on E: Exception`)* --
then spec + TDD it like the other fix-its. Do **not** ship a silent auto-namer.

Related: [DESIGN-table-conversion-visual-aid.md](DESIGN-table-conversion-visual-aid.md)
(the Transfer Editor -- the other paused visual-tool idea).
