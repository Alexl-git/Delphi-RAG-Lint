# Session 25 implementation plan

> ## EXECUTED 2026-08-17. Section A complete, B complete, C partial.
>
> | item | outcome |
> |---|---|
> | **A1** `seealso` memo | **DONE** -- 18.57 s -> 2.36 s. The plan's KEY was wrong (see below); the measured key is the PARENT id. Report byte-identical. |
> | **A2** fingerprint disagreement | **DONE** -- `EffectiveIndexPlatform`, chosen on a census of all 32 DBs. Suite RED-verified. |
> | **A3** announce the whole-DB resolve | **DONE** -- announced BEFORE the pass, with the reason recorded at the latch. Suite RED-verified. |
> | **A4** YADF review-marker | **DONE** -- byte-identical vendored copy + drift test + negative control. Zero re-stamps. |
> | **A5** redirected output | **DONE** -- harness rule written into `tests\README.md`; the note is CLOSED. |
> | **B1** `class-metrics` memo | **DONE** -- instrumented first: `ResolveTypeCategory` 40.99 s of 58.49 s, 266,715 calls / 7,568 distinct keys. Memo shipped. |
> | **B2** per-file scan | **ATTRIBUTED, not optimised** -- 144.34 s of 145.37 s accounted. The named suspect (quadratic append) measures **0.00 s**. |
> | **C1** `buildfor-defaulted-args` | NOT STARTED |
> | **C2** IDE/LSP headless half | **PARTIAL** -- `tools\lsp-diag\bpl-inventory.ps1` ships the registry+size audit. |
> | **C3** `exception-class-unit` | DEFERRED as planned (needs four owner rulings). |
> | **D** owner checklist | unchanged, still needs a keyboard. |
>
> **The plan itself was wrong in one place, and it is the instructive one.** A1
> said to key the memo on "(store pointer, symbol id)", copying the
> `OverloadArityTag` fix. That memo could never have hit: `Build` runs ONCE per
> declaration, so the declaration's own id never repeats. Measuring the block
> first -- with DISTINCT-KEY counts, not just call counts -- showed the
> repetition is in what it looks UP: 913,357 sibling rows from **322 distinct
> parents**. Same lesson as the one this plan opens with, one level down: a
> plausible fix aimed at an unverified attribution.
>
> **A trap worth more than any item here.** `NoDefaultCurrentDirectoryInExePath=1`
> is set on this machine, so the perf note's own "Reproducing" block
> (`cd dll-win64` then a BARE `drag-lint lint-all ...`) runs
> `third_party\dll\drag-lint.exe` -- the frozen **Win32 build of 2026-07-05** --
> off PATH. It reported **33,626 findings against the current build's 14,764**,
> with ~20 `.scm` rules silently at zero, and read as a catastrophic regression
> that did not exist. Use `.\drag-lint.exe`. Both the note and `tests\README.md`
> now say so.


Built from five parallel investigations (2026-08-17), each told to **re-measure
rather than trust its note**. That instruction paid: **three** of the seven notes
had materially wrong framing, one was assumed stale and is in fact live and
reproducible, and one of my own shipped features turned out to be silently
disabled on the path it was built for.

Corrected framings, so nobody re-derives them:
* `buildfor-defaulted-args` -- checker and repairer AGREE; only `AExtraStores` is real.
* `ide-lsp-ram-and-shim-todo` -- "IDE-blocked" is half true; two items are headless now.
* `index-runs-are-not-resumable` -- the buffering cause is **PowerShell, not the engine**.
* `incremental-index-hangs-on-large-db` -- **live, reproduced today**, and it is a
  silent 37-minute whole-DB pass, not a hang.

**Ordering principle:** verified-tight windows before big unattributed pools.
This session lost three prior sessions to a timer that enclosed more than its
name said, so "large number" is not a reason to start somewhere.

---

## A. Do first -- small, verified, pattern already proven

### A1. `seealso` memo -- 17.6 s, low risk (~1 h)

The only perf item with a **verified-tight timer window**: `Doc.Facts.pas:2511`
(TB0 reset) to `:2609` (`Inc(GBSeeAlso)`), containing only the `AIncludeSeeAlso`
block. Per declaration (4,309) it runs `GetCallEdgesFromSymbol` +
`GetSymbolById` per edge (`:2556-2560`) and `FindAllChildSymbols(ParentId)`
materialising every sibling (`:2581`).

