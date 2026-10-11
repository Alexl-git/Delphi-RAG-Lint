# compare

Reruns a saved or pasted report against the current index and shows what changed:
before, delta, after. Reach for it when a DocInsight report in a unit, a tester
sheet or a chart may have gone stale and you want to know whether it is still
true -- without rereading it by eye.

## What it answers

"Is this report still true?" A report that `Ask-Report.ps1 -Plain` (or
`Format-ReportAsDocInsight`) produced carries the exact question that made it on a
`COMMAND` line. `compare` reads that line, asks the same question again through the
current engine and diffs the two answers: a report by its normalised text, a forms
CSV by row, a chart by its nodes and edges.

## Running it from the CLI

```
drag-lint compare --old <report.txt|forms.csv|bundle dir> [--command "<id> -Target T -Project P ..."] [--project <P.dproj>]
                  [--new <same kind>] [--old-db <old.sqlite>] [--auto] [--save] [--snapshot-dir <dir>]
                  [--format text|json|html] [--output <file>] [--open]
drag-lint compare --in <U.pas> --line <L> [--update-doc]
drag-lint compare --show <report|csv|bundle> [--output <f.html>] [--open]
drag-lint compare --question <id> --target <T> --project <P.dproj> --save [--auto]
```

| Flag | Meaning |
|---|---|
| `--old <f>` | The old side: a saved plain report, a forms CSV, a `.dot` chart or a bundle folder (the folder holding `graph.dot` / `graph.svg`). |
| `--new <f>` | With `--old`: compare two saved outputs. Nothing is rerun. |
| `--command "<id> ..."` | The question to rerun, in the `COMMAND` line syntax without the word `COMMAND`. Needed when the old report has no `COMMAND` line; when both exist and differ, a warning names every differing argument and this one wins. |
| `--question <id> --target <T>` | Builds the command for you (`<id> -Target "<T>" -Project "<P>"`). |
| `--project <P.dproj>` | Replaces or adds `-Project` on the command that is run. |
| `--in <U.pas> --line <L>` | The old side is the `/// <remarks>` block around line `L` of the unit (S1). |
| `--update-doc` | With `--in/--line`: rewrite that block with the new answer in DocInsight form. Only that block changes. |
| `--old-db <old.sqlite>` | The old side is the same question answered from an old copy of the index (S4). The old copy is allowed to be stale. |
| `--auto` | The old side is the newest auto snapshot of this question (S3). |
| `--save` | Keep the new answer as a snapshot. With `--auto` it goes into `auto\`. Without any old side it just takes the snapshot. |
| `--snapshot-dir <dir>` | Where snapshots live; default is described below. |
| `--show <f>` | Render one report, CSV or bundle as the HTML page, no rerun. Takes no other source. |
| `--format text\|json\|html` | Output format (default `text`); `--open` alone means `html`. |
| `--output <file>` | Write there instead of stdout (HTML always goes to a file). |
| `--open` | Open the HTML page in the default browser. |
| `--db <file>` | Pin the index the new run reads. |

Exactly one old side may be named: `--old`, `--in`, `--old-db` or `--auto`.

## The report header (contract)

The first two lines of a plain answer are:

```
Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32, engine 1.27.0.
COMMAND who-writes -Target "OPERAT.NAME" -Project "C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj" -Depth 3
```

`COMMAND <id> [-Target "v"] [-To "v"] (-Project "v" | -In "v") [-Depth n] [-Cap n]
[-SurfaceCap n] [-Control "v"] [-Mode v] [-MaxRows n]` lists only the arguments the
caller gave explicitly, in that fixed order. In a unit the same two lines appear as
`///` comment lines (the `COMMAND` line XML-escaped and never wrapped). A report
without them is a legacy report: it parses with an empty time, engine and command,
and `compare` warns "The original command is unknown -- this may not be the same
question." unless you pass `--command`.

"Same question" means: the ids are equal, both commands name the same arguments, and
a value that reads as an integer compares as a number, anything else compares
ignoring case. Order and quoting never matter. `-Depth 3` against no `-Depth` is a
difference; it is named in a warning, never a refusal.

## What the diff ignores

Step numbers, `:line` anchors, the header's date and engine, the `BUNDLE`, `INDEX`,
`AS OF` and `REGENERATE` lines, wrapping, trailing spaces, and line-end style (CRLF,
LF or CR, with or without a UTF-8 BOM). A report saved by a foreign editor therefore
does not differ from an identical CRLF copy.

## The old sides

1. **A file** (`--old`): report, forms CSV, `.dot` or a bundle folder.
2. **The remarks block at the caret** (`--in/--line`, S1): only that block is the old
   side, and only that block is rewritten by `--update-doc`; a unit with two blocks
   keeps the other untouched. A block that is not a drag-lint report is refused.
3. **The newest auto snapshot** (`--auto`, S3): the snapshot's own `COMMAND` counts as
   the old one; the command you give only locates the snapshot.
4. **An old index** (`--old-db`, S4): the question is answered from that copy with
   `-AllowStale`, then again from the current index.
5. **Two files** (`--old` with `--new`): nothing is rerun, so `--save` is refused.

The new run NEVER accepts a stale index. If the index is stale you get exit `3` and no
diff, because comparing against a stale answer is how a report is declared true when
it is not.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | No differences. |
| 1 | Differences found. |
| 2 | Usage or setup error (no old side, no `COMMAND`, unreadable file, mixed formats, the producer failed). |
| 3 | The index of the new run is stale. |

On 2 and 3 `ERROR: <message>` goes to stderr first and, with `--format json`, the JSON
document is still written to stdout, so a machine caller always gets the envelope.

## Output formats

* **text** -- `WARNING:` lines, the OLD and NEW header lines, a `--- before / +++ after`
  summary, the delta in unified form (`=` unchanged, `-` removed, `+` added) and
  `result: ... (exit N)`. For a chart, four lists: nodes and edges added and removed.
* **json** -- one line, schema `compare/1`. Every key is always present.
* **html** -- a self-contained page (no script, no external resource) that follows the
  light or dark setting of the browser. A chart is shown with the added nodes and
  edges marked, and the old chart in a collapsed section with the removed ones faded.
  Written to `--output`, else
  `%TEMP%\drag-lint-reports\compare-<question>-<target>-<yyyymmdd-hhmm>.html`; the path
  is printed.

## Snapshots and `drag-lint-reports\` + `auto\`

A snapshot is a plain report (`.txt`), a forms CSV (`.csv`) or a chart's DOT text
(`.dot`) kept so a later run has an old side. The folder is the project's
`reportsDir` from `_D-RAG\drag-lint-project.json`, else `drag-lint-reports` beside
the project. Commit the folder; ignore `auto\` -- automatic snapshots are kept per
question and target, newest 20, and are a local convenience, not a record.

`--save --auto` before any auto snapshot exists simply takes the first one.

## Known limits

* A very long unbroken token in a report is cut for the HTML view; the diff still sees it.
* In a chart, edges are identified by their endpoint titles, so two different edges
  between the same pair of nodes count as one.
* The new answer comes from `charts\src\Ask-Report.ps1 -Plain` run in a PowerShell 7
  child process; without `pwsh` the verb exits `2` with the reason. A non-ASCII
  character in a report depends on that script's console encoding.
