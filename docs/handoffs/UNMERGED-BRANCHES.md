<!-- dl:backlog status=open last-measured=2026-10-27 -->
# Unmerged branches -- standing tracker

Every local branch ahead of `main`, classified. Re-measure before acting:
`git for-each-ref refs/heads` + `git rev-list --count main..<b>` + `git cherry main <b>`
(`+` = patch not in main, `-` = already in main under another SHA).
Measured 2026-10-27 against main = origin/main = 0db24e3c (1.36.0 deployed = a6515adc).
Owner of the merge: ENGINE (release roll-up). LSP has nothing unmerged.

## 1. NEEDS A DECISION -- real work not in main

| Branch | Head | Work | State | Ask |
|---|---|---|---|---|
| worktree-agent-ae49d9f476c2d9426 | 909fc131 (2026-10-25) | docs(help): name --out/--json on the verbs that read them; flag-verb baseline 110/27 -> 103/24 (W6-flagmap, 20 files) | NOT in main. Main went another way (c52ab911 uniform flag aliases, `$BaselineCells = 108`). `git merge-tree` conflicts in features/entries/*.json + manifest.json | ENGINE: redo on top of main (re-run featuregen build --all, re-measure the baseline) or drop it with a reason |

## 2. ACTIVE LANES -- in flight, merged by their own controller

| Group | Branches | Owner | Note |
|---|---|---|---|
| Clippy wave | clippy/int (79926245, +38), clippy/l0..l12 | ENGINE | integration branch clippy/int collects the lanes |
| Gaps | gaps/int (8403576a, +48), gaps/a0, g0, k1, k2, taint, taint-t1, taint-t2 | ENGINE | gaps/int must be green before the release install; taint T0 carries extractor 1.26.0-alpha (re-parse) |
| CONVERTER lanes (started 2026-10-27) | conv/q6, conv/linkmerge, conv/startup, conv/gateleak, conv/inhrecap (worktrees Delphi-RAG-lint-wt\conv-<name>) | CONVERTER | ACTIVE -- read 0 ahead only because no commits yet. NEVER in a delete batch until CONVERTER reports them merged. (conv-base, detached at 287766c3: not CONVERTER's, owner unknown) |
| LSP fixes for the release | fix/help-out-json (MERGED 84bbd47c), fix/help-compare-out-root 8503841c (handed to ENGINE), fix/lsp-switch-release (MERGED 64f7b4dd), fix/help-compare-out-root (MERGED), fix/lsp-unowned-label ca91e559 (MERGED 9aa87e94), fix/lsp-clear-diags-on-close f719c702 + 6cc58823 guards #Requires 7 (handed to ENGINE 2026-10-27, after the release; worktree .claude\worktrees\lsp-cleardiag) | LSP -> ENGINE merges at INT | 909fc131's branch worktree-agent-ae49d9f4 becomes deletable once fix/help-out-json merges |

## 3. DONE -- already in main, branch only left behind (safe to delete after a look)

| Branch | Head | Why it is done |
|---|---|---|
| worktree-agent-a894c17432443ce85 | 29e9186d | cfg B-30/B4 function-result-not-set: patch-equivalent in main (`git cherry` = `-`) |
| worktree-agent-a97a7239db384f5fa | faa5e2ac | B-41/X-14 docs: patch-equivalent in main |
| worktree-agent-ab5fcea23bf1d0159 | 576e4abc | cycles A2 positive control q4: patch-equivalent in main |
| worktree-agent-ad1b2e68c0f021432 | 3201f18f | autodoc TSharedFacts / X-24: patch-equivalent in main |
| worktree-agent-ab395cfc4fa18f85e | 857d0750 | T-22 unit-not-in-library: landed as 3b434b08 |
| worktree-agent-a3b9d0e9925b84522 | 905cd428 | CYC-C C2/C4/C7: landed as 2550ba6d (+ b68d9a77) |
| worktree-agent-a5dd69f27b7607079 / acc26006502f247af / a08b3329d53564793 / a7205be6bd212ec86 / a6b5582308fdac22f | b624d322 / 294f78b0 / 078aacc0 / 094419e2 / 288912dd | X1/X2/X4/X5/X6 lane extractor bumps: dropped ON PURPOSE ("lane bump dropped"), replaced by the one batch bump 8ccbd06f |
| verify/1351-cycc | a139973f | merge-only commit, nothing unique (`git cherry` empty); checked out in Delphi-RAG-lint-wt\mainbuild |
| fix/lsp-* (10 branches), fix/plugin-library-timeout, feat/index-active-config | -- | merged, shipped in 1.36.0 |

## 4. PARKED ON PURPOSE

| Branch | Head | Note |
|---|---|---|
| (none) | | archive/feat-converter-editor was triaged by CONVERTER 2026-10-27 -> RETIRE (see section 5) |

## 5. FULLY MERGED, deletable (owner runs deletes; agents' `branch -d` is refused by the guard)

| Branch | Owner | Note |
|---|---|---|
| feat/www-base (6bba1c98), fix/www-minors (800dbabe) | WEBSITE | 0 commits not on main; in Delphi-RAG-lint and DL-www |
| ~~conv/chain1-impl, conv/ch-t1..t5, conv/d2-split, conv/drv2b, conv/a1270, conv/fgcheckc~~ | CONVERTER | DELETED by owner 2026-10-27 (branches + their Delphi-RAG-lint-wt\conv-* worktrees) |
| ~~archive/feat-converter-editor~~ (f3f694d9) | CONVERTER | DELETED by owner 2026-10-27; its INBOX replies live on in tag archive/converter-editor-2026-09-15 |

Housekeeping (owner call, needs approval -- `branch -D`): ~80 `worktree-agent-*` worktrees under
`.claude\worktrees\`, ~35 of them `locked`; most have nothing ahead of main.
