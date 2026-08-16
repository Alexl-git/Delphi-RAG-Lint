# INBOX index -- 21 open notes (was 23; 60 at the start of 2026-08-16)

> **Session 22 (2026-08-16, later).** Two notes CLOSED and moved to
> `INBOX-Done\` (88 retired): `exception-cref-transitive-raise` (one-hop callee
> resolution) and `parse-error-shellshock-units` (the indexer discarded
> `{$DEFINE}`s from `{$I}` includes -- a SILENT wrong-branch bug everywhere, not
> just the three units that happened to fail loudly). Four more notes advanced
> without closing; see their banners. Release gate unchanged: nothing to GitHub
> until Group A is finished.

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

| note | shape |
|---|---|
| `qualified-type-receiver-does-not-resolve` | RE-DIAGNOSED: the gap is in call-ref EXTRACTION, not receiver typing. Start at the extractor. |
| `used-before-assignment-real-shape-is-intra-item-ordering` | Partly addressed (`and`/`or` sequencing modelled); the general position-ordered case is not. |
| `whole-db-resolve-degrades-a-stale-index` | Needs a deliberately staled index; small setup, not yet done. |
| `autodoc-caller-list-fabricates-callers-for-common-method-names` | Its own banner warns only `Create` was re-measured. |
| `autodoc-returns-section-incomplete` | Inbound from YADF, 2026-07-27. |
| `buildfor-defaulted-args-diverge-between-entry-points` | Two callers render the same declaration differently. |
| `docdrift-4-survive-a-converged-autodoc` | 3 of its 6 were `exception-cref-transitive-raise`, now FIXED. The remaining shape is the `TreeSitter.pas` one: the doc WRITER and the doc CHECKER disagree about the same managed block. |
| `cycles-scope-and-local-var-refs` | A local resolved to another unit's field. |
| `loader2019-formcreate-inifile-leak` | RE-MEASURED 2026-08-16: still fires against a fresh DB, unaffected by the object-leak fixes. A correct finding about an EXTERNAL project; closing it needs an edit to `C:\Projects\Loader2019`, which is the owner's call. |

## Open -- NOT verifiable in a normal session

These need a large corpus or an hours-long rebuild, and **were not re-measured
today** -- say so rather than implying they were.

`library-reindex-25x-slower-on-large-db` (cause identified and measured) ·
`incremental-index-hangs-on-large-db` · `indexer-livelock-when-two-platforms-run-concurrently`
(diagnosed) · `index-all-win32-library-rebuild-aborts` ·
`lint-all-project-wide-phase-dominates-runtime` (largely fixed 2026-08-12) ·
`index-runs-are-not-resumable` (**CORRECTNESS HALF FIXED 2026-08-16** -- the
fingerprint was stamped BEFORE the walk, so a killed run silently kept stale
parses; now committed only on completion. Per-file resume still open) ·
`codelens-cache-has-no-eviction` (confirmed unbounded -- `Clear` and a per-file
`Remove`, no size bound; lives in the IDE plugin BPL, which needs a build with
the IDE closed).

## Open -- not defects, kept here deliberately

`rule-hardening-plan-2026-08-13` (a plan answering an owner question) ·
`exception-class-unit-and-generated-exception-types` (feature request --
**MEASURED 2026-08-16: 64 distinct messages on ORM3, not the 400 that would have
killed it**, and normalization collapses 64 -> 63, so build Stage 1) ·
`converter-editor-phase-g-engine-findings` (workstream status: *"NOT pushed, NOT
merged, NOT deployed. Deliberate."* -- its one concrete engine ask, the
`#mapping`/`#apply` rejection, is **FIXED 2026-08-16**; findings 2.4-2.11 remain)
· `ide-lsp-ram-and-shim-todo` (items 3-4 still blocked on the IDE being
startable; §1.1's ask **folded into the union design 2026-08-16**, correcting a
wrong premise there) · `yadf-share-review-marker-hash` (owner request for a
shared hashing helper -- **RE-COUNTED 2026-08-16: 249 markers across three
repos**, so the "changing the normaliser is nearly free" window has closed).
