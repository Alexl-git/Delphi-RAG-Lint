---
id: ask
title: ask
summary: Ask one report question and print the answer as text
product: DL
group: diagrams-charts
order: 80001
since: 1.30.0-alpha
status: shipped
updated: 1.26.1-alpha
---

# ask

Ask one report question and print the answer as text.

Read this when you want a report answer on stdout -- drag-lint ask <question> --target <T> --project <P.dproj> prints the DocInsight block the Reports menu copies (or the plain answer with --plain). Every question is answered inside the engine; no PowerShell is needed.

## How to run it

Full flag list: [ask in the CLI reference](../cli.md#ask).

## Where to click

* RAD Studio main menu: **drag-lint > Reports**

**Needs:** index, graphviz

## Details

Asks one report question -- who writes this field, which tables this routine
touches, what this unit depends on, and the other 23 -- and prints the answer as
text. Reach for it when you want the answer on stdout (an agent, a script, a
terminal) rather than in the IDE: it is the same answer the **drag-lint > Reports**
menu puts on the clipboard, because that menu now runs this verb.

### What it answers

Every question of the chart pipeline, by id:

`butterfly`, `who-calls`, `what-it-calls`, `path`, `effects`, `touches-tables`,
`exception-paths`, `crosses-boundary`, `protocol-trace`, `change-impact`,
`tested-by`, `who-writes`, `who-reads`, `feeds-from`, `lands-where`,
`round-trip`, `class-surface`, `hierarchy`, `wiring`, `event-wiring`,
`lifecycle`, `deps`, `architecture`, `cycles`, `consumers`, `shown-where`.

Each id has its own page (`ask-<id>`) saying what to select and how to read
the chart.

### Running it from the CLI

```text
drag-lint ask <question> --target <T> [--project <P.dproj> | --in <U.pas> | --db <index>]
              [--to <routine B>] [--server-db <idx>] [--sql-db <idx>] [--counterpart-db <idx>]
              [--depth N] [--cap N] [--surface-cap N] [--control <C>] [--mode write|read|both] [--max-rows N]
              [--out-root <dir>] [--pairs-file <report-pairs.json>] [--allow-stale] [--plain] [--open] [--resolve-only]
```

| Flag | Meaning |
|---|---|
| `<question>` | The question id (any case; it is matched and lower-cased). `--question <id>` works too. |
| `--target <T>` | What the question is about: a routine, field, form control, type, unit, table or column. Required. |
| `--project <P.dproj>` | The project whose index answers, resolved with `resolve-dbs --project`. |
| `--in <U.pas>` | Any unit or form of the project; resolved with `resolve-dbs --in`. When several indexes hold the unit, the one `report-pairs.json` pairs is taken; otherwise pass `--project`. |
| `--db <index>` | The project index itself, skipping resolution (never its freshness check). |
| `--to <B>` | Routine B of the `path` question (`--target` is routine A). |
| `--server-db`, `--sql-db` | The SERVER and SQL-script indexes that `round-trip`, `lands-where`, `consumers` and `feeds-from` also read. Default: the pair in `report-pairs.json`. |
| `--counterpart-db` | The other side of `crosses-boundary`. Default: the pair's other index. |
| `--depth`, `--cap`, `--surface-cap`, `--control`, `--mode` | Passed to the chart, as the question's page describes. |
| `--max-rows N` | Rows printed from the chart (default 80). |
| `--out-root <dir>` | Where the bundle folder (chart, page, trace) is written. Default `%TEMP%\drag-lint-reports`. |
| `--pairs-file <f>` | The pairing file. Default `%APPDATA%\drag-lint\report-pairs.json`, else the repository's `charts\report-pairs.json`. |
| `--allow-stale` | Answer from a stale index anyway, with a note on stderr. |
| `--plain` | Print the plain answer instead of the DocInsight block. |
| `--open` | Open the bundle's `index.html` in the browser. |
| `--resolve-only` | Print the indexes it would read (`PROJECT`, `SERVER`, `SQL`, `COUNTERPART` lines) and stop. |

### What comes back

By default, a DocInsight `/// <remarks>` block ready to paste above a
declaration: the report sentence (question, target, date and time, engine
version), the `COMMAND` line that reruns it, then the findings -- anchors read
`(File.pas:line)`, a capped chart says how many rows it left out.

With `--plain`, the plain answer: the sentence, `COMMAND`, `BUNDLE <folder>`,
one `INDEX <db>` line per index read (`(server)` / `(sql)` / `(counterpart)`
after the first), then the text -- the whole trace for `round-trip`, otherwise a
`CHART` line with the counts, `TARGET <name> @File.pas:line` for the chart's own
selection and one `<name> @File.pas:line` row per result.

Exit codes: 0 answered; 1 the question was refused (the reason is on stderr);
2 setup -- usage, or the indexes could not be resolved (stderr says what to pass
or edit); 3 an index is stale -- stderr names it and prints the incremental
reindex command (`index --project '<p>' --db '<db>'` or `index --all --only <Section>`). It never indexes anything itself. Every refusal line on stderr
starts with `ask-report:`.

### How it answers

All twenty-six questions (`touches-tables`, `shown-where`, `deps`,
`class-surface`, `event-wiring`, `tested-by`, `change-impact`, `crosses-boundary`,
`protocol-trace`, `lifecycle`, `effects`, `feeds-from`, `lands-where`,
`consumers`, `exception-paths`, `who-calls`, `what-it-calls`, `butterfly`, `hierarchy`, `wiring`, `path`, `architecture`, `cycles`, `who-writes`, `who-reads`, `round-trip`) are answered inside the engine, from the live
index. `crosses-boundary` takes its counterpart from `--counterpart-db`, else from
the pair in `report-pairs.json`; with neither it draws the one side and says so, as
the script does. No question is handed to PowerShell: the engine answers
all of them itself, and `charts\src\Ask-Report.ps1 -Plain` stays in the repository
only as an internal parity oracle (not shipped, not a user tool). The text is the same either way: the questions are held to the PowerShell output byte for byte by
the parity harness (`charts\src\Test-Parity.ps1 -Mode Question`).

### Examples

```text
drag-lint ask who-writes --target Blueprint4.TfrmBlueprint4.FNoRecursion --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj
drag-lint ask round-trip --target frmBlueprint4.dxDBGrid1FtrsVNum --project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj --plain
drag-lint ask deps --target uPipeSessionBuilder --in C:\Projects\DB\ORM3\SERVER\uPipeSessionBuilder.pas --open
```

### Related

- [compare](compare.md) -- rerun a saved answer and see what changed.
- [Charts and the IDE](chart-engine-dot-lookup.md) -- the Reports menu, bundles, clickable rows.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
