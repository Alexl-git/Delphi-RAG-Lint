# INBOX -- a routine passed as a CALLBACK is a ref but never a call edge, so `--resolved` calls it uncalled

**Found 2026-08-16 (session 23)** while the owner challenged a claim I had
repeated from a plan: that `TZEISSTransfer.isValidZeissFileName` is dead.

## The measurement

DataCopy has TWO methods named `isValidZeissFileName` -- one on the form, one on
`TZEISSTransfer`. The form's is used as a `TFilterPredicate`:

```pascal
{ uMainZeissCopy.pas:3303 }
FileNames := TDirectory.GetFiles(ADir, '*_*_chr.txt', isValidZeissFileName);
```

```
query find-callers --name isValidZeissFileName            -> 1 caller  (3303)
query find-callers --name isValidZeissFileName --resolved -> 0 callers
```

**Both answers are defensible in isolation and contradictory together.** The
name-keyed search finds the reference; the resolved search consults `call_edges`,
and passing a routine BY NAME is not a call, so no edge exists.

## Why this matters

`--resolved` is documented as the *precise* caller query -- "`--resolved` for
precise call-edge callers" in `docs\AI-USAGE.md`. A caller who trusts it
concludes a live predicate is uncalled. Any reachability analysis built on
`call_edges` inherits the same blind spot, and callbacks are exactly the code
you cannot find by reading call sites.

The row that DOES record it is `refs.kind='read'` on the bare routine name --
already verified present, and already the basis of the store-backed follow-up
listed under `rule-hardening-plan` item 4.

## What is NOT wrong

* `TZEISSTransfer.isValidZeissFileName` really is unused: its only occurrences
  in live source are the class declaration (`uZeissRoutines.pas:292`), the
  definition (`:696`), two `<seealso>` tags and one commented-out CodeSite line.
  **No use site.** The three extra call sites the owner remembered are real but
  live in `BACKUP\uMainZeissCopy.pas.bck1/bck2`, which are not compiled -- and
  they are the FORM's copy, not this one. So the surviving `unused-parameter`
  finding on it is a true positive.
* `unused-parameter` handles both correctly: the form's is suppressed (bare-name
  pass, session 23's addr-taken pass), and `TZEISSTransfer`'s still fires.

I had written "zero refs, zero grep hits" for that method. **"Zero grep hits" was
wrong** -- there are five textual hits, just no use site. Precision matters here
precisely because the owner was right to push back.

## The question for the engine

Should a bare-name callback pass produce a `call_edges` row? Arguments both ways:

* **For:** it is the only place the routine is *reached from*, so every
  reachability consumer wants it; without it `--resolved` under-reports.
* **Against:** it is not a call -- the edge has no call site semantics (no
  arguments, no invocation point), and inventing one would make `callgraph`,
  `impact` and `call-path` claim a control-flow edge that does not exist at that
  line.

A third option, and probably the right one: keep `call_edges` meaning *calls*,
but teach `--resolved` (and the reachability rules) to UNION in
`refs.kind='read'` rows that name a routine, reporting them with a distinct
marker such as `[callback]`. That preserves the precision of the call graph while
removing the false "uncalled" answer.

**Needs an owner ruling before implementing.** Cost is S either way; the risk is
entirely in which semantics `call_edges` is allowed to carry.

## Repro

```
drag-lint query find-callers --name isValidZeissFileName --db C:\Projects\DataCopy\_D-RAG\DataCopy.sqlite
drag-lint query find-callers --name isValidZeissFileName --resolved --db ...
```
