<!-- dl:backlog status=open last-measured=2026-11-09 -->
# Unmerged branches -- standing tracker

Every local branch not an ancestor of `main`, classified. Re-measure before acting:
`git branch --no-merged main` + `git rev-list --count main..<b>` + `git cherry main <b>`
(`+` = patch not in main, `-` = already in main under another SHA).
Measured 2026-11-09 (wave 149 lane DOC; refreshed by 150 DOC2 below) against main = bdbf7f91 (1.48.0-alpha: the 148 integration 8a4ccf2d3 + the plugin BPL build). 507 local branches:
466 are merged into main (deletable, plain `git branch -d`), 41 are not (the in-flight lane/149-* branches among them). Owner of the merge: ENGINE. LSP has nothing unmerged.
Wave-150 refresh (lane DOC2, 2026-11-09, main = f8d66a21f = the 149 integration, pushed): see sections 5-7. ONE script does every delete: `C:\TEMP\claude\lanes\150\DOC2\staged\OWNER-DELETES-150.ps1` (dry run, -Go needed; -LaneWorktrees also removes the 149/150 lane worktrees first; it folds in RQ's pr-9 and the 149 DOC list). The older scripts stay valid.
Delete candidates (before 150): the merged ones are covered by `C:\TEMP\claude\lanes\147\H1\OWNER-DELETES.ps1` (generic `branch --merged main`, dry run, -Go needed);
the unmerged DONE set of section 3 (needs a force delete, git cannot see the equivalence) is in `C:\TEMP\claude\lanes\149\DOC\staged\OWNER-DELETES-149-DOC.ps1` (dry run, -Go needed).

## 0. lane/148-* (33 branches): merged vs not

30 of 33 are in main via the 148 integration (8a4ccf2d3): AF BV CV CY D1P DC DX G7 GB GD GX HK HP HP2 HS INT IX LS MF OM RF RN RO T2 T3 TN UP VS XP3 (G7 carries GX; both are the grammar-master stack, released as grammar v1.4.5 / v1.4.6).
Not in main, by design:

| Branch | Head | State | Where it goes |
|---|---|---|---|
| lane/148-HP2B | 64e4aae0 | Part B 145 -> 14 s | in `149 CY-BASE` 883c48a46 (CYA/CYB base); reaches main with the 149 integration |
| lane/148-PB | dad64ba1 | PurityStage shallow-file `?` (146 g1) + NarrowToNearest renamed-param override (146 b4) | carried by RB2 (seed merge); reaches main with the 149 integration |
| lane/148-XF | e42fa95c | FPC grammar spec (sibling layout `fpc/`) | NOT-FOR-MERGE; the grammar-fork decision is owner-side (FPC/Lazarus ruling) |

## 1. REAL WORK NOT IN MAIN -- needs a decision or a lane

| Branch | Head | Work | State | Ask / lane |
|---|---|---|---|---|
| lane/146-b6 | 36f26086 | docs+lint(146 b6): proof results and NOT-FOR-MERGE verdict (is-never-true) | 6 commits, verdict recorded in its spec | NOT-FOR-MERGE; keep as evidence (148/T3 measured the rule on real DBs) |
| lane/146-x2 | 01085ace | E-DCU-INDEX design + read-only prototype verb | NOT-FOR-MERGE; superseded by owner ruling 2026-11-08: NO .dcu parsing (lane HP uses .hpp + dcc map) | delete candidate after the owner's OK |
| gaps/ext-dirword | f065a904 | WIP: Tree-sitter directive-word names (callconv names) | STRUCK from the 149 bump list (owner 2026-11-08): fixed in grammar v1.4.0 (12088ad) | delete candidate after the owner's OK |
| lane/143-cyc4 | ce7b27be | docs(cycles): cyc4 registry output regenerated | registry output, stale (featuregen build --all regenerates it) | delete candidate (generated output) |
| lane/144-enummap | 64caa16a | convrules: D5 -> Win64 enum map evidence book (ENUMMAP) | CONVERTER's evidence book | CONVERTER decides |
| charts/docs-no-powershell | 6048ee46 | docs(handoff): CHARTS docs merged after 1.43 | handoff text only | CHARTS decides |

## 2. IN THE 147 / 148 INTEGRATIONS (reached main; do not treat as open)

lane/146-g3, lane/146-r4, lane/146-x1, lane/146-x3, lane/146-x4, lane/146-x5 and every lane/147-* are ancestors of main (147 integration, then 148 INT 8a4ccf2d3).
Re-measure with `git rev-list --count main..<b>` = 0 before deleting.

## 3. DONE -- in main under another SHA, or absorbed; safe to delete (needs `branch -D`: git cannot see the equivalence)

| Branch | Head | Why it is done |
|---|---|---|
| worktree-agent-ae49d9f476c2d9426 | 909fc131 | help-out-json (--out/--json on the verbs that read them): bdd0f847 says its help edits are already on main via alias folding; run_flag_verb_map PASS 43/43 on 1.46.0 (lane 148/HK). Lane DC's REDO row is moot unless the owner wants a per-entry diff |
| charts/ask-question-flag | d6f9d1be | `git cherry main` shows 0 `+` patches |
| verify/1351-cycc | a139973f | merge commit only, 0 `+` patches |
| worktree-agent-a97a7239db384f5fa | faa5e2ac | B-41/X-14 docs, 0 `+` patches |
| pr-1 pr-2 pr-4 pr-5 pr-6 pr-7 pr-8 pr-8b | 2026-10-16 | the 1.39 re-split landed each under a new SHA (same subject in main: 312f3f34 pr-1, ec918830 pr-2, 03917ac6 pr-4, 85bb854e pr-5, ba18f520 pr-6, 70390f7f pr-7, d72569e4 pr-8) |
| pr-3 | 39036a4f | re-split: d5860f6e (PR #3 part) + 87ee5e74 |
| pr-10 | 62d0628d | re-split: 3eff7cd3 (PR #10 throughput half re-split onto main) |
| pr-11 | ad47d8cf | re-split: 38c6473a (x11 per-section preprocessing) + def36f7c |
| pr-9 | b8b4c90d | resolver 1.13 PR: the 1.39 lanes re-did it (see the 1.39 handoff); OBSOLETE (149 RQ): both commits re-done on main (cli = 03917ac63; resolver 1.13 re-pinned 03c6078c0, now 1.22+); deletable with `git branch -D` (no patch-id match, so -d refuses) |

## 4. HOUSEKEEPING (owner call)

466 merged branches (several `worktree-agent-*`) are deletable with plain `git branch -d` (the 147 H1 OWNER-DELETES.ps1 dry run lists them); ~80 `worktree-agent-*` worktrees under `.claude\worktrees\`
(~35 locked) mostly hold nothing ahead of main. Removed since the last measurement: every conv/*, clippy/*, gaps/int and fix/* branch listed in the 2026-10-27 tracker.
Wave-149 lane branches: all 19 are ancestors of main now (section 5). Their worktrees (`C:\TEMP\claude\lanes\149\<lane>\wt`) and the wave-150 ones are the controller's to remove after the 150 re-parse; the gaps/ext-dirword WORKTREE (`C:\Projects\Delphi-RAG-lint-wt\ext-dirword`) blocks the delete of that branch until `git worktree remove` (OWNER-DELETES-150.ps1 step E).

## 5. lane/149-* (19 branches): all merged

Measured 2026-11-09 with `git merge-base --is-ancestor <b> main`: CYA CYB DF DOC EX1 EX2 GA GL GR HW IC INT LX MS PL RB1 RB2 RQ RT are ancestors of main (f8d66a21f); plain `git branch -d` works once the lane worktree is gone. Nothing from 149 is unmerged. (lane/148-HP2B and lane/148-PB, section 0, reached main inside the 149 integration.)

## 6. lane/150-* (wave 150): the integration set

All of CQ CY1 CY2 CY3 DF2 DQ EX3 GR2 HG INT LN LX2 PP PS RF RG RS1 RS2 SC W1 are ancestors of `lane/150-INT` (the integrator merged them; CY3 contains CY1's commits). Reaches main when the controller merges lane/150-INT. Still outside it at the time of writing (re-measure with `git merge-base --is-ancestor lane/150-<X> lane/150-INT`): CF (PARTIAL dd44e34ca), PF2 (PARTIAL 54bd311ef; item 1 merges only after the CLIENT identity finisher says IDENTICAL), MS-A (PARTIAL abdf9865f, measurement docs), SW, DOC2 (CHANGELOG-v1.49.md + this file; INT commits). `lane/150-GV` in THIS repo sits at the base: the graph work is the Graph repo's branch lane/150-GV (main-based), merged there by the controller; its exe SHA256 is in the 150 ledger.

Grammar repo (`C:\Projects\tree-sitter-delphi13`, owner merge to master + tag + npm): lane/149-GR (v1.4.7), lane/150-GR2 (v1.4.8, 4960c8d, local release commit), lane/150-PS (v1.4.9, 5ec1b35), lane/150-W1 (tsblank measurement; the scanner prototype was handed to GR2). tree-sitter-DFM: v1.2.0 (+ v1.2.1) master merge / tag.

## 7. NOT-FOR-MERGE (kept as evidence; do not merge, delete only on the owner's word)

lane/146-b6 (is-never-true verdict), lane/146-x2 (.dcu prototype, superseded by the 2026-11-08 ruling; delete candidate), lane/148-XF (FPC grammar spec), gaps/ext-dirword (struck, fixed in grammar v1.4.0; delete candidate after `git worktree remove`), lane/144-enummap (CONVERTER), charts/docs-no-powershell (CHARTS), the 36f26086 b6 twins and E-BIND-LIB-EFFECTS 0b617232 (parked by owner ruling), pr-9 (OBSOLETE, superseded by 03917ac63 + 03c6078c0; `git branch -D`, in OWNER-DELETES-150.ps1 step C).
