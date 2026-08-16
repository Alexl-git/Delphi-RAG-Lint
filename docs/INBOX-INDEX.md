# INBOX index -- 23 open notes (was 60 at the start of 2026-08-16)

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
| `exception-cref-transitive-raise` | Fixture-testable. |
| `autodoc-caller-list-fabricates-callers-for-common-method-names` | Its own banner warns only `Create` was re-measured. |
| `autodoc-returns-section-incomplete` | Inbound from YADF, 2026-07-27. |
| `buildfor-defaulted-args-diverge-between-entry-points` | Two callers render the same declaration differently. |
| `docdrift-4-survive-a-converged-autodoc` | Under measurement at the time of writing. |
| `cycles-scope-and-local-var-refs` | A local resolved to another unit's field. |
| `parse-error-shellshock-units` | Needs the named units to reproduce. |
| `loader2019-formcreate-inifile-leak` | An external-project finding; re-check against the object-leak fixes. |

## Open -- NOT verifiable in a normal session

These need a large corpus or an hours-long rebuild, and **were not re-measured
today** -- say so rather than implying they were.

`library-reindex-25x-slower-on-large-db` (cause identified and measured) ·
`incremental-index-hangs-on-large-db` · `indexer-livelock-when-two-platforms-run-concurrently`
(diagnosed) · `index-all-win32-library-rebuild-aborts` ·
`lint-all-project-wide-phase-dominates-runtime` (largely fixed 2026-08-12) ·
`index-runs-are-not-resumable` (confirmed: only WAL checkpoints exist) ·
`codelens-cache-has-no-eviction` (confirmed unbounded -- `Clear` and a per-file
`Remove`, no size bound; lives in the IDE plugin BPL, which needs a build with
the IDE closed).

## Open -- not defects, kept here deliberately

`rule-hardening-plan-2026-08-13` (a plan answering an owner question) ·
`exception-class-unit-and-generated-exception-types` (feature request) ·
`converter-editor-phase-g-engine-findings` (workstream status: *"NOT pushed, NOT
merged, NOT deployed. Deliberate."*) · `ide-lsp-ram-and-shim-todo` (items 3-4
blocked on the IDE being startable) · `yadf-share-review-marker-hash` (owner
request for a shared hashing helper).
