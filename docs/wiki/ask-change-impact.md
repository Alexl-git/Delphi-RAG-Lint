# ask: change-impact

**The blast radius of a change.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question change-impact --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question change-impact -Target DRagLint.Preprocess.Profile.ProfileFromDproj -DbPath <project.sqlite>
```

## You select

A method, routine or type.

## The chart shows

Everything that could break if the selection changes: its callers, their callers, and so on to the requested depth, grouped into SOURCE-DIRECTORY zones, each row tagged with the hop at which it was reached. For a TYPE the walk starts from every member.

## It stands on

The [`impact`](Impact-Blast-Radius-symbol) walk over CALLERS -- edges INTO a symbol are owned by the calling file, which is why this direction is reliable.

## Parameters

Depth (default 3); frontier cap 400 (reported when hit); rows per zone (default 8, "+N more" beyond).

## Read it carefully

An unresolved caller is invisible here, so a small radius is a FLOOR, not a ceiling. Pair it with [`who-calls`](ask-who-calls), which adds the name-matched bucket.

## Sample -- drag-lint's own code

![change-impact on DRagLint.Preprocess.Profile.ProfileFromDproj](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/change-impact-ProfileFromDproj.png)

Question `change-impact`, target `DRagLint.Preprocess.Profile.ProfileFromDproj`, drag-lint's self-index. [Clickable SVG](https://raw.githubusercontent.com/Alexl-git/Delphi-RAG-Lint/main/docs/Images/charts/change-impact-ProfileFromDproj.svg). The command that produced it is in the caption on [Diagrams and Charts](Diagrams-and-Charts).
