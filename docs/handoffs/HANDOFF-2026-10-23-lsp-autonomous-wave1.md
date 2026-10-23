# HANDOFF 2026-10-23 -- LSP stream, autonomous run, wave 1 in flight

Controller session: lsp-6f. Context checkpoint at ~76% (multi-day run). Resume COLD from this file.

## Authority
- Plan: `docs\superpowers\plans\2026-10-23-lsp-stream.md` (20 tasks, 4 lanes + audit lane, ETA ~6 days).
- **Ledger (source of truth): `.superpowers\sdd\2026-10-23-lsp\progress.md`**. It holds every ruling, the owner
  rulings, the ENGINE constraints, the registry queue, and the controller log at the bottom.
- Briefs/reports: `.superpowers\sdd\2026-10-23-lsp\briefs\task-<id>-brief.md` / `-report.md`.
  Wave-2 briefs are already extracted (A1 B1 B4 C1 C4 C3 B2). Extract the others with the awk loop in the ledger log.
- Autonomy: `~/.claude/autonomy/mode.json` key `lspRun`. The top-level slot belongs to CONVERTER (shared with ENGINE).
  NEVER change the top-level `phase`.

## Owner rulings (2026-10-23)
A7 deferred; D2 skipped; C1 opt-in default OFF + measured; land on LOCAL main; never push/deploy dll-win64;
max parallel subagents (CPU-capped: 3 builders + scripting lanes); **no approval-needing command mid-run**
(deletes, Stop-Process, reset/clean/checkout --/stash drop/worktree remove). Queue those for the END of day 3.
30-min wakeup cron (session-only). Recreate it in a fresh session: CronCreate "13,43 * * * *" with the
LSP wakeup prompt (read ledger + lspRun, nudge stalled lanes, dispatch the next ready task).
After the run: G0 = VS Code vs IDE DL-message parity (LSP\LSP-BACKLOG.md section G).

## Lane state at checkpoint
| lane | worktree | task | state |
|---|---|---|---|
| S | Delphi-RAG-lint-wt\lsp-server (lsp/server) | S0 | implementer running (session model), no commit at 15:30. Result -> briefs\task-S0-report.md |
| P | lsp-proxy (lsp/proxy) | P0 | DONE f582e862 (21/21). Session-model REVIEW running; verdict -> briefs\task-P0-review.md. Then fix loop or merge |
| Q | lsp-quality (lsp/quality) | D1 | COMPLETE + MERGED to main 7dc3b47f. **Docs-sync F3 regression fix running** (sonnet; merged main 36e20dbb into the lane). Report -> briefs\task-D1-docsync-report.md. Review it, merge, then TELL ENGINE (it reported the red). Next C1 needs S0 merged |

**Read the ledger tail first.** Ruling (late 2026-10-23): a task that adds a drag-lint.exe flag (P0: --merge-diagnostics,
--merge-budget-ms) gets its registry entry + `featuregen build --all` AT ITS MERGE, gated on ok from both teams, so that
docs-sync stays green on main. Run `tests\autotest\run_docs_sync_guard.ps1` before EVERY merge (`--progress` red is expected
until ENGINE's end-of-run deploy). ENGINE now asks before its own build --all; answer "ok" when no LSP build is in flight.
| audit | lsp-audit (lsp/audit) | C7 | COMPLETE + MERGED to main 19caa20e (lane retired; A6 re-run owed) |
| M | lsp-merge (lsp/merge) | C5 | COMPLETE + MERGED to main 547b5ab8; next A3 needs P0 merged |

A fresh session cannot message the old subagents. If a task has no completion line, read its report file and
`git log` in the worktree. If the work is committed and the report is complete, run the review. Otherwise
dispatch a fresh implementer with the brief + report (+ open findings from the ledger).

## Next actions
1. On each DONE: run `review-package` (skill scripts dir) BASE..HEAD in the worktree, then the task reviewer
   (sonnet for sonnet tasks; session model for S0/P0/A1/A3/B3/B5/C2), then the fix loop, then the ledger completion line.
2. Merge to local main in plan order (S0, P0, B1, ...). Then `git merge main` inside the dependent lanes, rebuild that lane,
   and announce each merge to delphi-rag-lint-5e + convrules-editor-2d.
3. After S0 merges: lane S -> B1, lane Q -> C1. After P0 merges: lane P -> A1, lane M -> A3.
4. A6 preconditions: re-run the C7 audit with the lane-P exe (the --merge-diagnostics control must PASS); featuregen build --all
   only after "ok" from BOTH other teams; never edit convert-apply/convert-scaffold entries.

## Owed / queued for end of day 3
- PLAN-lsp-toggle-switch.md step-4 status (untracked file; the controller edits it in the main tree).
- Worktree removal and branch deletion for the merged lanes (approval-gated).
