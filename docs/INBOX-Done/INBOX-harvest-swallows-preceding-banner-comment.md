> **RETIRED to INBOX-Done/ on 2026-08-15.** FIXED: guarded by tests/autodoc/run_doc_p3_harvest_boundary.ps1, green in the full battery.
>
> Original note follows unchanged.

# INBOX: the harvester swallows a preceding banner comment and makes it the `<summary>`

**Filed:** 2026-08-03, from the Phase 3 T17 rollout run against the real YADF corpus.
**Class:** autodoc quality defect (harvest boundary scan / acceptance guards).
**Status:** open. NOT fixed. Found on real code, not on a fixture.

## What happens

When a declaration is preceded by a real prose comment, and ABOVE that sits a
separate **banner / section-divider** comment with exactly one blank line between
them, the boundary scan swallows both as ONE comment block. "First paragraph
becomes the `<summary>`" then makes the **banner** the summary, and the real
prose is demoted to `<remarks>`.

## Reproducing it -- `C:\Projects\YADF\YADFOT.Wizard.pas`

Source (implementation side):

```pascal
// --- Register ----------------------------------------------------------

// Register is the entry point the IDE invokes when the design-time
// package loads. It hands the IDE one IOTAWizard (the Tools-menu item)
// ... (nine more lines of genuine prose) ...
procedure Register;
```

Emitted:

```pascal
/// <summary><!-- drag-lint:auto -->--- Register ----------------------------------------------------------</summary>
/// <remarks>
/// <!-- drag-lint:auto -->Register is the entry point the IDE invokes when the design-time package loads. ...
```

The `<summary>` -- the one line that shows in a Help Insight tooltip and in
every hover -- is a row of dashes.

## Why the existing guards miss it

Task 6's acceptance guards reject a comment block that IS a divider/banner rule.
This block is not: it is a banner, a blank line, and then eleven lines of real
prose. `HarvestStartLine` walks up from the declaration and `FindDocRegionAbove`
tolerates **one blank line** (`AllowGap = 1`), so the scan crosses the gap and
keeps going up into the banner. From there the paragraph split does exactly what
it is specified to do -- the banner is the first paragraph, so the banner becomes
the summary.

So neither piece is individually wrong; the interaction is.

## Second instance, same run

`YADF.OptionsFrame.pas:253` produced
`<summary><!-- drag-lint:auto -->event handlers</summary>` -- a bare section
label. **Those were the only two summaries harvested in the entire run, and both
are junk.** The feature's precision on this corpus is currently 0 of 2.

## Suggested fix, and the constraint on it

Reject a leading paragraph that is a divider/banner when there are further
paragraphs, and promote the NEXT paragraph to `<summary>` instead -- rather than
rejecting the whole block, which would lose eleven lines of good prose.

A banner is cheap to recognise deterministically: after stripping comment
markers, the line is (a) made only of a punctuation run (`-`, `=`, `*`, `_`) or
(b) a short label wrapped in such a run (`--- Register ---...`). Keep it exact
and conservative -- the point of the harvest is that it never invents prose.

**Any fix needs a fixture for the two-blocks-one-blank-line shape**, because that
gap is the actual trigger and no current fixture has it.

## Related

The same run showed the harvest is additionally suppressed wherever a symbol
already carries an unmarked blank `<summary></summary>` from a pre-marker
autodoc run (39 of them in YADF) -- those correctly take the hand-written path
and the harvest never lands. That is not this defect, but it is why the harvest
yield on this corpus was 2 rather than the expected large share of the 120
implementation-side comments.
