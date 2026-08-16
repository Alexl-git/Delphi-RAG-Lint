# RESUME -- 2026-08-12. The `_D-RAG` project home, declared lint ownership, rule fortification

Supersedes `RESUME-2026-08-11b-resolve-passes-editors-and-yadf.md` as the entry point.

Branch **`fix/lint-noise-round1`**, HEAD **`dbb5069`**, **25 commits this session**,
**no remote branch at all** (`git ls-remote --heads origin fix/lint-noise-round1` is
empty -- the work is local only). `main` still has 3 unpushed.

Working tree dirty ONLY with the known never-commit set (`FEATURES.txt`,
`docs/lint/PLAN-autodoc-*`, the four `dclDragLintWizard.{bpl,dcp}`) plus untracked
INBOX/RESUME notes.

Full blow-by-blow, including every review finding and ruling:
`.superpowers/sdd/2026-08-11-project-drag-lint-home-and-lint-ownership/progress.md`.

## Status -- what shipped

**1. Every project index moved into its project's own folder.**

```
<folder of the .dproj>\_D-RAG\<project file base>.sqlite
```

All **27 migrated for real** and verified: file-row counts identical to the
pre-migration snapshot, `quick_check` ok, 0 foreign-key violations. No reindex was
needed -- no table stores a database's own path. `library-<platform>.sqlite` and the
SQL index stay in `C:\Projects\.drag-lint` (no project folder), so the layout is
deliberately mixed.

**2. `lint-all` reports only the project's own code.** Ownership is DECLARED in
`<project folder>\_D-RAG\drag-lint-project.json` (`ownRoots`, absolute or relative to
that folder). `--lint-third-party` restores the old behaviour.

**3. Five lint rules fortified, and YADF's genuine warnings fixed.**

| measure | before | after |
|---|---|---|
| YADF total findings | 1,072 | **259** |
| YADF warnings | 70 | **24** (all `doc-drift`, see below) |
| ORM3-Micronite2027 scanned | 641 | **565** (keeps all 295 `COMMON\OBJECTS`) |
| battery | 248/255 | **250/255** |

## Resume point

Branch `fix/lint-noise-round1` @ `dbb5069`, nothing in flight, no half-finished task.

Build + deploy (needed before ANY measurement -- a stale binary lies):

```
# delphi-build skill recipe: wrapper .bat -> Start-Process -Wait -> read the log
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 src\cli\drag-lint.dproj
copy src\cli\Win64\Debug\drag-lint.exe third_party\dll-win64\drag-lint.exe
```

Measure YADF (8 files, seconds):

```
third_party\dll-win64\drag-lint.exe lint-all --db C:\Projects\YADF\_D-RAG\YADF.sqlite --quiet --output C:\TEMP\claude\yadf.txt
```

Full battery -- **launch it with PowerShell `Start-Process`, detached** (see Gotchas):

```
pwsh -NoProfile -File tests\run_battery.ps1
```

## Not done yet -- ordered backlog

1. **`lint-all` is unusable on a large project.** ORM3-Micronite2027 burned **8,705
   CPU-seconds (2.4 h) without finishing**. The per-file scan of all 565 files completes
   in **under 3 minutes** -- the entire cost is the project-wide phase after it, and
   `--disable duplicate-code` does NOT fix it. Suspects: `TClassMetrics` (CBO/RFC/LCOM4
   are pairwise), the doc rules, `CheckUsedUnitResolvable`. **Add a per-phase timing
   breakdown before guessing** -- the indexer already has one behind `DRAGLINT_PROFILE=1`,
   the linter has none. Filed:
   `docs/INBOX-lint-all-project-wide-phase-dominates-runtime.md`.
2. **Autodoc still oscillates on YADF**, and it is what YADF's remaining 24 `doc-drift`
   warnings ARE. The managed blocks cite `GuardTest.dpr` / `YADFOT.dproj` symbols that
   YADF's per-project index cannot see, so drag-lint judges them stale and strips them;
   autodoc puts them back. **Re-documenting cannot fix this -- it restarts the loop.**
   The fix is to PRESERVE a fact that cannot be recomputed from the configured index,
   or to resolve doc facts across several DBs. Filed:
   `docs/INBOX-autodoc-not-idempotent-on-yadf.md`.
