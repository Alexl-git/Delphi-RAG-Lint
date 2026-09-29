# ask: protocol-trace

**Where a protocol command or wire field travels.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask --question protocol-trace --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). Today, ask it by name through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question protocol-trace -Target MyApp.Protocol.cmdDelta -DbPath <project.sqlite>
```

## You select

A command constant or wire field (enum value), or a method.

## The chart shows

For an enum-valued COMMAND: every bound read of it, grouped by zone -- who sends it, who dispatches on it. For a METHOD: which protocol commands it speaks.

## It stands on

Enum-value reference binding (`refs.symbol_id` on an enum value; resolver 1.6.0-alpha), the same data `query find-callers --name <value> --resolved` lists as `[certain, read]`.

## Parameters

Row cap (default 20).

## Read it carefully

Needs an index resolved at resolver 1.6.0-alpha or later (`index --all --resolve-only`); an older index has no enum bindings and the trace is empty. A BARE enum read inside a routine containing a `with` block, or in a `{$SCOPEDENUMS ON}` unit, can bind wrongly -- verify those against the declaration.
