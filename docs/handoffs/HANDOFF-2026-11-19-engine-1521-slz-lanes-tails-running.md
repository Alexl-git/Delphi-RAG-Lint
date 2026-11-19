# HANDOFF 2026-11-19 13:00 -- ENGINE: 1.52.1 started (self-LoopZero lanes + tails)

Supersedes HANDOFF-2026-11-19-engine-152-released-reparse-running.md (that work is DONE).
Ledger (source of truth): `C:\TEMP\claude\lanes\v152\LEDGER.md` (tail). 1.52.1 lanes live under
`C:\TEMP\claude\lanes\v1521\<lane>\` (worktree `wt\`, REPORT.md, private engine).

## Done this session
- REPARSE DONE 10:12: both libraries FRESH, total 2h52m (1.51.1 in place 3h55m); Win32 2h32m pe 15,
  Win64 2h38m pe 37, projects 37/37 13m01s pe 0, catchup 1m. Owner page Part 6 + results 6.1/6.2 filled.
  `.before-152` libraries DELETED (owner OK).
- DL project DB up to date (455 files pe 0). Self-LoopZero r0: 6219 findings / 364 files
  (`C:\TEMP\claude\lanes\v152\SELFLZ\r0.json`); lint-all took 41 min (perf note for IDXPERF).
- Triage A-D (`SELFLZ\triage-B/C/D.md`; A only as group-A.tsv + lane reports).
- Stash "agent:DEPLOY152 -- overlap" dropped (whitespace-only).
- Website (www-11): 1.52 site LIVE 08:44, committed on local main unpushed (9215e822f + site commit).
  www reported an overnight revert of uncommitted WWW tracked files (ARTICLE-RULES additions + YADF help
  edits lost); no ENGINE checkout found -- told owner.

## 1.52.1 lanes (all off main 9215e822f)
| lane | branch / tip | state |
|---|---|---|
| SLZ-SRC | lane/v1521-slz-src 6f3cbc266 | MERGE-READY. Extractor-surface edits (Lattices:1437 out->var, Plan.pas OutDir, Delphi13 Stem, Indexer:832 arm...) DEFERRED to `slz-SRC\deferred-extractor-surface.patch` -> apply in the 1.52.1 extractor bump if there is one (INCR18 S4 resolver bump?). |
| SLZ-RULE2 | lane/v1521-slz-rule2 b60ce6e20 | MERGE-READY (uba 25->7, string-index-base 21->0, idx 442->389; remove now-unused dl:ok Core.ControlChannel.pas:1321). |
| SLZ-RULE1 | lane/v1521-slz-rule1 2c3cb5705 | REWORK per owner: (Q1) env-var taint source = PER-PROJECT setting: key in `.drag-lint.json` (default ON = env untrusted), DL repo opts out; (Q2) unused-unit-in-uses: revert init-section skip, use an ALLOW-LIST of registration units (FireDAC Stan/Phys/UI, driver links...). Keep its bare-except / unprotected-free / gettickcount commits. |
| TAILS-TEST | lane/v1521-tails-test | RUNNING (sonnet): PS5.1 vscode contract, 2 flaky runners, 9 vacuous runners + positive controls. |
| TAILS-EXT | lane/v1521-tails-ext | RUNNING: comment-span trailing CR repro, ToolsAPI library root. |

Lanes do NOT survive /clear: read each lane's REPORT.md + ledger line; if missing, inspect the branch and
run a finisher inside the existing worktree.

## Owner rulings 2026-11-19 (in ledger)
- Q1 per-project settings: owner wants a per-project settings STORE + MENU (IDE + VS Code). 1.52.1 = config
  key only; store + menu = 1.53 feature (spec-loop first) unless owner pulls it in.
- Q2 allow-list now; backlog 1.53: "init-dependency facts" in the library index (unit X init registers
  into A/B -> needed iff A/B used) -- extractor change.
- Q3 drop the 29 empty FRAME scaffold units (Fix.V151.*, Fix.V152.*, *.Support, Fix.Security, Fix.Typed)
  from drag-lint.dpr/.dproj in 1.52.1.
- All 6 OPEN-UNSCHEDULED backlog rows go into 1.52.1 (2 tail lanes; YADF ReviewMarker mirror: copied,
  needs YADF commit + rerun run_reviewmarker_yadf_mirror at INT).

## Next actions (in order)
1. Write the 1.52.1 plan (`C:\TEMP\claude\lanes\v1521\PLAN.md`) from BACKLOG-AFTER-152.md OPEN-1.52.1 rows +
   the above; deadline merged + battery green Fri 11-20 14:00, owner test 14:00-16:00, re-parse Fri 15:30 -> Sat.
2. Create lane/v1521-int off main; merge SLZ-SRC + SLZ-RULE2; at integration CHECK why except-handler-order
   6->0 and parameter-type-too-wide 14->0 in RULE1's re-measure (rule silently not running?).
3. Re-dispatch SLZ-RULE1 rework (finisher in its worktree). Dispatch: scaffold removal, INCR18 S3 merge +
   S4 finish, IDXPERF P1-P3, SHOPDEMO, NORETURN-SHOW, find-callees --name exit 2 check, query --text multi-line.
4. After merges: review-marker-unused sweep (75 -> ~211 after RULE1), then ~330 TP-keep dl:ok markers.
5. Status ticks: the recurring controller tick prompt still walks the finished 1.52 chain -- replace with a
   1.52.1 tick or stop it (owner offered the choice, no answer yet).

## Gotchas
- Agent `isolation: worktree` fails here (c:/C: casing) -> create worktrees by hand under the lane folder.
- Flow.Lattices / parser / preprocess / index / Core.Indexer edits are EXTRACTOR surface (guard fails) ->
  bump once at integration or defer.
- lint-all on DL takes ~40 min; lanes must use private engine + DB copies.
- Main checkout has many dirty files from other teams; commit only with pathspecs.
- MEMORY.md is over its size limit -- trim old ENGINE pointers into lessons_index.md.

## Update 13:05 (before owner's VS Code reload)
- OWNER RULINGS: per-project settings store + menu -> 1.53. INIT-DEPENDENCY FACTS -> 1.52.1 (owner: ONE rescan only,
  so every extractor change must be merged before the Fri 15:30 re-parse): spec first (spec-loop, session model),
  then lane; it rides the single 1.52.1 extractor bump with SRC deferred patch + INCR18 S4 resolver bump + grammar
  CR fix (if tree-sitter-delphi13 ships /[^\r\n]*/ in time). FIRST PRIORITY next session after the plan.
- TAILS-EXT DONE (no commits): comment CR = grammar defect (note TAILS-EXT\GRAMMAR-NOTE-line-comment-includes-cr.md;
  pass to the grammar repo); ToolsAPI unresolvable not reproducible -> close.
- TAILS-TEST: was RUNNING at reload; it dies with the reload -> inspect branch lane/v1521-tails-test + its worktree,
  finish inside the existing worktree.
- Controller tick: old 1.52 cron deleted; 1.52.1 tick cron e2ea5c5c created but it is session-only -> RECREATE
  after reload (13,53 * * * *; prompt in the ledger line of 13:05).
- Per-project options PART 2 added to C:\Projects\Delphi_IDE_OptionsPage_HOWTO.md (no Project Options page API).
- Owner is on other projects; tests the 1.52 page later; next owner touch-point Fri 14:00-16:00.