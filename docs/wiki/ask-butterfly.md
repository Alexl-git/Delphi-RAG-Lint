# ask: butterfly

**Who calls it AND what it calls, in one chart.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question butterfly --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question butterfly -Target DRagLint.Index.CallResolver.TCallResolver.ResolveEnumValueRead -DbPath <project.sqlite>
```

## You select

A method or routine.

## The chart shows

The selected routine in the middle, its CALLERS in one wing and its CALLEES in the other, each walked to the requested depth. Rows are routines; rows are grouped into one rounded box per UNIT, so a 30-routine neighbourhood reads as five or six boxes rather than thirty nodes.

## It stands on

Resolved `call_edges` (the same data as the [`butterfly`](butterfly) verb and `reverse-calltree`), plus the name-matched caller bucket so a caller the resolver could not bind is still shown.

## Parameters

Depth (default 2) -- how far each wing walks.

## Read it carefully

A callee edge exists only where the resolver bound the call. A routine whose body mostly calls through interfaces or untyped receivers shows a thin callee wing -- that is the index being honest, not the routine being simple. The [`butterfly`](butterfly) VERB prints the same graph as dot/mermaid/text; `ask --question butterfly` renders it.

## Sample -- drag-lint's own code

![butterfly on DRagLint.Index.CallResolver.TCallResolver.ResolveEnumValueRead](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/butterfly-ResolveEnumValueRead.png)

Question `butterfly`, target `DRagLint.Index.CallResolver.TCallResolver.ResolveEnumValueRead`, drag-lint's self-index. [Clickable SVG](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/butterfly-ResolveEnumValueRead.svg). The command that produced it is in the caption on [Diagrams and Charts](Diagrams-and-Charts).
