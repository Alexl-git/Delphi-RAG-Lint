# ask: cycles

**Circular unit dependencies.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question cycles --at <Project.dpr>:1:1 --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question cycles -Target project -DbPath <project.sqlite>
```

## You select

A unit, or the whole project.

## The chart shows

Each group of units that depend on each other circularly, with EVERY measured `uses` edge inside the group drawn, and how heavy each edge is.

## It stands on

The [`cycles`](Circular-Uses-Report-cycles-fix-plan) verb (`cycles --edges --causes`).

## Parameters

Selection `project` (every cycle) or a unit (the cycles through it). The refactoring playbook (`cycles --plan`) is optional and off by default -- it costs roughly 50x the plain query.

## Read it carefully

A "cycle" is a strongly-connected COMPONENT, not a ring: two loops sharing a unit have no single traversal order. The chart therefore assumes none and draws the edges that exist -- never an edge implied by list order.
