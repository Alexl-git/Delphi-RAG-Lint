<!-- dl:backlog status=open last-measured=2026-11-08 -->
# Unmerged branches -- standing tracker

Every local branch not an ancestor of `main`, classified. Re-measure before acting:
`git branch --no-merged main` + `git rev-list --count main..<b>` + `git cherry main <b>`
(`+` = patch not in main, `-` = already in main under another SHA).
Measured 2026-11-08 (wave 148 lane HK) against main = b036f2cb (1.46.0-alpha). 468 local branches: 415 are merged into main
(deletable, `git branch -d`), 53 are not. Owner of the merge: ENGINE. LSP has nothing unmerged.
The delete candidates are in `C:\TEMP\claude\lanes\148\HK\OWNER-DELETES-148.ps1` (dry run; -Go needed).

## 1. REAL WORK NOT IN MAIN -- needs a decision or a lane

| Branch | Head | Work | State | Ask / lane |
|---|---|---|---|---|
| lane/146-b6 | 36f26086 | docs+lint(146 b6): proof results and NOT-FOR-MERGE verdict (is-never-true) | 6 commits, verdict recorded in its spec | keep as evidence; 148/T3 measures the rule on real DBs |
| lane/146-x2 | 01085ace | E-DCU-INDEX design + read-only prototype verb (NOT-FOR-MERGE) | superseded by owner ruling 2026-11-08: NO .dcu parsing (lane HP uses .hpp + dcc map) | delete candidate after the owner's OK |
| gaps/ext-dirword | f065a904 | WIP: Tree-sitter directive-word names (callconv names) | PARKED by owner 2026-10-28; grammar v1.4.4 is now tagged | keep; revisit with the grammar fork |
| lane/143-cyc4 | ce7b27be | docs(cycles): cyc4 registry output regenerated | registry output, stale (featuregen build --all regenerates it) | delete candidate (generated output) |
| lane/144-enummap | 64caa16a | convrules: D5 -> Win64 enum map evidence book (ENUMMAP) | CONVERTER's evidence book | CONVERTER decides |
| charts/docs-no-powershell | 6048ee46 | docs(handoff): CHARTS docs merged after 1.43 | handoff text only | CHARTS decides |

## 2. IN LANE/147-INT (reach main with the 147 integration; do not delete)

lane/146-g3, lane/146-r4, lane/146-x1, lane/146-x3, lane/146-x4, lane/146-x5 (`git rev-list --count lane/147-int..<b>` = 0 for each),
and every lane/147-* (B1 B2 B4 B5 C1 D1 G2 G3P H1 K1 K2 K5 P1 PF PRE R3 R4F TL U1 X5P, base, int) and lane/148-* (GD HP VS and the lanes to come).

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
| pr-9 | b8b4c90d | resolver 1.13 PR: the 1.39 lanes re-did it (see the 1.39 handoff); no one-to-one SHA found -- UNVERIFIED, check `git diff main...pr-9 --stat` (60 files) before deleting |

## 4. HOUSEKEEPING (owner call)

415 merged branches (19 of them `worktree-agent-*`) are deletable with `git branch -d`; ~80 `worktree-agent-*` worktrees under `.claude\worktrees\`
(~35 locked) mostly hold nothing ahead of main. Removed since the last measurement: every conv/*, clippy/*, gaps/int and fix/* branch listed in the 2026-10-27 tracker.