**That is the exact shape the `OverloadArityTag` memo fixed this session** for
255 s, unmemoised here. Same fix: run-level memo keyed **(store pointer, symbol
id)** -- the pointer is load-bearing, ids are per-DB.

Gate: **report must stay byte-identical** (SHA256 of `lint-all` stdout on ORM3;
baseline 2,161,951 bytes / 14,764 findings). Pure reads, so it should be.

### A2. Fingerprint disagreement between entry points (~2 h + one decision)

`docs\INBOX-indexer-fingerprint-disagrees-between-entry-points.md`. **This
silently disables the per-file resume shipped in `bd30afa`, on the manifest path
-- which is the path the 12.5-hour library walk uses.** Highest-value correctness
item here despite being small.

`index --all --only <Section>` stamps `plat=` (`TPlanSection.Platform` is `''`
for closure sections by design, `Index.Plan.pas:50`); `index <dir> --db` stamps
`plat=win64`. Same DB, two spellings, so alternating them re-parses everything.

**Decision required before coding** -- and it needs a measurement, not an
opinion: read `schema_meta.indexer_fingerprint` from every DB in `resolve-dbs`
and count the spellings. That decides whether normalising costs minutes or hours
of one-time re-parse. Options are in the note; do not pick from the note alone.

**Positive control:** "the two entry points agree" passes trivially if both
return `''`. Assert instead that indexing by each entry point in turn causes
**no re-parse on the second run** (`skipped N up-to-date`, N = file count).

### A3. Announce the WHOLE-DB calls resolve BEFORE it runs (~1 h)

`INBOX-incremental-index-hangs-on-large-db.md` -- **still live, and REPRODUCED
2026-08-17**, which contradicts any assumption that it had gone stale.

Indexing 84 new files into a scratch copy of `library-Win64.sqlite` (2.3 GB): the
walk completed, ancestry 16.7 s, helpers 12.9 s, then **CPU-bound for 450 s+ in
the calls resolve** (9.9 s CPU per 10 s wall) and was killed at 8 minutes.

**Mechanism, and it is not a hang.** New units introduce new type names, so
`ScopedResolveIsSound` fails its type-equality gate
(`Storage.SQLite.pas:3949-3951`) and the run silently falls back to a WHOLE-DB
calls resolve over 3.4 M refs -- a cost the code itself documents as **"37
MINUTES on a 2 GB index"** (`Storage.SQLite.pas:8712-8714`).

The refuted O(corpus) affected-set claim **stays refuted**: this is the GATE, not
the set. Do not resurrect it.

**Smallest fix, and it is diagnosis rather than optimisation:** print
"WHOLE DB + reason" on stderr **before** the pass. Today the scoped/whole line
(`:8843` / `:8846`) prints only *after* it finishes, so a 37-minute pass is
indistinguishable from a hang while it runs -- which is exactly how this note
came to be filed. Positive control: the unfixed build lacks the announce line.

Larger, separate, correctness-sensitive: relax the gate for pure type
*additions*. The `DRAGLINT_NO_SCOPED_RESOLVE` A/B hatch (`:3930`) gives an
equivalence test. ~1 day; do not bundle it with the announce.

### A4. YADF review-marker helper -- share it WITHOUT touching the normaliser (~2-3 h)

`INBOX-yadf-share-review-marker-hash.md`. The note's pessimism ("249 markers, the
cheap window has closed") is right about changing the normaliser and wrong about
the request being blocked.

**Do not touch `NormalizeLine`** (`ReviewMarker.pas:327-442`); a change flips
`SameText(M.Hash, Want)` (`CLI.pas:6052`) for all 249 markers into mass "stale
review" re-reports. Instead: vendored copy of the unit into YADF + a
byte-identity battery test, shipping `HashWindow` **and**
`NormalizedIsLoneKeyword` (`:453-467`), **verify-and-warn only, zero re-stamps**.
The unit is pure (`SysUtils` + `Hash` only, `:22-23`), so this is cheap. Risk is
copy drift, caught by the identity test.

---

### A5. Redirected output -- the cause is DETERMINED, and it is not the engine (~30 min)

