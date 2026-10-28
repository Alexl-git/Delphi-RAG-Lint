# query --text --near

Restrict a text search to the code around one symbol. `query --text` finds every
message, caption or comment containing a phrase; `--near <QName>` keeps only the
hits that sit inside routines within N **call-graph hops** of a seed symbol.

## The question it was built for

> This error message is raised in forty places. Which of them are near the routine I am changing?

```
drag-lint query --text "invalid value" --near Foo.Unit1.TSaver.Save --hops 2 --db <file.sqlite>
```

## Running it from the CLI

```
drag-lint query --text "<phrase>" --near <QName> [--hops 1..3] [--hops-uses] [--near-boost] [--db ...] [--json]
```

| flag | meaning |
|---|---|
| `--near <QName>` | the seed symbol; a qualified name (`Unit.Routine`, `Unit.Type.Method`). An unknown seed, or a bare name that answers to several different qualified names, exits 2 |
| `--hops N` | 1 to 3, default 2. `--hops 4` exits 2 with "3 hops max; use impact --depth for wider" |
| `--hops-uses` | unit-uses edges join the neighbourhood: every routine of a unit that uses, or is used by, a unit within N hops of the seed's unit counts at that hop. The seed's own unit is NOT pulled in |
| `--near-boost` | do not filter: keep every hit, neighbourhood rows first (nearest hop first), the rest after |

A hop is one resolved call edge, followed in **both** directions (callers and
callees). A hit counts for the routine that contains it; each printed row carries
`hop=N` (`--json`: `"hop"`, `null` for a boosted row outside the neighbourhood).

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required (`drag-lint resolve-dbs --project <X.dproj>`), and the call
edges must be resolved: a symbol whose calls were never resolved has no
neighbours. The seed must be indexed in one of the scanned databases.

## Pitfalls

* The default restricts. A hit in a routine outside the neighbourhood is dropped,
  not demoted; use `--near-boost` to keep it.
* The neighbourhood is keyed by qualified name, so overloads of one routine share
  the smallest hop of any overload.
* `--limit` applies after the filter; the unfiltered fetch is capped at 100000 rows.
* Hits outside any routine body (DFM text, unit-level constants) have no owning
  routine and are excluded unless `--near-boost` is given.
* Measured on a 181 MB index (30,374 call edges), the neighbourhood query takes
  2 / 11 / 29 ms for 1 / 2 / 3 call hops, and 34 / 201 / 126 ms with `--hops-uses`.
