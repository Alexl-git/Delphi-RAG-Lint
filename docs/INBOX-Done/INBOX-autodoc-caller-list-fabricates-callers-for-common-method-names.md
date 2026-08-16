> # CLOSED 2026-08-16 (session 22) -- FIXED. The gate measured the wrong population.
>
> The banner's warning was right: only `Create` had been re-measured. Re-measured
> other names and it REPRODUCED on `TreeSitter.TTSNodeHelper.Child` --
> `find-callers --name Child --resolved` returns **0 callers**, while the
> generated `Called from:` list carried **59 entries** ("+54 more").
>
> **Root cause: `LeafNameIsUnambiguous` counted only CALL TARGETS.** It answered
> *"is there exactly one routine with this name"*, when what the bucket needs is
> *"could an unresolved ref carrying this name be something other than a call to
> me"*. `Child` is declared once as a method -- so the gate said unambiguous --
> while **23 distinct local variables named `Child`** exist in the same index.
> Those variable uses emit same-named refs, and the bucket claimed them all.
>
> This is the SIBLING of the `Create` case, not the same shape: `Create` was many
> constructors sharing a name; this is ONE method colliding with MANY variable
> bindings. Fixing the first could never have fixed the second.
>
> Fix: the gate now also fails on a collision with `skLocalVar` / `skParam` /
> `skField` -- the binders that put a bare identifier where the extractor sees a
> call shape. Types and constants are deliberately NOT counted (they collide
> rarely and gating on them would delete legitimate buckets). The resolved-anchor
> escape is untouched: when even one caller resolves, the bucket is still added
> and the ' ?' marker marks the weak entries.
>
> `DRagLint.Doc.Facts.pas`; test
> `testsutodocun_doc_leafname_localvar_collision.ps1`.
>
> **A vacuous-assertion trap was caught while verifying this, and it is worth
> knowing.** `document --qname X --json` emits only a per-symbol SUMMARY
> (qname/file/line/action/edits) and NEVER the block text -- so
> "output does not contain 'Called from'" passes against it no matter what the
> engine generated. The first verification of this fix, and the first version of
> the test, were both vacuous for that reason. The suite now reads the rendered
> (non-JSON) edit and additionally asserts an edit was produced at all.

# INBOX -- the "Called from:" list FABRICATES callers for common method names, and the uncertainty marker hides it

Found 2026-08-10 while applying the full autodoc pass to drag-lint's own source.
**Severity: high -- it writes a false claim into source, at corpus scale, and it reads
as verified.** The autodoc apply was REVERTED because of this; it is the one thing
blocking the pass.

> ## RE-MEASURED 2026-08-13: fix 1 appears LANDED. Fix 2 is now the whole of it.
>
> Same command, same symbol, current engine:
>
>     > drag-lint document --unit src\lint\DRagLint.Lint.QueryRules.pas ^
>         --db C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite
>     /// Called from: DRagLint.Lint.QueryRules.TQueryRuleLoader.LoadAll (DRagLint.Lint.QueryRules.pas),
>     ///   DRagLint.LSP.Completion.TLspCompletion.BuildCodeActions (DRagLint.LSP.Completion.pas) ?
>
> **107 fabricated entries -> 1.** `TQueryRuleLoader.LoadAll` is the correct sole
> construction site named in this note. One spurious entry remains
> (`BuildCodeActions`) and it CARRIES the ` ?` marker, so it is legible.
>
> Credit is not this session's: `run_doc_no_fabricated_callers.ps1` now pins both
> halves (constructor-receiver resolution + the name-bucket fallback), and today's
> `8abcc3e` stopped `document` fanning out across every DB on the machine.
>
> **What this changes about fix 2.** The argument for marking uniformly-uncertain
> lists was that a 107-entry, 100%-fabricated list rendered with no marker at all.
> That specific danger is gone. Fix 2 is still correct in principle -- absence of a
> marker should mean "verified" -- but it is no longer urgent, and its cost is now
> the dominant consideration:
>
> `run_doc_p3_callerline.ps1` measures **65 of 99** reference lines (YADF) and
> **832 of 1126** (drag-lint) as uniformly uncertain, i.e. 70.7% / 85.4% of
> entries would gain a ` ?`. It also pins the mixed-only rule deliberately, with
> mutation cases M2/M3 covering both directions.
>
> So fix 2 is a corpus-wide visible rewrite that reverses a tested decision.
> **Still needs the owner ruling this note asked for -- do not flip it silently.**
> Re-verify fix 1 on a common name other than `Create` (`Execute`, `Add`, `Free`)
> before declaring it closed; only `Create` was re-measured.

