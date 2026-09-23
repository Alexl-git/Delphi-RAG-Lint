# ask: architecture

**The whole project as layered zones.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question architecture --at <Project.dpr>:1:1 --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question architecture -Target project -DbPath <project.sqlite>
```

## You select

The project.

## The chart shows

Every project unit grouped into a zone per SOURCE DIRECTORY, the cross-zone `uses` edges, BACK-EDGES (a lower layer using a higher one) in red, and external units grouped by family (RTL, VCL, FireDAC, DevExpress, Spring4D, ...).

## It stands on

`unit_uses` for the internal structure plus [`deps-report`](deps-report) for the external families.

## Parameters

Rows per zone (default 6); externals can be left out.

## Read it carefully

Zones are directories because most Delphi projects have no namespace layering to read. On a large project the full picture is dense by nature -- for a readable view of one layer, ask [`deps`](ask-deps) on a unit in it (see the sample there).
