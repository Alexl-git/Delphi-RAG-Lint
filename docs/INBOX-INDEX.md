# INBOX index -- 7 open notes

> **THE STANDING LIST NOW LIVES IN `docs\OPEN-ITEMS.md`.** That file answers
> "what is left?" and is the one to re-read. This file is the narrative history:
> what was retired, when, and why. Session 25 close: **7 open / 111 retired**.
>
> Retired 2026-08-17: `indexer-fingerprint-disagrees-between-entry-points`
> (headline fixed and verified on a real database; its unrelated FK finding was
> SPLIT into its own note rather than keeping a discharged note open) and
> `yadf-share-review-marker-hash` (delivered: byte-identical vendored copy, drift
> test, negative control, zero re-stamps).
> Filed: `intermittent-fk-failure-on-incremental-reindex` (the split) and
> `extraction-fingerprint-uses-the-product-version` (found while cutting
> v1.4.0-alpha).

> **Session 25 (2026-08-17). 8 open -> 7; 108 retired. Plan A executed in full.**
>
> **Retired:** `index-runs-are-not-resumable` -- its last open item was
> mis-attributed to the engine. **PowerShell holds native stderr until the
> process exits**; the engine already flushes per file and per resolve line. The
> fix was a harness rule, now in `tests\README.md`.
>
> **Fixed, each with a suite verified RED against the previous build:**
> * **`indexer-fingerprint-disagrees-between-entry-points`** -- the two entry
>   points recorded different platform tokens for one DB, which silently disabled
>   per-file resume on the manifest path (the path the 12.5-hour library walk
>   uses). Chosen on a census of every DB, not on taste: 30 carried `plat=`, 2
>   carried `plat=win64` -- and one of those 2 is the 6,993-file library index,
>   so normalising the other way would have invalidated exactly the walk this
>   work exists to protect.
> * **`incremental-index-hangs-on-large-db`** (diagnosis half) -- the calls
>   resolve now announces WHOLE-DB **and its reason** before running, instead of
>   after. It was never hanging; it was a documented 37-minute pass printing
>   nothing.
> * **`yadf-share-review-marker-hash`** -- vendored byte-identical into YADF with
>   a drift test, zero re-stamps, `NormalizeLine` untouched.
>
> **`seealso` memo: the planned key would have hit ZERO times.** The plan said to
> copy the `OverloadArityTag` memo, keyed on the symbol id. But `Build` runs once
> per declaration, so that key can never repeat. Measuring the block first showed
> the repetition is in what it LOOKS UP: 913,357 sibling rows materialised from
> **322 distinct parents**. The key is the PARENT id. A distinct-key counter is
> what made the difference visible, and it cost one instrumented run.
>
> **A trap that cost an hour, now written into two places.**
> `NoDefaultCurrentDirectoryInExePath=1` is set on this machine, so
> `cd third_party\dll-win64 && drag-lint lint-all ...` -- the "Reproducing" block
> in the perf note, verbatim -- runs `third_party\dll\drag-lint.exe`, the frozen
> **Win32 build of 2026-07-05**, off PATH. It answers plausibly: 33,626 findings
> against the current build's 14,764, with ~20 `.scm` rules silently at zero. It
> reads as a catastrophic regression and is none. Use `.\drag-lint.exe`.
>
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

## Open -- all 7, current as of session 25 close (2026-08-17)

Re-verified by listing `docs\INBOX-*.md`, not by trusting this table. Every note
retired above has been removed from it. **Ordered by what a next session should
pick up first.**

