---
id: gain-usage-log
title: Gain (counted savings)
summary: "Sums the per-user usage log: tokens returned versus source bytes avoided, per verb and per day"
product: DL
group: search-navigation
order: 20011
since: 1.38.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Gain (counted savings)

Sums the per-user usage log: tokens returned versus source bytes avoided, per verb and per day.

Read this to see what the index saves: gain sums the usage log that context, query and find-callers append to, per verb and per day, as tokens returned against the source they stood in for.

## How to run it

Full flag list: [gain in the CLI reference](../cli.md#gain).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--since` | `yyyy-mm-dd` |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Pitfalls

* tokens_returned is measured only for context and query --text; the other readers are estimated at 15 tokens per row
* The log is per user and best effort: an unwritable LOCALAPPDATA loses lines silently by design

## Details

Counts what the index saved. Every reader verb that answers from the index
(`context`, `query --name`, `query --text`, `query find-callers`) appends one
tab-separated line to the per-user usage log, and `gain` sums that log per verb
and per day. Reach for it to see how many tokens the answers cost against the
source files they stood in for.

### Running it from the CLI
```text
drag-lint gain [--since yyyy-mm-dd] [--json]
```
`--since` drops log lines older than the date; `--json` emits one object with
`total`, `by_verb` and `by_day`.

### The log
`%LOCALAPPDATA%\drag-lint\usage.log`, one line per verb run:

```text
ISO8601-UTC <TAB> verb <TAB> db_tag <TAB> tokens_returned <TAB> units_avoided <TAB> bytes_avoided
```

* `tokens_returned` is measured for `context` (the bundle's token estimate) and
  `query --text` (printed characters / 4); the other readers are estimated at 15
  tokens per result row.
* `bytes_avoided` is the size of the distinct source files the answer stood in
  for (the target's unit plus each caller's unit for `context`; the distinct
  `file_path` of the rows for the others).
* `tokens_avoided` is derived by `gain` as `bytes_avoided / 4`; the ratio is
  `tokens_avoided / tokens_returned`.

The log is best effort: a missing or read-only `%LOCALAPPDATA%` never changes a
verb's output or exit code. Set `DRAGLINT_USAGE_LOG=0` to turn it off.

### What it needs
No index. `gain` only reads the log; a missing log is an all-zero report.

### Example
Illustrative only:
```text
drag-lint gain --since 2026-10-01
```
This would print the calls, tokens returned, tokens avoided and ratio per verb
and per day since 1 October 2026.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
