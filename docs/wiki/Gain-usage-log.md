# Gain (counted savings)

Counts what the index saved. Every reader verb that answers from the index
(`context`, `query --name`, `query --text`, `query find-callers`) appends one
tab-separated line to the per-user usage log, and `gain` sums that log per verb
and per day. Reach for it to see how many tokens the answers cost against the
source files they stood in for.

## Running it from the CLI
```
drag-lint gain [--since yyyy-mm-dd] [--json]
```
`--since` drops log lines older than the date; `--json` emits one object with
`total`, `by_verb` and `by_day`.

## The log
`%LOCALAPPDATA%\drag-lint\usage.log`, one line per verb run:

```
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

## What it needs
No index. `gain` only reads the log; a missing log is an all-zero report.

## Example
Illustrative only:
```
drag-lint gain --since 2026-10-01
```
This would print the calls, tokens returned, tokens avoided and ratio per verb
and per day since 1 October 2026.
