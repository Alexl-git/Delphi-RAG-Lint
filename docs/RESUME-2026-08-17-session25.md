# RESUME -- session 25 (2026-08-17)

`docs/PLAN-SESSION-25.md` was executed. **Section A complete, B complete, C
partial.** This file is the state snapshot; the plan carries the per-item outcome
table at its head.

## State

`main` @ **`491f921`**, working tree **clean**, **128 unpushed ON PURPOSE**
(the owner lifts that gate). Battery **320/320 pass, 0 fail, 19.0 min**
(321 found, 1 excluded by the standing default exclusions).

## Headline

**`lint-all` on ORM3: 332.12 s -> 276.62 s**, report byte-identical throughout
(stdout SHA256 `1BA0CA2D1B2B23F2176320CD109989449BCE22FA3478BBBE772792E787A48A29`,
2,161,951 bytes, 14,764 findings = 32 error / 2,156 warning / 12,173 info /
403 hint). Cumulatively with session 24: **572 s -> 277 s.**

INBOX **8 open -> 7**, 108 retired.

## What shipped

| | before | after |
|---|---|---|
| `seealso` (doc-drift) | 18.57 s | **2.29 s** |
| `class-metrics` phase | 58.04 s | **19.24 s** |
| `ResolveTypeCategory` | 40.99 s | **1.78 s** |

* **A1 `seealso` memo** -- keyed on the **PARENT id**, caching the filtered
  (id, qualified-name) list of routine-kind children. 913,357 sibling rows
  materialised -> 17,559.
* **A2 fingerprint** -- `EffectiveIndexPlatform` normalises `''` -> `Win64`
  inside `IndexerFingerprint`, so both entry points record one token. This
  re-enables per-file resume on the manifest path, where it had been silently
  dead.
* **A3 whole-DB resolve announce** -- printed BEFORE the pass, naming the reason,
  which is now recorded at the latch (`FScopeWholeWhy`) instead of guessed.
* **A4 YADF review-marker** -- byte-identical vendored copy + drift test.
* **A5** -- harness rule in `tests\README.md`; note closed.
* **B1 `class-metrics` memo** -- `RtcMemo`, local to the call.
* **B2** -- per-file scan attributed, not optimised (see below).
* **C2 partial** -- `tools\lsp-diag\bpl-inventory.ps1`.
* **C3** -- unblocked by measurement, still needs owner rulings.

Three new suites, all RED-verified against the previous build:
`run_index_fingerprint_entry_points.ps1`, `run_index_calls_resolve_announce.ps1`,
`run_reviewmarker_yadf_mirror.ps1`. Battery **317 -> 320**.

## READ THIS BEFORE ANY BEFORE/AFTER MEASUREMENT

**`NoDefaultCurrentDirectoryInExePath=1` is set on this machine.** So

```
cd C:\Projects\Delphi-RAG-lint\third_party\dll-win64
drag-lint lint-all --db ... --quiet          <-- WRONG BINARY
```

does **not** run the exe in that folder. cmd skips the CWD and resolves the bare
name from PATH, to `third_party\dll\drag-lint.exe` -- the frozen **Win32 build of
2026-07-05**. It starts, it lints, and it answers with two-month-old rules:

| | frozen Win32 (2026-07-05) | current build |
|---|---|---|
| findings | 33,626 | 14,764 |
| `large-magic-number` | 19,729 | 3,324 |
| `used-unit-not-resolvable` | 2,704 | 21 |
| ~20 `.scm` rules | **0** | firing |

That was the exact "Reproducing" block in the perf note, followed verbatim. It
cost an hour of diffing rule histograms, hashing the rule catalogue and
inspecting the ORM3 index before `where drag-lint.exe` was run.
**Use `.\drag-lint.exe`.** The tell is the profile FORMAT -- it changes whenever
the profiler does, so an old-format breakdown means an old binary.

Both `tests\README.md` and the perf note now carry this.

## Next action -- C1, and it is the only unstarted plan item

`docs\INBOX-buildfor-defaulted-args-diverge-between-entry-points.md`, as the
plan's C1 describes it: the **options-record refactor**, not "thread four args"
(which fixes nothing observable -- three of the four are dead, latent, or
checker-side).

The one real residue is **`AExtraStores`**: `document --qname --db A --db B`
mines cross-DB inbound facts; the checker renders Fresh single-store, flags the
block stale, `--fix` regenerates single-store and deletes the entries, `document`
re-adds them -- a ping-pong. Only `dl:shared` units are forgiven.

One record read by the Fresh render, `Analyze`, both `FixEdits*` and `BuildFor`.
**Test first:** a two-DB fixture with a symbol in A called only from B;
`document --db A --db B --apply` then `lint-all --fix` must not strip the inbound
entry. Bonus: clears two `too-many-parameters` findings. **Update that note's
stale framing while there** -- its header still describes a checker-vs-repairer
divergence that no longer exists.

## The next perf target, now that it is attributed

`per-file scan` is **145.86 s of 276.62 s (53%)** and is the only phase never
optimised. It is no longer unattributed -- 144.34 s of 145.37 s is accounted:

```
  Linter.LintFile (.scm)     56.17 s  (566 files,  99.24 ms/file)   39%
  FlowChecker.Check          46.49 s  (566 files,  82.13 ms/file)   32%
  TypeAware                   9.75 s
  DeadCodeChecker.Check       7.56 s
  ...27 further checks, each under 3 s...
  (Findings append)           0.00 s   <-- THE NAMED SUSPECT, REFUTED
```

The quadratic `Findings := Findings + X` accumulation -- ~20k appends over an
array reaching 54,245 records -- **costs 0.00 s**. Do not revive it.

**The double parse is CONFIRMED; its cost is NOT.** The built-in checks share
one parse per file via `TAstParseCache`, but `TLinter` does not use it --
`CheckFileImpl` builds its own `TTSParser` and parses the file
(`DRagLint.Lint.Linter.pas:681-684`). So every file is parsed twice per
`lint-all`.

What that does NOT tell you is how much of the 56.17 s `.scm` slot is the parse
versus executing 114 tree-sitter queries. Routing `TLinter` through
`TAstParseCache` saves at most ONE parse per file. **Time the parse alone
first** -- acting on a plausible mechanism before measuring it is the exact
failure this whole note thread records four times.

## Still open / not done

* **C1** -- not started (above).
* **`incremental-index-hangs-on-large-db`** -- the ANNOUNCE shipped; relaxing the
  scoped-resolve gate for pure type ADDITIONS did not, deliberately. ~1 day,
  correctness-sensitive, has an A/B hatch (`DRAGLINT_NO_SCOPED_RESOLVE`).
* **The intermittent FK failure** in the fingerprint note -- one occurrence, not
  reproduced, keeps that note open.
* **C3 `exception-class-unit`** -- measured on ORM3: 139 findings, 80 with a
  literal message, **42 distinct texts** (not the feared 400), 12 raised from 2+
  sites. So scope is not the obstacle. But **59 of 139 carry no literal at all**
  (`Format(...)`, variables, concatenation), which stage 3 cannot serve -- ship
  stage 1, be sceptical of stage 3. Four owner rulings still block it.
* **D** -- the IDE checklist still needs the owner at a keyboard. The headless
  half is done: `pwsh -File tools\lsp-diag\bpl-inventory.ps1` (209 + 63 + 182
  registered packages, 151 + 26 + 132 MB on disk; 4 absent files are all
  `__`-prefixed = disabled, which is normal, not breakage).
