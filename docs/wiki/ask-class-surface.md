# ask: class-surface

**What a type exposes, by visibility.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

From RAD Studio: *drag-lint > Reports > What this type exposes (class surface)...* -- put the caret on the selection first (see [IDE Menu Reference](IDE-Menu-Reference#reports)).

```
drag-lint ask --question class-surface --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). Today, ask it by name through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question class-surface -Target MyApp.Orders.TOrder -DbPath <project.sqlite>
```

## You select

A class, record or interface.

## The chart shows

The type's members grouped into one cluster per visibility (published, public, protected, private), each row a field, property, method, constructor or destructor with its signature.

## It stands on

The type's child symbols in the index -- structured signatures, not the text slice [`surface`](Class-Surface) prints.

## Parameters

Rows per visibility cluster (default 12), disclosed as "+N more".

## Read it carefully

A form class's published component fields can dominate; the cap keeps the picture readable, and the hidden count is always shown.