The residue of `INBOX-index-runs-are-not-resumable.md`. The note blamed the
engine ("stdout is block-buffered when redirected"). **Measured, that is wrong.**

The engine already flushes stdout once per file -- `Flush(Output)` at
`src\core\DRagLint.Core.Indexer.pas:1176`, guarded by
`tests\autotest\run_index_progress_flush.ps1`. The stderr counter
(`Indexer.pas:614/620`) has no flush, but the RTL's 128-byte buffer bounds its
lag to 2-3 lines.

Experiment, same 52 s index, both redirections, sizes polled every second:

```
cmd.exe  > 2>   out.log 128 -> 765 -> 2230 bytes within 4 s; err.log grew from t=1 s
PowerShell > 2> out.log 0 until an 8192-byte block
                err.log 0 BYTES FOR THE ENTIRE RUN, 4462 at exit   <- the ORM3 symptom
```

**PowerShell holds all native stderr to process exit.** So the fix is in the
HARNESS, not the engine: redirect long runs through `cmd.exe` or
`Start-Process -RedirectStandardError`, and say so in the runner docs. This is
already what this repo's own long runs do; the note simply mis-attributed it.

Optional and secondary: `Flush(ErrOutput)` after `Indexer.pas:620`. Positive
control -- a 2-file walk emitting under 128 stderr bytes, redirected via cmd and
polled mid-run: unfixed shows 0 bytes, fixed shows the line.

**Then close that note.** Its headline (per-file resume) shipped; this was the
only thing keeping it open.

## B. Then -- larger, but instrument before optimising

### B1. `class-metrics` memo -- up to 56 s, win unquantified (~2 h)

`ResolveTypeCategory` is called per `type_use` ref per class with no memo
(`ClassMetrics.pas:256,364,417`; `ComputeAllFanIn:400-434` is unconditional), and
each call runs `FindSymbolsByExactName`, materialising every same-named symbol
(`Storage.SQLite.pas:9156`) -- **the anti-pattern already fixed three times in
this codebase.** Memo keyed **(lowercase name, fileId)**; fileId matters, it is
the tie-break at `Storage.SQLite.pas:9159`.

But which of two candidates dominates is **not established** (the other is
`ComputeLCOM4`/`ComputeMiddleMan` re-parsing method bodies, `:439-449`). Add
sub-timers with CALL COUNTS first. One run, then decide.

### B2. `per-file scan` -- 141 s of 320 s, ZERO attribution (~1 h to instrument)

Timer opens `CLI.pas:10669`, closes at `:10752`. Per file it runs
`Linter.LintFile` (.scm rules, `:10691`), ~35 checker calls (`:10700-10737`),
4x `FindFileIdByPath`, then `TAstParseCache.Clear` (`:10742`). All checks share
ONE parse via `TAstParseCache.Get` (`ParseCache.pas:72-109`), so parsing is once
per file, not 35x.

**Do not optimise yet.** There are no sub-timers inside this bucket, and this
session's whole lesson is what happens when you act on an unattributed bucket
name. Instrument (per-check timers + counts), run once, then decide. It may
simply be 566 genuine file parses, in which case the honest outcome is to
**record it as irreducible and close it** rather than leave it open forever.

One named suspect worth timing explicitly: the quadratic
`Findings := Findings + X` accumulation, ~20k appends (566 x 35) each copying an
array that grows to 54,245 records with string fields. The note claims this
"never showed up" -- but what was measured there was the ownership **filter**
(0.03 s), not the accumulation, which lands inside this bucket. Unmeasured
hypothesis, flagged as such.

---

## C. Worth doing, but not urgent

### C1. `buildfor-defaulted-args` -- **the note's framing is now wrong** (~4-6 h)

Re-measured: the four parameters are **no longer a checker-vs-repairer
divergence**. The checker hardcodes the same values the repairer does
(`Drift.pas:615-617`; Fresh render `:986` omits `AComplexityMin` -> 10). They
AGREE. Per parameter: `ABaseDir` is dead unless `AIncludeSince=True`
(`Doc.Facts.pas:2619-2624`) -- not a defect; `AComplexityMin` is latent (manifest
= 10 = default); `AIncludeSince` is observable only via opt-in `document
--since`, and is checker-side, so threading the repairer alone fixes nothing.

