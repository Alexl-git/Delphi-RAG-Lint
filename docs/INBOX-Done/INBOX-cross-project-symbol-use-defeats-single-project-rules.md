> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21). ADDRESSED.** The note's concrete example is `unused-public-symbol` reporting `SaveOptionsToIni` as dead when it has 15 call sites in sibling YADF projects. That finding now reads *"is not referenced within this project. Its unit is shared with YADF, YADFOT, YADFSetup -- check there before treating it as dead"* and is a **hint**, not an info claim of dead API, with the sibling projects named from the unit's own `dl:shared` header. **The underlying constraint is unchanged and that is deliberate** -- the authoritative DB set is still one project plus the platform library (owner ruling 2026-08-13), so the tool still cannot PROVE the symbol unused. What changed is that it no longer asserts what it cannot know. If cross-project reference resolution is ever wanted as a feature, file it as one rather than as this defect.

# Project DB + library DB does NOT cover "is this symbol used anywhere"

Filed 2026-08-13. This is a caveat on the otherwise-correct default scheme
(project DB + platform library DB), found while triaging YADF toward zero.

## The measurement

`lint-all --project YADF.dproj` reports:

    YADF.Options.pas:338  [info] unused-public-symbol: procedure SaveOptionsToIni(...)

`SaveOptionsToIni` has **15 call sites** -- all of them in
`YADF.OptionsFrame.pas`, which `YADF.dproj` does not compile. That file belongs
to `YADFOT.dproj` and `YADFSetup.dproj`, which have their own indexes.

So the finding is FALSE, and no amount of correctness in YADF's own index or in
the platform library index would fix it. The information simply is not in either
one.

## Why the two-DB scheme is still right, and where it stops

The scheme is right for what it was chosen for:

* **project DB** -- this project's own symbols, its compile closure, its locals;
* **platform library DB** -- the RTL/VCL/third-party universe the compiler sees.

Together they answer every question of the form *"what does this code mean"*:
resolve a type, find a declaration, resolve a call, type-check an expression.
That is the overwhelming majority of what the engine does, and it is why
`used-unit-not-resolvable` was fixed by getting the library slot right.

They do NOT answer questions of the form *"is this used ANYWHERE we own"*, because
"anywhere we own" spans sibling projects that share source files. In this repo:

    YADF.Options.pas       compiled by YADF.dproj, YADFOT.dproj, YADFSetup.dproj
    YADF.OptionsFrame.pas  compiled by YADFOT.dproj and YADFSetup.dproj ONLY

A symbol declared in the first and used only in the second is invisible to
`YADF.dproj`'s index by construction.

## Which rules are affected

Any rule whose predicate is "no reference exists". Known so far:

* `unused-public-symbol`
* `find-deadcode` / dead-code reporting generally
* plausibly `unused-unit-in-uses` in the reverse direction

Rules that ask "what does this mean" are NOT affected and stay correct on two DBs.

## Options

1. **Scope-aware reporting.** When a project DB has sibling DBs declared in the
   same manifest that share source roots, consult them before reporting
   "unused". `resolve-dbs` already knows the full DB set; the reachability
   question just has to be asked across it.
2. **Declare a solution/group.** A manifest-level grouping ("these N projects are
   one product") that reachability rules union over. More explicit, and it also
   gives the LoopZero standard a definition of "everything we own".
3. **Demote the rule** to only report symbols that are private to one project, or
   to say "no use found in THIS project" rather than "unused".

Until one of these lands, **`unused-public-symbol` must not be `allow`ed** on any
project that shares source with a sibling -- marking it reviewed records something
false, permanently, with a hash on it.

## Also found in the same triage

`length-zero-compare` is type-blind. At `YADF.Layout.pas:2534`:

    if (Length(W) = 0) or (W[0] <> 'then') then

`W` is `TArray<string>` -- `ScanTop(const L: string; out AW: TArray<string>; ...)`
at `YADF.Layout.pas:2400`. `Length(X) = 0` is THE idiom for a dynamic array; the
rule's suggested `X = ''` does not compile for one. Same class as
`concat-in-loop`'s type-blindness (`INBOX-concat-in-loop-is-type-blind.md`) and
the same fix applies: a store-backed built-in that supersedes the syntactic rule
when an index is present, per the `string-equality-comparison` precedent.
