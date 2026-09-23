# ask: effects

**What a routine does to state outside its locals.** One of the diagram questions of the `ask` verb -- see [Diagrams and Charts](Diagrams-and-Charts) for the model, the bundle and click-to-source.

## Asking it

```
drag-lint ask --question effects --at <file.pas>:<line>:<col> --db <project.sqlite>
```

The selection is the symbol under `--at` (resolved exactly as [Type at Cursor](Type-at-Cursor) resolves a caret). The same question by name, through the chart pipeline:

```
New-DiagramArtifact.ps1 -Question effects -Target MyApp.Pricing.CalcDiscount -DbPath <project.sqlite>
```

## You select

A method or routine.

## The chart shows

The purity verdict and the effect summary, token by token: `g` writes global state, `h` allocates or frees on the heap, `s` writes its own fields, `p<k>` writes through parameter k (named from the signature), `?` a blocker the analysis could not see through. A routine with no tokens and a proven verdict is shown as **Effect-free (proven)** -- the same words hover and autodoc use.

## It stands on

`symbol_facts.effect_summary`, `effect_free`, `mutates_params` and `returns_owner`, written by the purity resolve stage (whole-DB fixpoint).

## Parameters

None.

## Read it carefully

An empty summary with a proven verdict is PURE; an empty summary with no verdict is NOT ANALYSED. The chart keeps the two apart -- reading absence as ignorance would call thousands of provably pure routines unknown. `?` is an admission, so it is always counted in the header beside the effects.