## What the engine wrote

`document --unit src/lint/DRagLint.Lint.QueryRules.pas --apply` produced this on
`TQueryRule.Create`:

```
/// Called from: DRagLint.CLI.PrintReferences (DRagLint.CLI.pas),
///   DRagLint.CLI.PrintReferencesWithContext (DRagLint.CLI.pas),
///   DRagLint.CLI.OpenReadOnlyStore (DRagLint.CLI.pas),
///   DRagLint.CLI.OpenWritableStore (DRagLint.CLI.pas),
///   DRagLint.CLI.PlanToJson (DRagLint.CLI.pas) (+102 more)
```

`TQueryRule.Create` is constructed in exactly ONE place: `TQueryRuleLoader.LoadAll`.
None of the five named routines constructs one.

## The measurement

```
symbol DRagLint.Lint.QueryRules.TQueryRule.Create  -> id 14125
resolved call_edges INTO it                        -> 0
refs of kind 'call' with name_text = 'Create'      -> 537
```

So the symbol has **zero** resolved callers, and the list is built entirely from the
NAME BUCKET: every unresolved `Create(` call site in the corpus is attributed to this
one constructor. 107 of them were rendered.

This is not specific to `Create`. Any method whose leaf name is common and whose call
sites do not resolve -- `Execute`, `Run`, `Add`, `Free`, `Clear` -- gets the same
treatment, so the defect scales with how ordinary the name is.

## Why it reads as verified -- and this ANSWERS the long-open ' ?' question

The ' ?' uncertainty marker is emitted **only on MIXED lists**: a list whose entries
are all uncertain renders plain, exactly like a list whose entries are all resolved.
That was a deliberate, re-measured T4 decision, and the plan has carried an open
question about it ever since:

> The ' ?' marker renders only on MIXED lists, so an all-guessed caller list is
> indistinguishable from an all-resolved one. One line in `JoinRefs`. **Needs a
> ruling.**

This is the ruling's evidence. A 107-entry, 100%-fabricated caller list currently
renders with no marker of any kind. The argument for suppressing on uniformity was
that "a marker present on every entry distinguishes nothing" -- true WITHIN one list,
but the reader is not comparing entries, they are deciding whether to trust the line.
Uniformly-guessed is precisely the case where the reader most needs telling.

## Two fixes, and they are complementary

1. **Do not name-bucket callers into a symbol that has ZERO resolved edges when the
   name is ambiguous corpus-wide.** A name shared by 537 call sites carries no
   information about this symbol. The existing machinery already knows the resolved
   count; the bucket should be gated on it, or capped by "how many symbols share this
   leaf name" (`Create` is shared by nearly every class in the codebase).

2. **Emit the ' ?' marker on a uniformly-uncertain list**, so absence of the marker
   means "verified" rather than "either verified or entirely guessed". One line in
   `JoinRefs` (`src\doc\DRagLint.Doc.Regions.pas`).

Fix 1 removes the false content. Fix 2 makes the remaining uncertainty legible. Doing
only 2 leaves 107 marked-but-wrong entries; doing only 1 leaves smaller guessed lists
still reading as verified.

## Why this blocked the autodoc pass

The pass was measured and ready: **1,322 doc edits across 92 files**, and the rest of
the output was good -- qualified cross-unit callees (the new unit-level rung),
intrinsics filtered out, `<exception cref>` from mined raises, `Recursive`,
`Owns returned`, complexity, reads/writes, and `<seealso>` leading with real callees.

But `document --apply` REWRITES SOURCE, and this defect would have written ~100 false
"Called from" entries onto every common-named constructor and method in the codebase,
with nothing to tell a reader they were guesses. Under the project's own stated policy
-- absence over a wrong claim -- that is not shippable. Reverted with `git checkout --
src/`; nothing from the pass remains.

Re-run the pass once fix 1 lands. The measurement above is the before-picture.
