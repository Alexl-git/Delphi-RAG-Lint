# ask: class-surface

**What a type exposes, by visibility.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question class-surface --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

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
