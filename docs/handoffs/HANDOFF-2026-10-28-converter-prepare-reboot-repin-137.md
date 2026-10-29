# HANDOFF 2026-10-28 -- converter: PREPARE-REBOOT; re-pin 1.37.0 after ENGINE's re-parse

Session convrules-editor-31 (after the 12:30 /clear). Supersedes
HANDOFF-2026-10-28-converter-dlggap-failures-smoketest.md (all four of its open items are handled or moved here).

## Status
* conv/dlggap (gateleak + dlggap + gui-lock token) READY -> MERGED by ENGINE 9269c588; owner pushed main 97a99bc4.
  A/B vs a main 84f17966 build proved the battery failures pre-exist on main (log
  C:\TEMP\claude\lanes\1027conv\agent-mainab\ab.txt) -> backlog DRVLIB.
* Smoke test: Converter group of docs\SMOKE-TEST-1.37.0.html rewritten (16 steps, real menu paths). ENGINE's
  file, uncommitted; ENGINE commits it.
* Owner rulings 2026-10-28 (D2 #migrate, D5 inherited .dfm, Q2 old platform, Q5 strict ancestor-first) and
  the ENGINE INBOX (Q1 type rename MISSING -> ENGINE lane cv-migtype; Q4 inherited retype SUPPORTED) are
  recorded in docs\CONVERTER-BACKLOG.md "State 2026-10-28" (uncommitted -- commit it:
  `git commit -m "docs(converter): backlog 2026-10-28" -- docs/CONVERTER-BACKLOG.md`).
* CPU incident: 100% CPU came from sessions' sleep-5 wait-loops (bash/grep/sleep spawns), not the start script.
  44+12 stale loops stopped; ENGINE pruned its own. Start scripts fixed for after the reboot:
  E:\OneDrive\Documents\StartClaude\StartClaude-{DL,gmail}.ps1 (ELECTRON_NO_ATTACH_CONSOLE=1) + .cmd hidden
  launchers. Untested live -- test after the reboot (double-click .cmd, no console stays).
* No background jobs or lanes of mine are running.

## Resume point (in order)
1. After the reboot: check the new .cmd launchers worked (owner). Run `.\check-engine-drift.ps1` (exit 1 expected).
2. WAIT for ENGINE "re-parse done" (1.37.0). Then re-pin per src\tools\convrules-editor\CLAUDE.md (copy dll-win64
   to third_party\engine-pinned\1.37.0-<stamp>\, own SHA256, verify info/rules/query), model tests both modes,
   one battery on an IDLE machine (haiku), IDE-test steps -> ENGINE, PushNotification owner.
3. Editor CLAUDE.md counts (model + GUI driver list: file-menu 23 + dlggap, rule-chains 24, startup-responsive 12,
   convert-tab 34) -- re-measure on the 1.37.0 pin rather than copying.
4. Then backlog (docs\CONVERTER-BACKLOG.md "State 2026-10-28"): C8CHAIN (owner Q5, M), DRVLIB (M), DOCSCHECK-C3 (S),
   MIGTGT / ENUMMAP (need ENGINE cv-migtype + a D5 library index; owner must copy D5 Source\ here -- tell ENGINE
   the path).

## Gotchas
* Worktree C:\Projects\Delphi-RAG-lint-wt\conv-mainab (detached 84f17966) is a scratch A/B build: remove it with
  `git worktree remove` when done (no-approval delete via [IO.Directory]::Delete is not needed for that).
* Polling: no sleep-5 loops; one waiter per file; 10-20 min polls (owner + ENGINE, 2026-10-28). Subagent briefs too.
* JobLayout.pas is outside Micronite2027's closure; DMTEST (C:\Projects\DB\ORM3\CLIENT\DM) holds the inherited pairs.
* Pending owner question: a hook that refuses wait-loops polling faster than 1/min (offered, not answered).
