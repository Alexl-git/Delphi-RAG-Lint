> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (73c441c): reports per unmatched selector, lists selectable sections, exits 2. Guarded by run_cli_narrowing_is_reported.ps1 (9/9).

# INBOX -- `index --all --only <name>` that matches nothing does nothing, and exits 0

**Found:** 2026-08-12, while starting the library rebuilds.
**Severity:** medium, but it is the highest-cost SHAPE this project keeps hitting --
a command that appears to succeed while doing nothing.

## Symptom

```
drag-lint index --all --only "Library[Win32]" --rebuild
```

exits **0**, prints nothing to stdout, and indexes nothing. Launched detached, the
process vanishes in under a second and the log is empty, which reads exactly like
"it finished".

`--dry-run` shows the truth:

```
> drag-lint index --all --only "Library[Win32]" --dry-run
  Sections to build: 0

> drag-lint index --all --only "Library" --dry-run
  Sections to build: 2
    [Library[Win32]] mode=library db=...\library-Win32.sqlite
    [Library[Win64]] mode=library db=...\library-Win64.sqlite
```

So `--only` matches by PREFIX/substring against the section name, and the full
name as PRINTED (`Library[Win32]`) is not itself an accepted value. Passing the
name the tool displays selects nothing.

## Why this matters more than it looks

This is the same failure shape as the already-recorded trap where `index --all`
resolves its manifest relative to the EXE's own directory, so a freshly built exe
with no `drag-lint.json` beside it "indexes nothing and exits 0" -- which once
faked an entire regression. A silent no-op on a long-running command is
expensive: you come back hours later to an index that was never built, and every
downstream measurement taken in the meantime is wrong.

## Fix

1. **`--only` matching nothing must be an ERROR** (exit non-zero) naming what was
   passed and listing the section names that exist. There is no legitimate reason
   to ask for a section by name and be pleased that it did not exist.
2. Accept the name as printed. `Library[Win32]` appears in `--dry-run` output and
   in the section header; a user pasting it back should get that one section.
   Either make the bracketed form match exactly, or stop printing a form that is
   not accepted as input.
3. Consider the same audit for every other filter flag that silently narrows to
   an empty set.

## Workaround

`--only Library` selects both platform sections. With `--jobs 2` they build in
parallel (parallelism is per SECTION, so two sections is exactly two jobs).
