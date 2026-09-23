# ask: shown-where

**Which forms and controls display a database column.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question shown-where --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question shown-where -Target CUSTNAME -DbPath <project.sqlite>
```

## You select

A database column (a DataField name).

## The chart shows

Every form and data-aware control whose DFM binding displays the column.

## It stands on

DFM data bindings (`DataField` / `DataBinding.FieldName` and kin), each resolved to its component symbol.

## Parameters

Row cap (default 20).

## Read it carefully

Not built on `symbol_facts.ui_affinity`: that fact is a THREAD-affinity hint on routines ("UI thread only"), not a column-to-control map.
