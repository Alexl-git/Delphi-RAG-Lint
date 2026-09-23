# ask: consumers

**Which code reads or writes this table or column -- and what does the database itself do with it?** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question consumers --target <TABLE | TABLE.COLUMN> --db <project.sqlite> --sql-db <sql-index.sqlite>
```

The same question through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question consumers -Target TABLE|TABLE.COLUMN -DbPath <Delphi project index> -SqlDbPath <SQL-script index>
```

## You select

A database table (`CUSTOMERS`) or a column (`CUSTOMERS.NAME`).

## The chart shows

* **Code side:** the routines that WRITE it and the routines that READ it.
* **Database side:** the triggers declared FOR the table (their bodies are scanned, including `NEW.` / `OLD.` column use), the stored procedures that name it (a `SET TERM`-aware body scan), and the indexes ON it.
* **Column form only:** the form bindings whose data-source chain resolves to that table.

## Read it carefully

* **The schema comes from SCRIPTS, not the live database.** It is built from the `MS*.SQL` migration scripts, collapsed by name with the newest script winning. A table created outside those scripts is absent (measured: 5 live `PDF_*` tables), and a column may survive only in an older script.
* **Writers are certain, readers are mostly inferred.** Writers come from the engine's `sql_writes` fact and are `[certain]`. Readers are mostly `[inferred]` from upper-case SQL-verb literals, because `sql_reads` misses SQL built with multi-line `SQL.Add` calls. Both counts are printed.
* **Positional reads are invisible.** `Fields[i]` access names no column, so it cannot appear.
* **On an index without SQL facts** (ORM3 CLIENT today), only `[by name]` literal matches appear.
* A live-database snapshot ([`fb-snapshot`](fb-snapshot)) makes the database side richer; it is optional.

## It stands on

The SQL-script index (tables, columns, triggers, procedures, indexes), the per-routine `sql_reads` / `sql_writes` facts that [`touches-tables`](ask-touches-tables) uses in the other direction, SQL-verb string literals, and DFM data bindings for the column form.
