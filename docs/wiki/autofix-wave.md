# Autofix for fixable rules

`drag-lint lint --fix` repairs the findings of the 111 fixable lint rules (`drag-lint rules --json` marks them `fixable`). The fixers are grouped: expression-level, statement and block, declaration and directive, hygiene, and store-backed ones that consult the index.

## Running it from the CLI
```
drag-lint lint --in <file.pas> --fix                 (dry run: reports the edits, writes nothing)
drag-lint lint --in <file.pas> --fix --apply         (writes the edits)
drag-lint lint --in <file.pas> --fix --json          (per finding: was it applied)
drag-lint lint <folder> --fix --apply                (every scanned .pas / .inc / .dpr)
drag-lint lint-all --db <db> --fix --apply           (the whole project)
```
`--fix-line` with `--fix-rule` narrows the fix to one finding. `--json` reports each finding as applied or not, keyed by the finding itself, so a fix whose edits sit on other lines still counts as applied. Overlapping fixes are deferred to the next run. A store-backed fixer declines without `--db`. `uses-movable-to-implementation` and a few risky fixes are opt-in.

## Reaching it in the IDE
The Structure form's right-click Fix it / Fix all in unit run the same fixers; see Fix-it and Fix-all-in-unit.

## What it needs
Nothing for the file-level fixers; `--db <index.sqlite>` for the store-backed ones.
