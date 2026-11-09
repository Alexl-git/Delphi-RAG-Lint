<!-- dl:backlog status=open last-measured=2026-11-09 -->
# Unmerged branches -- standing tracker

Every local branch not an ancestor of `main`, classified. Re-measure before acting:
`git branch --no-merged main` + `git rev-list --count main..<b>` + `git cherry main <b>`
(`+` = patch not in main, `-` = already in main under another SHA).
Measured 2026-11-09 (wave 149 lane DOC) against main = bdbf7f91 (1.48.0-alpha: the 148 integration 8a4ccf2d3 + the plugin BPL build). 507 local branches:
466 are merged into main (deletable, plain `git branch -d`), 41 are not (the in-flight lane/149-* branches among them). Owner of the merge: ENGINE. LSP has nothing unmerged.
Delete candidates: the merged ones are covered by `C:\TEMP\claude\lanes\147\H1\OWNER-DELETES.ps1` (generic `branch --merged main`, dry run, -Go needed);
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
Wave-149 lane branches (lane/149-*) are in flight; their worktrees are under `C:\TEMP\claude\lanes\149\<lane>\wt` and are the controller's to remove after the 149 integration.
