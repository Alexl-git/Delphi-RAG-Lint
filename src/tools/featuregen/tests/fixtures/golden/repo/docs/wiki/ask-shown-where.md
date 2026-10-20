# ask: shown-where

**Which forms and controls display a database column.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

Answered in-process by the engine (`drag-lint ask`); no PowerShell is needed (see [Charts and the IDE](Charts-and-the-IDE)).

From RAD Studio: *drag-lint > Reports > Where this database column is shown...* -- type the name in the prompt (see [IDE Menu Reference](IDE-Menu-Reference#reports)).

```
drag-lint ask --question shown-where --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). From a terminal, ask it by name:

```
drag-lint ask shown-where --target CUSTNAME --db <project.sqlite>
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
