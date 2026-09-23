# ask: deps

**The dependency neighbourhood of one unit.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question deps --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question deps -Target DRagLint.Lint.Linter -DbPath <project.sqlite>
```

## You select

A unit.

## The chart shows

The unit in the middle, the units that USE it on one side and the units it uses on the other, each grouped into a box per SOURCE DIRECTORY. An interface-section `uses` edge is solid; an implementation-section edge is dashed -- the distinction [`uses-audit`](Uses-Audit-interface-impl-moves-unused-this-unit) acts on.

## It stands on

`unit_uses` joined on the resolved target file (never on the bare unit name, which collides across namespaces).

## Parameters

None.

## Read it carefully

One hop only. For the whole project's layering ask [`architecture`](ask-architecture); for cycles ask [`cycles`](ask-cycles).

## Sample -- drag-lint's own code

![deps on DRagLint.Lint.Linter](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/deps-Lint-Linter.png)

Question `deps`, target `DRagLint.Lint.Linter`, drag-lint's self-index. [Clickable SVG](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/deps-Lint-Linter.svg). The command that produced it is in the caption on [Diagrams and Charts](Diagrams-and-Charts).
