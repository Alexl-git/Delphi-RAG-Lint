# ask: risk

**Which complex routines do the tests leave uncovered.** A CRAP-style score per routine from the cyclomatic
complexity in the index and the coverage imported with [import-coverage](import-coverage). One of the diagram
questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts).

## Asking it

```
drag-lint import-coverage --file <report.xml> --db <project.sqlite>
drag-lint ask risk --target project --db <project.sqlite>
```

`--cap N` bounds the routines drawn (default 20, the highest scores). Every routine is written to `risk.csv`
(rank, routine, file, line, cc, coverage, has_data, score) beside the diagram.

## The chart shows

A ranked column, riskiest first. `score = cc^2 * (1 - coverage)^3 + cc`, with coverage the covered fraction of the
routine's lines. At full coverage the score is the complexity itself; at none it is cc^2 + cc. A routine with no
coverage record scores as 0% covered and is counted as "without coverage data"; with no import at all every routine
is, and the meta says `CoverageImported = false`. Boxes click through to the routine's source.

## It stands on

`LoadMetrics` (cyclomatic, MET-1) and `<db>.coverage.json`.

## Read it carefully

* Coverage comes from your test run, not from the index: it is only as current as the report you imported.
* A routine the report does not name is shown as uncovered, which may be a naming mismatch; `import-coverage` lists
  the unmatched records so the mismatch is visible.
