# ask: hierarchy

**Ancestors above, descendants below.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question hierarchy --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question hierarchy -Target MyApp.Base.TBaseForm -DbPath <project.sqlite>
```

## You select

A class or interface.

## The chart shows

What the type inherits from (above) and what inherits from it (below). Arrows mean INHERITS FROM and all point upward. It is a DAG, not a tree: a class has one parent but any number of interfaces, so a type is drawn once and edges may converge on it.

## It stands on

Ancestor edges (`query ancestors` / [`query descendants`](query-descendants)); an RTL/VCL ancestor is shown when the platform library index resolves it.

## Parameters

Row cap (default 20).

## Read it carefully

Descendants come only from indexes you passed. A base class used across several projects shows the descendants of THIS project's closure.