The one real residue is **`AExtraStores`**: `document --qname --db A --db B`
mines cross-DB inbound facts (`Doc.Document.pas:862`), the checker renders Fresh
single-store (`Drift.pas:615,986`), `BlockDrifted` flags stale (`:1008`),
`--fix` regenerates single-store and deletes the entries, `document` re-adds --
**a ping-pong**. Only `dl:shared` units are forgiven (`:988-1008`).

Fix as the note's own options-record refactor (one record read by Fresh render,
`Analyze`, both `FixEdits*`, and `BuildFor`), not as "thread four args" -- that
alone fixes nothing observable. Bonus: clears two `too-many-parameters` findings.
Test: two-DB fixture, symbol in A called only from B; `document --db A --db B
--apply` then `lint-all --fix` must not strip the inbound entry.
**Update the note's stale framing when doing this.**

### C2. IDE/LSP -- **"IDE-blocked" is only half true** (~3-4 h headless)

`INBOX-ide-lsp-ram-and-shim-todo.md`. Headless-capable **now**:
* TODO 3 steps 3-4: registry enumeration of `Known Packages` / `Known IDE
  Packages` / `Known Packages x64`, plus on-disk BPL sizes as provisional
  ranking (note:113-118).
* TODO 4's relay: the "blocked on 2b" gate (note:128-131) applies only to the
  **64-bit-forwarding** variant. A 32-bit-forwarding superset relay is testable
  headlessly -- DelphiLSP was already probed over raw stdio without the IDE
  (note:42) and drag-lint's server speaks stdio with Content-Length framing
  (`src\lsp\DRagLint.LSP.Server.pas:30`). `tests\fixtures\T31_hoverform.bat:30`
  proves the dcc64/designide headless pattern.

Genuinely IDE-bound: 2b error capture (note:87-99), live module-size ranking,
in-IDE shim validation. **Human checklist is in section D below.**

### C3. `exception-class-unit` -- DEFER, and it is not implementable as written

Stage 1 ("config key naming the exceptions unit; `raise-bare-exception` reports
which existing class fits, or says none exists", note:122) needs **four owner
rulings** before anyone can start -- chiefly what *"fits"* means: normalized
message match, or class-name match? Normalization is only spec'd for Stage 3.
Payoff is 19 findings. Building blocks exist (`Doc.Facts.pas:1742` raise mining,
`Project.OwnRoots.pas:69` per-project config, `ProjectRules.pas:75` rule host).
Queue behind perf and correctness.

---

## D. Needs the owner at a keyboard -- one IDE session serves both items

1. Close all RAD Studio instances.
2. Run `tools\lsp-diag\arm-lsp-diagnostic.ps1`.
3. Start RAD Studio 13 **32-bit, fresh from the Start Menu**; open a
   representative project; exercise Code Insight until the 64-bit LSP failure
   appears.
4. With the IDE still open:
   `Get-Process bds | Select-Object -ExpandProperty Modules |`
   `Sort-Object ModuleMemorySize -Descending |`
   `Select-Object -First 60 ModuleName,ModuleMemorySize > modules.txt`
5. Run `collect-lsp-diagnostic.ps1`, then `disarm-lsp-diagnostic.ps1`.
6. Hand back `modules.txt` + the collect output.

(Disable/re-measure comes after analysis: Component -> Install Packages,
restart, repeat step 4 -- note:124.)

---

## E. Standing gates -- do not skip

* **Byte-identical report** for every perf change: SHA256 of `lint-all` stdout on
  ORM3 (baseline 2,161,951 bytes / 14,764 findings). A saving that moves one line
  of output is a regression with a stopwatch attached.
* **Every guard needs a POSITIVE CONTROL and a run against the UNFIXED build.**
  Five suites this session were RED-verified; one nearly passed vacuously
  because `git stash push -- <path> --quiet` reads `--quiet` as a pathspec and
  silently does not stash.
* **Never edit source during a battery** -- `.dpr` suites compile the engine.
* **Reindex before trusting the self-index.** It drifted ~250 lines during this
  session's edits and a subagent silently fell back to Grep.
* `.pas`/`.dpr`/`.bat`/`.ps1` are ASCII + CRLF. `sed -i` rewrites a file even
  when nothing matched, converting CRLF to LF; the encoding guard catches it.