| # | note | WHAT IS LEFT (the shipped parts are in each note's banner) | size |
|---|---|---|---|
| 1 | `buildfor-defaulted-args-diverge-between-entry-points` | **The only fully-specified, unstarted item.** One real residue: **`AExtraStores`**. `document --qname --db A --db B` mines cross-DB inbound facts; the checker renders Fresh single-store, calls the block stale, `--fix` deletes the entry, `document` re-adds it -- a ping-pong. Only `dl:shared` units are forgiven. Fix as an **options record** read by the Fresh render, `Analyze`, both `FixEdits*` and `BuildFor` -- NOT "thread four args", which fixes nothing observable (`ABaseDir` is dead unless `AIncludeSince`; `AComplexityMin` is latent; `AIncludeSince` is checker-side). **Write the two-DB fixture test first.** Bonus: clears 2 `too-many-parameters`. Also **update the note's header**, which still describes a checker-vs-repairer divergence that no longer exists. | 4-6 h |
| 2 | `lint-all-project-wide-phase-dominates-runtime` | `per-file scan` is now **53% of the run (145.86 s of 276.62 s)** and the only phase never optimised -- but it IS now attributed (144.34 of 145.37 s): `Linter.LintFile` (.scm) 56.17 s + `FlowChecker.Check` 46.49 s = **71%**. **Confirmed structurally, cost NOT measured:** `TLinter` does not use `TAstParseCache` (`Linter.pas:681`), so every file is parsed TWICE -- **time the parse alone before acting.** Also still open: `unused-unit-in-uses` ~17 s. **Refuted, do not revive:** the quadratic `Findings := Findings + X` measures **0.00 s**; and the `.scm` double parse is real but worth **1.38 s of 271 s**. ~~`ToFactRef` cross-DB id bug~~ -- **FIXED in session 24 (`8605017`)**; `Doc.Facts.pas:2179` passes `ExStore`. This row claimed it was open for two sessions after it was closed. | varies |
| 3 | `incremental-index-hangs-on-large-db` | The ANNOUNCE shipped (it was never a hang). What is left is the real fix: **relax the scoped-resolve gate for pure type ADDITIONS**, so adding units to a library index stops forcing a whole-DB pass. Correctness-sensitive; `DRAGLINT_NO_SCOPED_RESOLVE` (`Storage.SQLite.pas:3930`) is the A/B equivalence hatch. The refuted O(corpus) affected-set claim STAYS refuted -- this is the GATE, not the set. | ~1 day |
| 4 | `indexer-fingerprint-disagrees-between-entry-points` | Headline FIXED and verified on a real DB. Open only for the **second, unrelated finding**: an INTERMITTENT `FOREIGN KEY constraint failed` during incremental reindex, seen ONCE. DB verified NOT corrupt at the moment of failure (`foreign_key_check` 0, `integrity_check` ok, no orphans). Suspected in `ResolveCallTargets` when many files change at once. **Next step is reproduction**, not a fix: touch ~40 files, incremental index, repeat. Worse than it looks -- the section is left unbuilt while the run reports ERROR and a scripted sweep moves on. | unknown |
| 5 | `exception-class-unit-and-generated-exception-types` | Feature request, not a defect. Scope was settled in session 22 by an **AST-based** count: **64 distinct messages on ORM3**, normalization collapses 64 -> 63. (A session-25 re-measure produced "42" and is **retracted** in the note -- different population, different set, regex instead of AST.) **Blocked on FOUR OWNER RULINGS**, chiefly what *"fits"* means in Stage 1: normalized message match, or class-name match? Payoff 19 findings. | needs owner |
| 6 | `ide-lsp-ram-and-shim-todo` | Headless half DONE (`tools\lsp-diag\bpl-inventory.ps1`: 209 + 63 + 182 registered packages; the 4 absent files are all `__`-prefixed, i.e. disabled, which is normal). **Genuinely IDE-bound:** TODO 2b error capture, live `ModuleMemorySize` ranking, and disable-then-**re-measure** (do not skip step 5 -- a wrongly-removed package fails when a FORM opens, not at IDE start). TODO 4's 32-bit-forwarding relay is testable headlessly and NOT started. | owner + 3-4 h |
| 7 | `yadf-share-review-marker-hash` | Ships DONE (byte-identical vendored copy + drift test + negative control, zero re-stamps). Open only as the standing constraint: **`NormalizeLine` is frozen** -- changing it invalidates all **249** markers across three repos, and changing it in the mirror also breaks the drift test. | closed unless the owner wants a YADF-side checker |

## A note on the two labels this index used to carry

"Verifiable now" versus "not verifiable in a normal session" has been dropped.
Session 23 found the second group was mostly mislabelled: the Win32 rebuild had
already succeeded, the 25x slope IS reproducible on a 3 MB fixture, and the ORM3
profile that "needs a long run" takes nine minutes. A label that discourages
measurement is worse than no label.