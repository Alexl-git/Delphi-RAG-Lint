# ask: lifecycle

**A form's create -> show -> destroy stages.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

From RAD Studio: *drag-lint > Reports > Form lifecycle (create -> show -> destroy)...* -- put the caret on the selection first (see [IDE Menu Reference](IDE-Menu-Reference#reports)).

```
drag-lint ask --question lifecycle --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). Today, ask it by name through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question lifecycle -Target MyApp.Main.TfrmMain -DbPath <project.sqlite>
```

## You select

A form or data-module class.

## The chart shows

The lifecycle sequence (OnCreate, OnShow, OnActivate, OnClose, OnCloseQuery, OnDestroy, ...) with each stage in one of THREE states: wired in the DFM, IMPLEMENTED BUT NOT WIRED (a `FormDestroy` method nothing calls), or absent.

## It stands on

`symbol_facts.dfm_event` plus the form class's own methods.

## Parameters

None.

## Read it carefully

The middle state is the point of the chart: a handler that exists but is not wired never runs, and nothing else in the toolchain says so.
