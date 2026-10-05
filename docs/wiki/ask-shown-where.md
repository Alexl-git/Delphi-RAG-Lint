# ask: shown-where

**Which forms and controls display a database column.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

From RAD Studio: *drag-lint > Reports > Where this database column is shown...* -- type the name in the prompt (see [IDE Menu Reference](IDE-Menu-Reference#reports)).

```
drag-lint ask --question shown-where --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). Today, ask it by name through the chart pipeline:

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
