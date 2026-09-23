# ask: touches-tables

**Which database tables a routine reads and writes.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question touches-tables --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question touches-tables -Target MyServer.Orders.TOrderDM.SaveOrder -DbPath <project.sqlite>
```

## You select

A method or routine.

## The chart shows

The routine and the physical tables it READS, WRITES, or both.

## It stands on

`symbol_facts.sql_reads` / `sql_writes`, derived from the SQL a routine issues through FireDAC.

## Parameters

None.

## Read it carefully

A tier that owns no database connection (a thin client that asks a server over a pipe) has no SQL facts at all. Asked on such an index, the question REFUSES with that reason instead of drawing "0 tables", which would read as "does no database work". Ask the server-tier index.
