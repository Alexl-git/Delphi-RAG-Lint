# ask: tested-by

**Which tests reach this code.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question tested-by --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question tested-by -Target MyApp.Orders.TOrderService.Post -DbPath <project.sqlite>
```

## You select

Any symbol.

## The chart shows

The DUnitX `[Test]` methods (and their fixtures) whose call trees reach the selection.

## It stands on

COMPUTED at render time, not stored: a bounded caller walk that unions resolved callers and name-matched callers at every hop, stopping at routines carrying a `[Test]` attribute. `symbol_facts.covered_by` is reserved and never written, on purpose -- a reverse edge written at index time would depend on file order.

## Parameters

Row cap (default 20).

## Read it carefully

Ask it against the TEST project's index. A production project's compile closure cannot contain its tests; a test project's closure contains both the tests and the code under test, so the walk runs inside one database.
