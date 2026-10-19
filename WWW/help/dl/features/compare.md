---
id: compare
title: Compare a report with current code
summary: Reruns a saved or pasted report and shows before / delta / after
product: DL
group: diagrams-charts
order: 80005
since: 1.28.0-alpha
status: shipped
updated: 1.26.7-alpha
---

# Compare a report with current code

Reruns a saved or pasted report and shows before / delta / after.

Read this when a DocInsight report, a tester sheet or a chart may have gone stale: compare reruns its COMMAND against the current index and diffs the normalised text, a forms CSV by row, or a chart by nodes and edges.

## How to run it

Full flag list: [compare in the CLI reference](../cli.md#compare).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--old` | `<report.txt\|forms.csv\|bundle dir>` |  |  |
| `--command` |  |  |  |
| `--project` | `<P.dproj>` |  |  |
| `--new` | `<same kind>` |  |  |
| `--old-db` | `<old.sqlite>` |  |  |
| `--db` | `<new.sqlite>` |  |  |
| `--auto` |  |  |  |
| `--save` |  |  |  |
| `--snapshot-dir` | `<dir>` |  |  |
| `--format` |  |  |  |
| `--output` | `<file>` |  |  |
| `--open` |  |  |  |

**Needs:** index

## Details

Reruns a saved or pasted report against the current index and shows what changed:
before, delta, after. Reach for it when a DocInsight report in a unit, a tester
sheet or a chart may have gone stale and you want to know whether it is still
true -- without rereading it by eye.

### What it answers

"Is this report still true?" A report that `drag-lint ask` (plain or DocInsight) produced carries the exact question that made it on a
`COMMAND` line. `compare` reads that line, asks the same question again through the
current engine and diffs the two answers: a report by its normalised text, a forms
CSV by row, a chart by its nodes and edges.

### Running it from the CLI

```text
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
| `--db <file>` | Pin the index the new run reads. A question that also reads the SERVER or SQL-script index (`round-trip`, `lands-where`, `consumers`, `feeds-from`) pairs it from `report-pairs.json`, exactly as `ask` does; no pair is exit 2 with its message. |

Exactly one old side may be named: `--old`, `--in`, `--old-db` or `--auto`.

### The report header (contract)

The first two lines of a plain answer are:

```text
Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32, engine 1.27.0.
COMMAND who-writes -Target "OPERAT.NAME" -Project "C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj" -Depth 3
```

`COMMAND <id> [-Target "v"] [-To "v"] (-Project "v" | -In "v") [-Depth n] [-Cap n] [-SurfaceCap n] [-Control "v"] [-Mode v] [-MaxRows n]` lists only the arguments the
caller gave explicitly, in that fixed order. In a unit the same two lines appear as
`///` comment lines (the `COMMAND` line XML-escaped and never wrapped). A report
without them is a legacy report: it parses with an empty time, engine and command,
and `compare` warns "The original command is unknown -- this may not be the same
question." unless you pass `--command`.

"Same question" means: the ids are equal, both commands name the same arguments, and
a value that reads as an integer compares as a number, anything else compares
ignoring case. Order and quoting never matter. `-Depth 3` against no `-Depth` is a
difference; it is named in a warning, never a refusal.

### What the diff ignores

Step numbers, `:line` anchors, the header's date and engine, the `BUNDLE`, `INDEX`,
`AS OF` and `REGENERATE` lines, wrapping, trailing spaces, and line-end style (CRLF,
LF or CR, with or without a UTF-8 BOM). A report saved by a foreign editor therefore
does not differ from an identical CRLF copy.

### The old sides

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

### Exit codes

| Code | Meaning |
|---|---|
| 0 | No differences. |
| 1 | Differences found. |
| 2 | Usage or setup error (no old side, no `COMMAND`, unreadable file, mixed formats, a chart that parses as empty, the producer failed, or any unexpected error inside the verb). |
| 3 | The index of the new run is stale. |

On 2 and 3 `ERROR: <message>` goes to stderr first and, with `--format json`, the JSON
document is still written to stdout, so a machine caller always gets the envelope. An
unexpected error inside the verb is reported as `ERROR: <class>: <message>` with exit 2
(never 3, which means only "stale index"), and its envelope goes to stdout even when
`--output` was given, since writing `--output` may be what failed.

### Output formats

* **text** -- `WARNING:` lines, the OLD and NEW header lines, a `--- before / +++ after`
  summary, the delta in unified form (`=` unchanged, `-` removed, `+` added) and
  `result: ... (exit N)`. For a chart, four lists: nodes and edges added and removed.
* **json** -- one line, schema `compare/1`. Every key is always present.
* **html** -- a self-contained page (no script, no external resource) that follows the
  light or dark setting of the browser. Its `Content-Security-Policy` meta allows inline
  styles and `data:` images only. A chart's `graph.svg` is inlined only when it passes a
  safety check (the same for `--show`); otherwise it is withheld -- see Known limits. A chart is shown with the added nodes and
  edges marked, and the old chart in a collapsed section with the removed ones faded.
  Written to `--output`, else
  `%TEMP%\drag-lint-reports\compare-<question>-<target>-<yyyymmdd-hhmm>.html`; the path
  is printed.

### Snapshots and `drag-lint-reports\` + `auto\`

A snapshot is a plain report (`.txt`), a forms CSV (`.csv`) or a chart's DOT text
(`.dot`) kept so a later run has an old side. The folder is the project's
`reportsDir` from `_D-RAG\drag-lint-project.json`, else `drag-lint-reports` beside
the project. Commit the folder; ignore `auto\` -- automatic snapshots are kept per
question and target, newest 20, and are a local convenience, not a record.

`--save --auto` before any auto snapshot exists simply takes the first one.

### Known limits

* A very long unbroken token in a report is cut for the HTML view; the diff still sees it.
* In a chart, edges are identified by their endpoint titles, so two different edges
  between the same pair of nodes count as one.
* The new answer is produced in-process by the engine; no PowerShell is needed or started.
* A forms CSV is compared only as two saved files (`--old a.csv --new b.csv`): no
  question reruns into a CSV, so `--old a.csv` alone has nothing to compare it with.
* `--save --open` is refused: `--save` with no old side only takes a snapshot, and a
  snapshot alone cannot render a page.
* A `COMMAND` line recorded from a `-DbPath` run carries no `-Project` or `-In`, so its
  rerun needs `--project <P.dproj>` or `--db <index>` on the compare command line.
* A chart DOT is read in the emitters' dialect (one node statement per box with an HTML
  label; bare or double-quoted ids). A non-blank DOT that yields no node and no edge is
  refused (exit 2, "parsed as empty") rather than compared as "no differences".
* Security: a `graph.svg` is untrusted (it may come from a committed snapshot), so it is
  inlined only when nothing in it can run script, navigate, restyle the page or leave SVG
  parsing -- graphviz output always passes. Anything else (`<script>`, `<foreignObject>`,
  `<meta>`, `<style>`, an `on*` attribute, a link that is not `draglint:` or `#`,
  content after the first `</svg>`, ...) WITHHOLDS the image: the page shows
  `chart image withheld: the SVG contains content that is not allowed (<reason>)` and the
  lists of changes, and text / JSON output carry the same line as a warning. Nothing is
  stripped and then inlined.

