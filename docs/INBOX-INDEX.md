# INBOX index -- 9 open notes (was 13; 23 that morning; 60 at the start of 2026-08-16)

> **Session 23 (2026-08-16, evening). 13 -> 9 open, 103 retired.**
>
> **Retired:** `index-all-win32-library-rebuild-aborts` (not blocked -- the
> rebuild ALREADY succeeded 08-12 in one 2h10m pass; root cause found 07-29 as an
> EXTERNAL `Stop-Process` kill, evidenced by exit code exactly -1);
> `library-reindex-25x-slower-on-large-db` (the slope IS reproducible on a ~3 MB
> DB -- 1.3x -> 11.4x -- and the FK-index fix already shipped);
> `callback-pass-is-a-ref-but-not-a-call-edge` (filed and fixed the same day);
> `used-before-assignment-...` (closed by DECISION -- shape A shipped, B/C/D
> accepted, 0 findings on all four consumer projects);
> `stale-manifest-shadows-canonical-beside-debug-exe` (deleted; the debug build
> now errors honestly instead of naming a DB that no longer exists). One further
> note was filed AND refuted the same day and sits in `INBOX-Done` as a record of
> the refutation, not a defect.
>
> **Engine fixes shipped, each RED-verified:** `unused-parameter` callback
> suppression (syntactic, because one real registration lives in an inactive
> `$IFDEF` no store can see); `find-callers --resolved` reporting callback
> reaches as `[callback]`; **a RECORD deciding class ancestry** (three `TTimer`
> in library-Win32, `DosCommand.TTimer` sorting first, which is what made an
> owned `TTimer.Create(LDlg)` read as a leak); walk progress n/total+ETA;
> CodeLens LRU cap. DataCopy **43 -> 31**; own source `unused-parameter`
> **99 -> 75**.
>
> **The measurement discipline earned its keep three times.** The
> `unused-parameter` note's prescribed store-backed fix could not have worked;
> the `query` exit-code contract was misrecorded; and doc-drift's dominant
> sub-item is `unresolved-name` (269 s), not `calls` (0.99 s) as a YADF-sized
> profile predicted. Each is written into its own note.

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

## Open -- all 9, current as of session 23 close

Re-verified by listing `docs\INBOX-*.md`, not by trusting this table. Every note
retired above has been removed from it.

| note | shape |
|---|---|
| `lint-all-project-wide-phase-dominates-runtime` | **THE BIGGEST REMAINING WIN.** `unresolved-name` is **269 s of ORM3's 530 s** run -- 51%. NOT the CTE (~6 s) and NOT a missing name index (present and used). It is a query PLAN difference: identical SQL is ~0.74 ms/call through an external SQLite versus ~62 ms in-process. A `+` plan pin shipped and bought ~4% (noise); `sqlite_stat1` now exists, so the with-statistics number is the next measurement. If that fails too, log `sqlite3_libversion()` and EXPLAIN **through FConn**. |
| `index-runs-are-not-resumable` | Group B 5b, and the plan's own HIGHEST-RISK item. Additive `files.indexed_at_fingerprint`; the stamp **must** sit inside the transaction `CommitFileTx` closes, or it recreates the silent-staleness bug fixed in session 22. Full design in `PLAN-SESSION-23-IMPLEMENTATION.md` section 5b. Not started. |
| `rule-hardening-plan-2026-08-13` | **Essentially one item left.** Re-measured across all four consumer projects: items 1/3/5/7/8 now fire **ZERO** times; 2+6 are down to 0; item 4 DONE. Live: **item 9 `unused-public-symbol` (12)** -- 9 are YADF shared-unit hints of which 8 are alive in a sibling and `OptionsHelpText` is genuinely dead (x3), plus 3 in DataCopy. The fix is to consult the sibling DBs a unit's own `dl:shared` header NAMES, which needs `TProjectLintRules.Run` to take extra stores (it takes one `ISymbolStore` today). |
| `converter-editor-phase-g-engine-findings` | 2.4-2.11 ALL closed. Open only for 2.5's product half -- and the owner has ANSWERED the shape: the tie is LIBRARY-ONLY (a project DB returns 0 rows for `TEdit`) and the framework is derivable from the project's own `uses` (DataCopy 25 `Vcl.*` / 0 `FMX.*`). So: derive context, do NOT add a `--framework` flag. Ordinary engine work, no ruling needed. |
| `incremental-index-hangs-on-large-db` | The "hang" is the whole-DB resolve; scoped resolve fixes the body-edit shape but an ADDED type still falls back. NOTE: a session-23 suspicion that the incremental affected-set is O(corpus) was **refuted on real code** (748 affected refs, smaller than the changed file's own 1,988) -- do not carry that link forward. |
| `buildfor-defaulted-args-diverge-between-entry-points` | STALE for the function it names. Remaining: `ABaseDir` / `AIncludeSince` / `AExtraStores` / `AComplexityMin` still defaulted on the repair path -- `AExtraStores` is the risky one (cross-DB fan-out), so use a cross-DB fixture. |
| `exception-class-unit-and-generated-exception-types` | Feature request, not a defect. **MEASURED: 64 distinct messages on ORM3, not the 400 that would have killed it**, and normalization collapses 64 -> 63. Build Stage 1. |
| `ide-lsp-ram-and-shim-todo` | Items 3-4 need a live IDE. NOTE: the "needs the IDE closed" blocker is now DISCHARGED for BPL work -- both design-time packages were rebuilt in session 23, and 37.0 registers a 32-bit and a 64-bit IDE separately (`Known Packages` / `Known Packages x64`). |
| `yadf-share-review-marker-hash` | Owner request for a shared hashing helper. **RE-COUNTED: 249 markers across three repos**, so the "changing the normaliser is nearly free" window has closed. |

## A note on the two labels this index used to carry

"Verifiable now" versus "not verifiable in a normal session" has been dropped.
Session 23 found the second group was mostly mislabelled: the Win32 rebuild had
already succeeded, the 25x slope IS reproducible on a 3 MB fixture, and the ORM3
profile that "needs a long run" takes nine minutes. A label that discourages
measurement is worse than no label.