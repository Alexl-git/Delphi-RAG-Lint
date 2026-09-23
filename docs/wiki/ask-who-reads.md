# ask: who-reads

**Every routine that reads a field or property.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question who-reads --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question who-reads -Target MyApp.Orders.TOrder.Total -DbPath <project.sqlite>
```

## You select

A field or a property.

## The chart shows

The member and every routine that READS it, grouped by unit, with read-site counts. Both totals ride in the header.

## It stands on

`member_accesses` rows with mode `read`.

## Parameters

Row cap (default 20), disclosed as "+N more".

## Read it carefully

Same accessor attribution and `with` caveat as [`who-writes`](ask-who-writes). A widely read flag (a `Connected` property read in hundreds of routines) is exactly what the cap exists for.
