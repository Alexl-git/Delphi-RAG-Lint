---
id: autofix-wave
title: Autofix for fixable rules
summary: lint --fix repairs findings of the 111 fixable rules; --json reports per finding whether it was applied; lint accepts a folder
product: DL
group: linting
order: 30001
since: 1.37.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Autofix for fixable rules

lint --fix repairs findings of the 111 fixable rules; --json reports per finding whether it was applied; lint accepts a folder.

Read this when you want drag-lint to repair findings instead of only reporting them. A dry run shows the edits, --apply writes them, and the JSON result says for each finding whether a fix was applied.

## How to run it

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

`drag-lint lint --fix` repairs the findings of the 111 fixable lint rules (`drag-lint rules --json` marks them `fixable`). The fixers are grouped: expression-level, statement and block, declaration and directive, hygiene, and store-backed ones that consult the index.

### Running it from the CLI
```text
drag-lint lint --in <file.pas> --fix                 (dry run: reports the edits, writes nothing)
drag-lint lint --in <file.pas> --fix --apply         (writes the edits)
drag-lint lint --in <file.pas> --fix --json          (per finding: was it applied)
drag-lint lint <folder> --fix --apply                (every scanned .pas / .inc / .dpr)
drag-lint lint-all --db <db> --fix --apply           (the whole project)
```
`--fix-line` with `--fix-rule` narrows the fix to one finding. `--json` reports each finding as applied or not, keyed by the finding itself, so a fix whose edits sit on other lines still counts as applied. Overlapping fixes are deferred to the next run. A store-backed fixer declines without `--db`. `uses-movable-to-implementation` and a few risky fixes are opt-in.

### What it needs
Nothing for the file-level fixers; `--db <index.sqlite>` for the store-backed ones.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