3. **A reindex never repopulates `call_edges` if the table was dropped or emptied.** The
   incremental resolve keys off files changed on disk; when only the DB was mutated it
   refills nothing, so any pre-D5 or interrupted index stays silently broken and
   `find-callers --resolved` returns nothing without erroring. `run_migrate_v13_to_v14.ps1`
   is red because of it. Filed:
   `docs/INBOX-reindex-does-not-repopulate-dropped-call-edges.md`.
4. **Two stale battery expectations** (`run_docrules_catalog.ps1` expects 115 built-in
   rules and finds 116; `run_rulecatalog_tests.ps1` expects naming count 9). They predate
   this session (`d18e862`). Trivially fixable -- **but verify the new counts are genuinely
   correct before matching them**, or you paper over whatever moved them.
5. **`run_smoke.ps1`** parses a literal `VERSION` from `DRagLint.CLI.pas`, which became
   `VERSION = DRAGLINT_VERSION` (an alias) in `c92cb1d`. Broken since then.
6. Remaining known rule gaps, each with an INBOX note: `create-inside-try`'s `FreeAndNil`
   branch has no fixture; `undeclared-identifier` tokenises `{ }` comment text as code;
   `referenced-never-set` misfires on record factories (`Result.FField := ...` is peeled
   to `Result`).
7. **YADF's fixes are UNCOMMITTED in its own repo** (`C:\Projects\YADF`, branch
   `autodoc-phaseC`). Deliberate: that tree already carried 11 modified files from an
   earlier autodoc run its author recorded as unstable, and committing would lock that in.
   `YadfMain.pas` / `YADF.Layout.pas` carry both sets of changes.
8. Deferred, non-blocking: the pre-existing quadratic accumulation in the `--project`
   `ScopeSet` block; the IDE's stale `DbPathTemplate` is never migrated; `<projname>` is
   guessed from the directory name in two plugin resolvers.

## Gotchas that will bite a cold start

* **The default own-root is the PROJECT FILE'S FOLDER.** It is only correct when the
  `.dproj` sits at the root of the code it owns. `drag-lint`'s own project file is at
  `src\cli`, so its default scope was **3 files, with the other 94 units of the engine
  counted as third-party**. Nine of 27 sections were affected. All now have declarations.
  **A `.dproj` in a subdirectory always needs one** -- and the skip report is what tells
  you ("94 file(s) outside the project's own roots skipped").
* **There are TWO manifests and BOTH are read at runtime.** The 32-bit IDE loads the
  win32 BPL, which resolves its manifest beside itself; the CLI reads win64. Desynced,
  they resolve different scopes and **neither errors**. `run_manifest_parity.ps1` enforces
  byte-identity; `migrate-dbs` now mirrors the pair.
* **Long-running work must be launched with PowerShell `Start-Process`.** A subagent's
  background processes are killed when its turn ends, and a `nohup` child inside a
  background bash job dies when that job's command finishes. Two battery runs were lost
  to this before the pattern was pinned down.
* **stdout is block-buffered when redirected; stderr is not.** Use `--json` and read
  stderr to see the scan/skip banner immediately instead of waiting for process exit.
* **A frozen I/O counter is not proof of a hang** -- check CPU time too. The ORM3 lint sat
  with flat `WriteTransferCount` for hours while pegged at 100% of one core.
* **Deploy before measuring.** `third_party\dll-win64\drag-lint.exe` is the copy with the
  manifest and tree-sitter DLLs beside it; `index --all` resolves its manifest relative to
  **the exe's own directory**.
* **`git add -A docs` will sweep in ~32 untracked INBOX notes.** They are deliberately
  untracked. Stage explicitly.
* The Write tool emits LF; every `.pas` and `.md` here is strict 7-bit ASCII + CRLF.
  Byte-check after writing.

## Method notes worth keeping

Three regressions this session were found by **running the binary against shapes the
fixtures did not cover**, never by reading a diff: a 2-argument `IfThen` silently dropped
by a narrowed matcher, a UTF-8 BOM written into the manifest, and the scope collapse
above. When a change narrows a matcher, probe the shape space it no longer reaches.

Of YADF's original 70 warnings, **28 were drag-lint's own false positives** and 24 more
were the autodoc defect. Only ~17 were real code debt. Sampling a category before
believing its count remains the highest-value habit here.
