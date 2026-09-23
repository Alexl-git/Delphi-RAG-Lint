# ask: crosses-boundary

**Does this routine's work leave the process.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question crosses-boundary --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question crosses-boundary -Target MyClient.Orders.TOrderClient.SendOrder -DbPath <project.sqlite>
```

## You select

A method or routine.

## The chart shows

A verdict -- CROSSES (with the protocol commands and transport calls that carry it), IS THE BOUNDARY (the routine is the transport), or NO EVIDENCE -- plus the evidence rows. Given the other tier's index as a counterpart, the far side of each command is named.

## It stands on

Enum-value binding for the commands a routine speaks, plus call edges to the transport.

## Parameters

Optional counterpart index (the other half of a client/server system). Without it the chart shows one side and says so.

## Read it carefully

The verdict is a judgement made FROM the evidence, so the evidence count is always in the header beside it.
