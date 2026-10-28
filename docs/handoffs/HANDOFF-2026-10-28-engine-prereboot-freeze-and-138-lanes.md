# HANDOFF 2026-10-28 (16:15, pre-reboot) -- ENGINE: 1.37 freeze pending + 1.38 HPS lanes

Supersedes `HANDOFF-2026-10-28-engine-1370-combined-known-issues-wave.md` (still valid background).
**Source of truth: the ledger `C:\TEMP\claude\lanes\gaps\LEDGER.md`** (entries 10:55-16:30; stamps between
13:20 and 17:40 were ~3 h ahead of the PC clock, from 14:30 on they are real).

## Owner rulings in force (2026-10-28)
* HPS = highly parallel subagents, always (memory feedback_hps_highly_parallel_subagents). Sonnet for designed
  lanes, haiku mechanical, session model for design. No sleep-5 loops; one waiter per file; 10-20 min polls.
* 1.37.0 = the re-parse build (ONE re-parse). PREPARE it as a release (bump, build, pack, staged) but DO NOT
  publish; publish 1.37 only if weekly tokens hit 98% with 1.38 far; discard 1.37 when 1.38.0 ships.
* 1.38.0 = the PUBLISHED release, after the owner's IDE test; as few known issues as possible.
* Downgrade fixers (D1-D6) -> 1.38.1; 1.38 ships only dg-d0 surface (--target-compiler, silencing, docs/menu).
* ORM3 = Win64 only; libraryResolve ON for ORM3 CLIENT + SERVER in the re-parse; libraries first.
* LSP: per-file project + platform DBs; marked DB -> background re-index + notice (LSP lanes built it).
* Enum rules ON + one type-level dl:ok; A2 dead-store comment stays own-line (review later); CONVERTER
  order gate refuses + dependency graph (CONVERTER's C8CHAIN); D2 type rename = ENGINE cv-migtype.
* 4-hourly owner status report: the cron was session-only -> RECREATE it (CronCreate "13 */4 * * *").

## Freeze (FREEZE-FINAL, first job after the reboot)
gaps/ext 694e0360 (= E1-E5 + E1b + xj-7 + ki-exta, baseline 7dd7877f..ab73), engine-freeze\ + FINGERPRINT
built from it, gaps/stage3 322d14d6 = stage2 b401aade + ext (no conflicts, guards green).
STILL TO FOLD into gaps/ext: gaps/ext-plat 843a7fc8 (Win32/Win64 defines EXACT vs dcc32/dcc64 -- Win64 now
has CPUX64; 8 other platforms UNVERIFIED), gaps/ext-dirword (WIP at reboot; directive words like `Platform`
as identifiers -- resume from C:\TEMP\claude\lanes\gaps\agent-ext-dirword\STATE.md with a session-model
implementer in its worktree). Then ONE baseline recompute, rebuild engine-freeze + FINGERPRINT, merge gaps/ext
into stage3, plus LSP perf fix 27984767 (ResolveLibraryDb, lint setup 22.9 -> 2.0 s) into stage3.
Then: set libraryResolve true for ORM3 sections in the drag-lint.json the re-parse uses; library pre-parse
Win32+Win64 FIRST, then projects with explicit --platform Win64 (plan library-first s.4 witnesses).
NEVER `index <dir> --db <real>`; real DBs only via index --project/--all.

## 1.38 branches READY (merge into stage3 after the freeze; INT2 order in the plans)
XERJ: xj-1 0699a9df, xj-3 caea086a, xj-4 a84db133, xj-5 b14be602, xj-6 0962ce42, xj-8 7c086446.
KI: ki-help 952d80b4, ki-rules 9d4930c1, ki-verify 585d7a3d, ki-clippy1 0c43708b, ki-clippy2, ki-outenc
e35a079c (behaviour change: ANSI reports -> \uXXXX), ki-sqlfts d6a9d8b1, ki-purity 253f5971 (resolver bump at
INT), ki-hyg 59313e3f (partial), ki-docscheck 256625a9, ki-fp 6ec32b41, ki-d7 6593fbef, ki-d6 67bac8c3.
Other: dec13 0c5b2c7d, dec15 cb5f3e4a, lf-ready 749165a8, lf-marker cb98fe76 (take lf-ready's LibraryReady.pas),
lf-order 416580e2, gaps/ilc2 dc7e5716, gaps/a7 cbcc87b8 (merge LAST per old rule).
LSP (merge order): CLIENT 6e30cd5c -> CTXFILE 6bef79fa -> SETUP 52449565 -> GUARDS fix/lsp-guards-main
(+IFCONST 00be8321) -> CORE fix/lsp-context 97b17c4a; then switch CORE's marker key to
LIBRARY_RESOLVE_STATE_META_KEY.
WIP at reboot (resume from each agent-<lane>\STATE.md, fresh implementer inside the worktree):
enumrules (session), dg-d0 (session; surface only), cv-migtype (session), ext-dirword (PRE-FREEZE).
QUEUED: RB-5 3 lanes (docs\superpowers\plans\2026-10-28-rb5-interface-dispatch-hps-plan.md), lf-docs (haiku),
plugin writer for the central settings folder (DragLintLocalDataDir from CTXFILE), D5 old-library experiment
(owner copies Delphi 5 Source\ from the VM), CONVERTER follow-ups (GUI driver waits after libdesc).
Plans (untracked, commit at INT2): docs\superpowers\plans\2026-10-28-{known-issues-137, xerj-features-137,
rb5-interface-dispatch-hps, two-way-modernize-downgrade, library-first-resolve}-plan.md.

## INT2 owed (beyond the plans' lists)
run_lint_tests full (several lanes could not finish it under load), lf-ready's two tests, flag_verb_map +--rule
(fails on base; decide), encoding guard stray C0 byte, featuregen Help.FrozenBannerPreserved, registry
check B needs plugin index, `featuregen verify --id project-context --by LSP` (re-verify after merge), docs
triage waivers to CHARTS/LSP, Core.Model.pas:1107 facts block, xj-5 `since` -> 1.38 heading.

## Main tree
main 97a99bc4 pushed by owner (+ conv/dlggap 9269c588). stash@{0} = lane leaks (DEC-13 + ki-clippy1 lines;
content on their branches) -> verify + drop after reboot. stash@{1} = owner's P3 (keep). Untracked leaks:
src\tools\featuregen\FeatureGen.DocsCheck.pas (ki-docscheck copy), tests\autofix|autotest 6 files (leak #3)
-> diff vs branches, then [IO.File]::Delete with absolute paths. RuleCatalog.pas deletion is not ours.
18 agent worktrees kept for owner review (audit csv in the old session scratchpad); xj-5a..d worktrees left.

## Next action after the reboot
1. Recreate the status cron. 2. Collect the 4 WIP lanes' STATE.md, re-dispatch (ext-dirword first).
3. FREEZE-FINAL when ext-dirword is green -> re-parse. 4. Start RB-5 + lf-docs + plugin writer lanes and INT2
on stage3 in parallel with the re-parse. 5. Prepare (not publish) 1.37.0.
