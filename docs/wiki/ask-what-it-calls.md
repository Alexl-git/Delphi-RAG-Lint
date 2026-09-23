# ask: what-it-calls

**The N-deep callee tree.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question what-it-calls --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question what-it-calls -Target MyApp.Orders.TOrderService.Post -DbPath <project.sqlite>
```

## You select

A method or routine.

## The chart shows

Everything the selection calls, then everything those call, to the requested depth, grouped by unit. Cycles are marked.

## It stands on

`reverse-calltree --direction callees` over resolved `call_edges`.

## Parameters

Depth (default 2).

## Read it carefully

There is no name-matched bucket in this direction -- nothing can ask "which symbols share a name with something this routine calls". An unresolved call is therefore absent, not approximated. See [`ambiguous-calls`](ambiguous-calls) for what the resolver declined.
