# INBOX index -- 13 open notes (was 23 that morning; 60 at the start of 2026-08-16)

> **Session 22 (2026-08-16, later).** Two notes CLOSED and moved to
> `INBOX-Done\` (88 retired): `exception-cref-transitive-raise` (one-hop callee
> resolution) and `parse-error-shellshock-units` (the indexer discarded
> `{$DEFINE}`s from `{$I}` includes -- a SILENT wrong-branch bug everywhere, not
> just the three units that happened to fail loudly). Four more notes advanced
> without closing; see their banners. Release gate unchanged: nothing to GitHub
> until Group A is finished.
>
> **Session 22, later the same day: Group A is DONE bar one owner decision.**
> Eight more notes closed (91 retired). Closed: `qualified-type-receiver`
> (did not reproduce -- both its diagnoses were stale; cross-unit coverage
> added), `whole-db-resolve-degrades-a-stale-index` (stale files are now
> excluded from the delete AND the stream), `autodoc-returns-section-incomplete`
> (did not reproduce), `autodoc-caller-list-fabricates-callers`
> (the ambiguity gate counted only call targets; 59 fabricated callers on ONE
> symbol), `cycles-scope-and-local-var-refs`, `docdrift-4-survive-a-converged-autodoc`.
> `loader2019-formcreate-inifile-leak` is a correct finding about an EXTERNAL
> project and is the only Group A item left -- it needs an owner decision, not
> engineering. Group C now has a written plan: `docs\PLAN-GROUP-C-2026-08-16.md`.

**Rewritten 2026-08-16 (session 21).** The previous index had drifted badly from
the notes it indexed -- it listed fixed items as open, carried per-priority
tables that no longer matched the files on disk, and counted feature requests
inside a defect backlog. Prose describing which notes *were* retired is in the
retired notes themselves, each of which now opens with a banner saying WHY.

* `docs\INBOX-Done\` -- **86 retired notes**, every one bannered with the
  measurement or commit that closed it.
* `docs\BACKLOG-editor-integration\` -- **6 notes**, one programme, four senders.
  Moved OUT of this index because they are features, not defects; see that
  folder's README. Not closed.
* `docs\TRIAGE-2026-08-16-inbox-sweep.md` -- the measurement record for the sweep
  that produced this state, including the traps that produced wrong verdicts.

## How this list is meant to be worked

**Re-measure before coding.** This is not advice, it is the single highest-yield
action available here: of everything settled on 2026-08-16, the majority closed
on measurement alone, and **three notes had the wrong stated mechanism** --
their fix was found only by measuring, not by reading the note:

* `used-before-assignment-array-local` blamed "array never counted as defined";
  it is defined. The cause was a substring test in `IsManagedType`.
* `object-leak` needed the same guard in TWO places; fixing the lattice alone
  changed nothing observable, because a separate replay records the site.
* `qualified-type-receiver` points at `TypeReceiver`, which already handles the
  case -- no call ref is emitted at all.

**Every guard needs a positive control, and must be run against the UNFIXED
build.** A test asserting only "the false finding is gone" passes with the rule
switched off.

## Open -- verifiable now

Group A is finished except for one item that is not an engineering decision.

| note | shape |
|---|---|
| `loader2019-formcreate-inifile-leak` | RE-MEASURED 2026-08-16: still fires against a fresh DB, unaffected by the object-leak fixes. **A correct finding about an EXTERNAL project** -- closing it means editing `C:\Projects\Loader2019`, which is the owner's call, not engine debt. |
| `used-before-assignment-real-shape-is-intra-item-ordering` | NOT re-measured in session 22 -- said plainly rather than implied. `and`/`or` sequencing is modelled; the general position-ordered case is not. **Read `rule-hardening-plan` item 3 first**: it blames a different cause (an `out` arg counted as a READ, 7 findings, cost S). Measure which one is live before coding. |
| `buildfor-defaulted-args-diverge-between-entry-points` | STALE for the function it names (the two caps are threaded now). `FixEditsForMissingDoc` fixed in session 22. Remaining: `ABaseDir` / `AIncludeSince` / `AExtraStores` / `AComplexityMin` still defaulted on the repair path -- `AExtraStores` is the risky one (cross-DB fan-out), so use a cross-DB fixture. |

## Open -- NOT verifiable in a normal session

These need a large corpus, an hours-long rebuild, or a live IDE. A Fable review
in session 22 found the group is **less blocked than its label suggests**: three
were already fixed in code, one had an INVERTED premise, and one does not belong
here at all.

**`lint-all-project-wide-phase-dominates-runtime` should move to Group A.** Its
dominant phase (doc-drift, 454.9s of 732s) reproduces on YADF in 40-second runs,
so it is profileable in a normal session; the full ORM3 confirmation is 12
minutes, which also fits. Leftover #3 (`idx_refs_name_nocase`) is already done.

`library-reindex-25x-slower-on-large-db` (FK indexes landed; **index-path size
guard added 2026-08-16**; progress/ETA line still missing; the 25x itself stays a
projection -- a small fixture cannot show a cost that is O(child-table rows)) ·
`incremental-index-hangs-on-large-db` (the "hang" is the whole-DB resolve;
scoped resolve fixes the body-edit shape but an ADDED type still falls back to
whole-DB. A synthetic 2M-symbol DB built by direct SQL insert would exercise it
in minutes -- positive control: assert the calls line reports millions of refs
streamed, else the pass streamed nothing and "fast" is vacuous) ·
`indexer-livelock-when-two-platforms-run-concurrently` (**the concurrency theory
was REFUTED**; nothing concurrency-shaped needs fixing. `DRAGLINT_NO_SCOPED_RESOLVE`
exists precisely to make the scoped/unscoped A/B a one-binary comparison, and no
autotest uses it yet -- ~1h to turn two landed fixes from "believed" into
"row-identical proven") · `index-all-win32-library-rebuild-aborts` (the
"crashed mid-DIAG-line" clue was a **128-byte stdout buffer artifact**; the
per-file flush now preserves evidence, so the next failure is diagnosable. Can be
launched unattended and harvested later) ·
`index-runs-are-not-resumable` (**CORRECTNESS HALF FIXED 2026-08-16** -- the
fingerprint was stamped BEFORE the walk, so a killed run silently kept stale
parses; now committed only on completion. Per-file resume still open) ·
~~`codelens-cache-has-no-eviction`~~ **RETIRED 2026-08-16 (session 23)** -- capped
at 32 with LRU eviction (`5f62f21`), 26-assertion console test, and BOTH
design-time BPLs rebuilt with the IDE closed (`a9b587a`). In-IDE behaviour
remains unverified; the binary is current.

`callback-pass-is-a-ref-but-not-a-call-edge` **(NEW 2026-08-16)** -- a routine
passed by bare name as a callback produces a `refs.kind='read'` row but NO
`call_edges` row, so `find-callers --name` reports 1 caller and
`find-callers --resolved` reports 0 for the same live predicate. `--resolved` is
documented as the *precise* query, so a caller trusting it concludes a live
callback is dead. **Needs an owner ruling** on whether `call_edges` may carry a
non-call edge, or whether `--resolved` should union in the ref rows under a
`[callback]` marker (probably the latter). Cost S.

## Open -- not defects, kept here deliberately

`rule-hardening-plan-2026-08-13` (a plan answering an owner question -- **item 4
`unused-parameter` CLOSED 2026-08-16 (session 23)**, and the note's own proposed
mechanism was wrong: not override/interface/DFM-wired-from-the-store, but
callback registration, caught same-file and SYNTACTICALLY because one real
registration sits in an inactive `$IFDEF` the store cannot see. DataCopy 5 -> 1,
own source 99 -> 75, the one true positive preserved) ·
`exception-class-unit-and-generated-exception-types` (feature request --
**MEASURED 2026-08-16: 64 distinct messages on ORM3, not the 400 that would have
killed it**, and normalization collapses 64 -> 63, so build Stage 1) ·
`converter-editor-phase-g-engine-findings` (workstream status: *"NOT pushed, NOT
merged, NOT deployed. Deliberate."* -- its one concrete engine ask, the
`#mapping`/`#apply` rejection, is **FIXED 2026-08-16**; findings **2.4-2.11 are
now ALL CLOSED (session 23)** -- 2.7 was disproved as stale by a new suite,
2.8's exit-code contract was documented AND corrected (usage is 2 and fatal is 3,
not the recorded "2 = usage" alone), the rest verified live. The note stays open
for exactly one thing: 2.5's `--framework vcl|fmx` tie-break, which is an OWNER
RULING, not engine debt -- **ANSWERED 2026-08-16: the tie is LIBRARY-ONLY (a
project DB returns 0 rows for `TEdit`), and the framework is derivable from the
project's own `uses` -- DataCopy 25 `Vcl.*` / 0 `FMX.*`. So the fix is to derive
context, not to add a `--framework` flag and rule on a default**)
· `ide-lsp-ram-and-shim-todo` (items 3-4 still blocked on the IDE being
startable; §1.1's ask **folded into the union design 2026-08-16**, correcting a
wrong premise there) · `yadf-share-review-marker-hash` (owner request for a
shared hashing helper -- **RE-COUNTED 2026-08-16: 249 markers across three
repos**, so the "changing the normaliser is nearly free" window has closed).
