# INBOX index -- 8 open notes

> **Session 24 (2026-08-16 -> 08-17). 9 open -> 8; 107 retired; 2 filed AND closed, 1 filed and OPEN.**
>
> **Retired:** `converter-editor-phase-g-engine-findings` (2.1-2.11 all fixed;
> the last, 2.5's product half, shipped as the owner's shape -- `query --name`
> orders a same-named VCL/FMX tie by the framework the run's own project writes
> in its `uses`, with **no `--framework` flag and no built-in default**);
> `rule-hardening-plan-2026-08-13` (last live row, `unused-public-symbol`, 12 ->
> 6 -- and of that note's ten rows exactly ONE needed the fix it described, five
> were stale and fired zero times, and one was fixed for a completely different
> reason than the one written down); plus the two filed and closed below.
>
> **Also shipped:** `lint-all` **572 s -> 320 s (-44%)**, report byte-identical
> -- and it was never the SQL: `FindUnresolvedNameCallers` costs 2.41 s, not 269,
> so the famous ~80x in-process gap never existed. **Per-file index resume** (a
> killed 12.5-hour walk now continues instead of restarting). `find-unit` and
> `resolve-uses` both fixed to read every `--db`; an extra store's caller now
> gets its overload tag from THAT store.
>
> **The `.bat` thread, which began as a footnote and produced the most.**
> `resolve-uses` shipped a multi-DB defect while carrying a test that PASSED --
> because that test put both units in ONE database, the single configuration in
> which the bug cannot appear. Chasing why nobody had noticed found **68 `.bat`
> tests the battery had never enumerated**, every one pointed at the RETIRED
> Win32 exe, which reports the SAME version string as the current build, so a run
> against the corpse looked real. Repointed and driven: **15 FAIL -> 0** on the
> v021 chain, plus 19 further fixtures that had **never executed once**, all from
> one broken template. That in turn surfaced a live engine regression --
> `generate-docs` emitting no `<returns>` for any class function. **All 60 are
> now driven; 0 dark.**
>
> Two of my own calls were wrong and are corrected in those notes: their status
> was not hopeless (55 of 60 passed immediately), and the last 19 were not
> "IDE-bound" -- they compile against `designide` headlessly; they were broken
> scripts nobody could see fail.
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

## Open -- all 8, current as of session 24 close

Re-verified by listing `docs\INBOX-*.md`, not by trusting this table. Every note
retired above has been removed from it.

| note | shape |
|---|---|
| `indexer-fingerprint-disagrees-between-entry-points` | **NEW 2026-08-17, and it silently disables the per-file resume shipped the same day.** `index --all --only <Section>` stamps `plat=` (`TPlanSection.Platform` is `'` for closure sections BY DESIGN, `Index.Plan.pas:50`); `index <dir> --db` stamps `plat=win64`. One DB, two spellings -> alternating entry points makes `Prev <> Cur` and re-parses everything. Worst on the manifest path, which is what the 12.5-hour library walk uses. Pre-existing; the new per-file stamps made it visible. **Decide by measurement** (count the spellings across every DB) -- normalising costs one full re-parse per DB. Same note records an INTERMITTENT `FOREIGN KEY constraint failed` on incremental reindex: not reproducible, DB verified NOT corrupt at the moment of failure, next steps written down. |
| `lint-all-project-wide-phase-dominates-runtime` | **HEADLINE DISCHARGED: 572 s -> 320 s (-44%), report byte-identical.** It was never the SQL. `FindUnresolvedNameCallers` costs **2.41 s, not 269** -- its in-process 0.56 ms/call AGREES with the external replay, so **the ~80x gap never existed**; the timer enclosed something else. The cost was **`OverloadArityTag`, 255.48 s (10.52 ms x 24,286 calls)**, running `FindAllChildSymbols` per rendered caller row. Fixed with a memo keyed on **(store pointer, symbol id)** -- ids are per-DB. Four hypotheses (CTE, index, statistics, the `NOT IN` predicate) plus a shipped plan pin and ANALYZE were all aimed at the wrong statement, because no timer had a CALL COUNT beside it. **Now open, all smaller and independent:** `per-file scan` is the new dominant phase (141 s of 320, never profiled), `class-metrics` 56 s, `seealso` 17.6 s, `unused-unit-in-uses` ~17 s, and a separate CORRECTNESS bug -- `ToFactRef` in the extra-store loop hands `OverloadArityTag` an id from the WRONG DB. |
| `index-runs-are-not-resumable` | Headline (per-file resume) SHIPPED. Open for ONE thing, and its cause is now **MEASURED: the buffering is PowerShell, NOT the engine.** The engine already flushes stdout per file (`Indexer.pas:1176`, guarded by `run_index_progress_flush.ps1`); PowerShell `2>` holds ALL native stderr to process exit (0 bytes for a whole 52 s run, 4462 at exit), while cmd.exe grows from t=1 s. **Fix is in the HARNESS** -- redirect long runs via `cmd.exe` / `Start-Process -RedirectStandardError` and document it; an optional `Flush(ErrOutput)` after `:620` is secondary. Then CLOSE this note. |
| `incremental-index-hangs-on-large-db` | **STILL LIVE -- REPRODUCED 2026-08-17.** Not a hang: a SILENT WHOLE-DB PASS. New units introduce new type names, so `ScopedResolveIsSound` fails its type-equality gate (`Storage.SQLite.pas:3949-3951`) and calls resolve falls back to the whole database -- 3.4 M refs, a cost the code documents as **"37 MINUTES on a 2 GB index"** (`:8712-8714`). Measured: 84 new files into a 2.3 GB copy of library-Win64 -> CPU-bound 450 s+, killed at 8 min. The refuted O(corpus) affected-set claim STAYS refuted -- this is the GATE, not the set. **Cheap fix (~1 h) is DIAGNOSIS:** announce "WHOLE DB + reason" BEFORE the pass; today the scoped/whole line (`:8843`/`:8846`) prints only after, which is why it looks like a hang. Gate relaxation for pure type ADDITIONS is separate, ~1 day, correctness-sensitive (`DRAGLINT_NO_SCOPED_RESOLVE` at `:3930` is the A/B hatch). |
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