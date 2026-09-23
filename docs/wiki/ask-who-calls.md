# ask: who-calls

**The N-deep caller tree.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question who-calls --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question who-calls -Target MyApp.Orders.TOrderService.Post -DbPath <project.sqlite>
```

## You select

A method or routine.

## The chart shows

Every routine that calls the selection, then every routine that calls those, to the requested depth. A cycle is drawn once and marked, never walked forever.

## It stands on

`reverse-calltree` (resolved `call_edges`) unioned with the name-matched caller bucket at every hop, so a bare call the resolver typed to the wrong receiver is still found. Name-matched rows are marked as such.

## Parameters

Depth (default 2).

## Read it carefully

An EVENT HANDLER correctly has no code callers: its caller is the form file. Ask [`event-wiring`](ask-event-wiring) instead. Name-matched rows are hypotheses -- two routines can share a name.