### Determinism (N5) status

N5: the same question asked twice on the same index must compare empty; a non-empty diff is a defect in the report, not in Compare. Measured 2026-10-11 by `charts\src\Test-Parity.ps1 -Mode Determinism` on the frozen clones: **26/26 deterministic**. `architecture` failed the first run (zones of equal size were ordered by per-process hashtable key order) and was fixed by an ordering-only tie-break in `Emit-Architecture.ps1` (commit b2da70e9). Seconds are the PowerShell producer's wall time per run.

| question | run 1 s | run 2 s | N5 |
|---|---|---|---|
| butterfly | 4.4 | 3.6 | PASS |
| deps | 3.6 | 4.1 | PASS |
| who-calls | 4 | 3.2 | PASS |
| what-it-calls | 3.7 | 3.1 | PASS |
| who-writes | 4.7 | 5 | PASS |
| who-reads | 3.5 | 4.1 | PASS |
| hierarchy | 4 | 3.2 | PASS |
| class-surface | 4.1 | 4.4 | PASS |
| event-wiring | 4.6 | 4.3 | PASS |
| touches-tables | 3.8 | 3.6 | PASS |
| lifecycle | 4.3 | 4 | PASS |
| cycles | 3.3 | 3.7 | PASS |
| wiring | 3.9 | 4.1 | PASS |
| effects | 3.6 | 2.9 | PASS |
| architecture | 6.8 | 6.5 | FAIL, fixed b2da70e9; re-run 7.9 / 6.1 PASS (x3) |
| protocol-trace | 4.6 | 4.3 | PASS |
| crosses-boundary | 5 | 5.1 | PASS |
| shown-where | 3.3 | 3.5 | PASS |
| change-impact | 5.4 | 4.7 | PASS |
| tested-by | 3.9 | 3.8 | PASS |
| exception-paths | 10.2 | 10.8 | PASS |
| consumers | 12.9 | 12.2 | PASS |
| feeds-from | 111.5 | 112.8 | PASS |
| lands-where | 119 | 116.3 | PASS |
| round-trip | 61.9 | 58.7 | PASS |
| path | 4.3 | 4.6 | PASS |

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
