# sql

Runs **one read-only SQL statement** against an index database and prints the
result set. Reach for it when the question you have is real but no verb answers
it -- a join across `symbols`, `refs` and `files`, a distribution, a spot check
on something the extractor wrote.

It exists so that "there is no verb for that" stops being the end of the
conversation. Every canned verb costs its own flags, its own `--help` line and
its own documentation, paid per question; this one pays that cost once.

## Running it from the CLI

```
drag-lint sql --query "SELECT ..." --db <file.sqlite> [--format text|json] [--json] [--limit N] [--timeout-ms N] [--output <file>]
drag-lint sql --file <q.sql>       --db <file.sqlite> [--format text|json] [--json] [--limit N] [--timeout-ms N] [--output <file>]
```

Pass **either** `--query` or `--file`, not both.

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. A project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` (or `--in <X.pas>`) if unsure.
`sql` never creates a database: pointing it at a path that does not exist is an
error, not an empty index.

## It is read-only, and that is enforced by SQLite rather than by reading your query

Three independent layers, none of which is a pattern match over the SQL text:

1. the connection is opened with `PRAGMA query_only = ON`;
2. an **sqlite3 authorizer** permits only `SELECT`, table/column reads,
   `WITH RECURSIVE`, transaction control and safe scalar functions. Everything
   else is denied -- `ATTACH`, `DETACH`, `PRAGMA`, every `CREATE`/`DROP`/
   `ALTER`, every `INSERT`/`UPDATE`/`DELETE`, and filesystem-touching functions
   such as `load_extension`. The authorizer is the layer that blocks `ATTACH`;
   `query_only` does not;
3. a **progress handler** enforces a wall-clock cap, so a runaway join is
   interrupted mid-execution instead of pinning the machine.

Two more limits sit on top:

* **exactly one statement.** `SELECT 1; DROP TABLE symbols` is rejected before
  it reaches SQLite. A semicolon inside a string literal or a comment does not
  count.
* **a row cap**, 200 by default (`--limit N`). When it truncates, it SAYS so --
  a cap that stayed quiet would read as the complete answer.

A denied statement names the action that was refused, e.g.
`ERROR: refused -- ATTACH is not permitted (other.sqlite)`. DDL reports as a
write to `sqlite_master`, because that is the action SQLite authorizes first.

## Flags

| Flag | Meaning |
|---|---|
| `--query "<sql>"` | the statement to run |
| `--file <q.sql>` | read the statement from a file instead |
| `--db <file.sqlite>` | the index to query (required) |
| `--limit N` | row cap; default 200 |
| `--timeout-ms N` | wall-clock cap; default 10000. There is no "unlimited" -- pass a bigger number |
| `--format json` / `--json` | emit the stable `sql/1` JSON document |
| `--output <file>` | write to a file instead of stdout |

Exit codes: `0` success; `2` usage error (no query, both sources, more than one
statement, missing or absent `--db`); `1` the query was refused, hit the time
cap, or failed in SQLite.

## Know the columns before you write the query

Table names are discoverable; **semantics are not**. Ask first:

```
drag-lint schema --db <file.sqlite> --format json
```

That carries every column plus, where the vocabulary is closed, the enumerated
values -- `refs.kind` is exactly {`read`, `call`, `member-access`, `write`,
`type_use`}, and `symbols.section` has three values, one of which is the empty
string. A query that assumes a value which does not exist returns nothing and
reads like an answer. When a query does fail, the error names this command.

## Example

Illustrative only:

```
drag-lint sql --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --limit 5 --query ^
  "SELECT f.path, COUNT(*) AS n FROM refs r JOIN files f ON f.id = r.file_id WHERE r.kind = 'call' GROUP BY f.path ORDER BY n DESC"
```

This would list the five files making the most resolved calls:

```
path                                   n
-------------------------------------  ----
C:\Projects\MyApp\src\MyApp.Main.pas   2282
...
5 row(s) in 12 ms
-- ROW CAP REACHED at 5 rows; there are more. Pass --limit N.
```

The JSON form emits `"schema": "sql/1"` with `columns`, `rows`, `row_count`,
`truncated`, `row_cap`, `timeout_ms` and `elapsed_ms`. Rows are **arrays**
positionally matching `columns`, not objects -- a query may legitimately return
two columns with the same name, and an object would silently lose one.
