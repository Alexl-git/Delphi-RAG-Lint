---
id: v152-per-rule-budget
title: Per-rule time budget in the rule frame (rule-skipped-budget)
summary: A v151/v152 rule slower than rule_time_budget_ms (2000 ms) on a file is skipped there with one rule-skipped-budget note; index warns near the parse limit
product: DL
group: linting
order: 30070
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Per-rule time budget in the rule frame (rule-skipped-budget)

A v151/v152 rule slower than rule_time_budget_ms (2000 ms) on a file is skipped there with one rule-skipped-budget note; index warns near the parse limit.

Read this when a lint run shows a rule-skipped-budget note, when you want to change or turn off the per-rule time budget, or when index warns that a unit is near the parse limit.

## How to run it

```text
drag-lint lint <file.pas> [--config <lint.json>] [--no-budget] (lint config key rule_time_budget_ms, default 2000 ms per rule per file, 0 = off; --no-budget or DRAGLINT_NO_BUDGET=1 = off; an overrunning rule is skipped for the file with one rule-skipped-budget note: category other, info, on)
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint lint-all --db <file.sqlite> [--no-budget] (same budget; one "rule budget:" note line lists the skipped rules of the run)
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

```text
drag-lint index --project <X.dproj> --db <file.sqlite> (prints a WARN line for a unit within 10% below settings.maxParseFileKB, default 2048 KB)
```

Full flag list: [index in the CLI reference](../cli.md#index).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--config` | `<file>` |  |  |
| `--no-budget` |  |  |  |
| `--no-budget` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

One slow rule on one huge unit used to hold up a whole `lint-all` (a v151 rule once took
148-166 s on a 20k-line file). Since 1.52 the v151/v152 rule frame gives every rule a time
budget per file: a rule that needs longer than the budget on a file is skipped for that
file, and the file gets one `rule-skipped-budget` note that names it.

### The budget

| Setting | Meaning |
|---|---|
| default | 2000 ms per rule per file |
| `"rule_time_budget_ms": 5000` in the lint config (`drag-lint-lint.json`, or `--config`) | another budget |
| `"rule_time_budget_ms": 0` | budget off: no rule is ever skipped |
| `--no-budget` on `lint` / `lint-all` | budget off for this run (release measurements) |
| environment `DRAGLINT_NO_BUDGET=1` | budget off for the process (same as `--no-budget`) |

The budget is wall time, measured in the frame: each `Wants(<rule>)` a lane makes before it
computes a rule starts that rule's time slice, and the slice ends at the next rule or when
the lane hands control back. Time a lane spends before it asks for any rule is charged to
the lane (`lane:<NAME>` in the note). A running rule is never interrupted -- there is no safe
way to stop it in-process -- so the skip takes effect when the rule returns: its findings
for that file are dropped and it is not asked again for that file (its DFM and raw-byte
passes included).

### What you see

`drag-lint lint Big.pas` on a file where `writeln-in-gui-app` overran:

```text
Big.pas:1:1: info: [rule-skipped-budget] writeln-in-gui-app (2140 ms) exceeded the per-rule
time budget of 2000 ms on this file and was skipped for it; raise rule_time_budget_ms in the
lint config (0 = off) or run with --no-budget to get its findings
```

`lint-all` prints one summary line after its totals when anything was skipped:

```text
rule budget: 3 skip(s) on 2 file(s): dictionary-get-without-check (1 file), writeln-in-gui-app (2 files)
```

`rule-skipped-budget` is category `other`, severity `info`, ON. Disable it like any rule
(`"disabled": ["rule-skipped-budget"]`) to hide the notes; the skips still happen.

### Things to know

- Wall time on a machine at 100% CPU is longer than on an idle one, so a rule near the
  budget can be skipped on one run and not on the next. For a comparison between two
  engines run with `--no-budget` (or budget 0).
- With `--rule <id>` the note is only shown when `<id>` is `rule-skipped-budget`; the
  skipped rule's findings are still dropped.
- Only the v151/v152 rule lanes are budgeted in 1.52; the tree-sitter query rules, the AST
  checks and the project-wide pass are not.

### Near the parse limit

The indexer does not parse a unit larger than `settings.maxParseFileKB` (default 2048 KB):
it prints `SKIP <path>: <n> KB exceeds parse limit` and the unit has no symbols. Since 1.52
a unit within 10% of that limit gets a warning line at index time, so you can split it
before it silently drops out of the index:

```text
  WARN C:\src\Big.pas: 1900 KB is within 10% of the parse limit (2048 KB); a little more code
  and the unit is no longer indexed (settings.maxParseFileKB)
```

Test: `tests\autotest\run_v152_BUDGET.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
