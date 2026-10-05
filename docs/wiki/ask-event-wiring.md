# ask: event-wiring

**Which handler runs on which event.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

**Planned engine verb -- `drag-lint ask` is not shipped yet.** Today ask this question with the chart pipeline command below, or with `Ask-Report.ps1` (see [Charts and the IDE](Charts-and-the-IDE)).

From RAD Studio: *drag-lint > Reports > Which handler runs on which event (form)...* -- put the caret on the selection first (see [IDE Menu Reference](IDE-Menu-Reference#reports)).

```
drag-lint ask --question event-wiring --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). Today, ask it by name through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question event-wiring -Target MyApp.Main.TfrmMain -DbPath <project.sqlite>
```

## You select

A form class (optionally one control).

## The chart shows

Control -> event -> handler rows for the form, from the DFM.

## It stands on

`symbol_facts.dfm_event`. Handlers are NEVER matched to controls by name: `Exit2.OnClick` wired to `WindowClose1Execute` is drawn as the DFM says.

## Parameters

Optional control name, used as a FILTER after the form has scoped the question (component names repeat across forms).

## Read it carefully

This is the answer [`who-calls`](ask-who-calls) cannot give for an event handler.
