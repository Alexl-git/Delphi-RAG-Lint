> # FIXED 2026-08-16 (session 23), same day it was filed. Owner said "we need to fix this".
>
> `find-callers --resolved` now reports callback reaches, marked `[callback]`:
>
> ```
> query find-callers --name isValidZeissFileName --resolved
>     uMainZeissCopy.TfrmZeissCopy.FindFirstZeissFile  (uMainZeissCopy.pas:3303)  [callback]
> ```
>
> **`call_edges` was deliberately NOT widened**, which was the open question below.
> An edge there means a CALL, and `callgraph` / `impact` / `call-path` consume it
> as control flow; a bare-name pass has no call site and no arguments, so
> inventing an edge would make those verbs assert flow that does not exist at
> that line. The reach is reported by `find-callers` only, under a marker that
> cannot be read as a call. That is the third option this note recommended.
>
> Guarded by `tests\autotest\run_find_callers_callback_reach.ps1`. The control is
> `D_Orphan`, called by nobody and passed to nobody: it must STILL report
> `0 caller(s)` and exit 1. Without it, "the callback shows up now" would pass
> against a change that reported every routine as reached -- the failure
> direction that actually matters, since this query is what people use to decide
> something is dead. RED verified: exactly the three callback assertions fail on
> the pre-fix exe while both controls pass on either.
>
> Emitted only when the name denotes a ROUTINE (`skProcedure`/`skFunction`/
> `skMethod`/`skConstructor`/`skDestructor`), so a `read` of a same-named
> variable does not masquerade as a callback. It remains name-keyed, so a local
> sharing a routine's name can still produce a spurious row -- the marker is what
> keeps that honest.
>
> **The `TZEISSTransfer` half is also answered -- see the closing section.**

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

## Closing section -- "why was the predicate dropped?" It never was.

The owner asked whether `TZEISSTransfer.isValidZeissFileName` had been dropped
and what replaced it. Traced through DataCopy's Mercurial history:

* At **rev 7 (2025-03-31)**, **rev 14 (2026-02-19)** and **rev 17 (2026-08-03)**
  the occurrences in `uZeissRoutines.pas` are the SAME three every time: the
  class declaration, the definition, and one commented-out CodeSite line.
  **There has never been a call site in that unit.** Nothing was removed.
* The reason is visible in how the class actually enumerates. `TZEISSTransfer`
  filters **by MASK**, not by predicate -- `TDirectory.GetFiles(pFromPath, pMask)`
  at `uZeissRoutines.pas:1062` and `:1618`, plus `:584`, `:1370`, `:1670`. The
  two-argument overload. So the predicate was carried along when the logic moved
  out of the form into a service class, and the service class never needed it.

**The owner's recollection is right about the OTHER copy.** `TfrmZeissCopy`'s
version was used at three sites -- still visible in `BACKUP\uMainZeissCopy.pas.bck1`
and `.bck2` at lines 809, 822 and 1337 -- and those were consolidated into ONE
helper, `TfrmZeissCopy.FindFirstZeissFile` (`uMainZeissCopy.pas:3294`), which
holds the single surviving predicate call at `:3303` and is itself called at
`:3660`. So "it was used as a predicate in a couple of `TDirectory` calls" is an
accurate memory of a real refactor -- of the form's copy, not the transfer
class's.

**Conclusion:** the surviving `unused-parameter` finding on
`TZEISSTransfer.isValidZeissFileName` is a true positive, and the method is an
unwired copy rather than something that lost its caller. Wiring it would mean
switching that class's mask-based enumeration to the predicate overload; deleting
it loses nothing. Still a source decision.
