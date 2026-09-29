# ask: who-writes

**Every routine that assigns a field or property.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

```
drag-lint ask --question who-writes --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). Today, ask it by name through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question who-writes -Target MyApp.Orders.TOrder.Total -DbPath <project.sqlite>
```

## You select

A field or a property.

## The chart shows

The member in the middle and every routine that WRITES it, grouped by unit, with the number of write sites per routine. The header carries both totals (writes and reads) so a zero is never mistaken for "nothing touches this".

## It stands on

`member_accesses` rows with mode `write` -- the same bound accesses `query find-callers --resolved` lists for a property or field.

## Parameters

Row cap (default 20); hidden rows are counted in an explicit "+N more" row, never dropped silently.

## Read it carefully

For a property the access is attributed through its accessor (a field-backed property names its field, a method-backed one its getter/setter). Code inside a `with` block is not scope-modelled, so heavy `with` users can UNDERCOUNT.
