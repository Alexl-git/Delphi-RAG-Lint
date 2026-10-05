# ask: wiring

**Who registers an interface, and where it is resolved.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

From RAD Studio: *drag-lint > Reports > Who registers and resolves this interface...* -- put the caret on the selection first (see [IDE Menu Reference](IDE-Menu-Reference#reports)).

```
drag-lint ask --question wiring --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). Today, ask it by name through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question wiring -Target MyApp.Services.IOrderService -DbPath <project.sqlite>
```

## You select

An interface.

## The chart shows

Spring4D registrations of the interface (implementation class, lifetime, registering routine) and every site that resolves it.

## It stands on

`di_bindings` -- the data behind the [`wiring`](Show-Wiring-Spring4D-DI-DFM-events) verb.

## Parameters

Row cap (default 20).

## Read it carefully

Selecting a CLASS refuses with a reason: the verb returns the same empty document for a class and for an interface nobody registers, so the chart checks the kind itself. A project that registers in a LOCAL `TContainer` may carry few bindings -- check `wiring --coverage` before trusting an empty answer.
