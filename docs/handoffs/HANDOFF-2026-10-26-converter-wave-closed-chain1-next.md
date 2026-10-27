# HANDOFF 2026-10-26 (late night) -- converter: ready wave closed + pushed; CHAIN-1 / D2 split next

Session convrules-editor-31 (resumed). Supersedes HANDOFF-2026-10-26-converter-ready-wave-next.md.

## Status
* Ready wave DONE and merged on main: W0 re-pin, HLP, N13, N2, N4, DRV, plus docs 4577a597. Details and
  follow-ups are in `docs\CONVERTER-BACKLOG.md`, block "2026-10-26 (night) ready-wave CLOSED".
* The owner said "push main": pushed 1b7a70d3..7c7746b4 (81 commits). Backlog commit 5aa82e06 is
  local and unpushed (1 ahead).
* Pin is `third_party\engine-pinned\1.35.1-alpha-20261026-134311` (SHA256 92E4655A...). Its
  ConvRulesEditor.exe is STALE: stage a fresh build beside a COPY of the pin.
* Baselines on main: 2950/0/20 without the engine, 3068/0/0 on the pin.
* Worktrees still present: conv-base and conv-drv (DRV is merged, so conv-drv can be removed). Scratch
  still present: agent-base, agent-drv, agent-final.

## Owner inputs (2026-10-26, this session)
* **D2:** the owner prefers SPLITTING BDE-to-FireDAC.rules into a BDE book plus a "Book-2" for the
  rules that are not BDE-related. Backlog entry D2 -> SPLIT.
* **CHAIN-1 (new):** for A->B plus B->C in one book, warn and offer either one A->C rule or a split
  into separate books run one after the other. ENGINE (delphi-rag-lint-65) was asked whether
  convert-apply works in one pass or chains (types, unit swaps, #link/#migrate). The answer should
  arrive as a `docs\INBOX-*engine-to-converter*` note. The DSL doc does not say.

## Resume point
1. Run `check-engine-drift.ps1` and read any new INBOX note (the CHAIN-1 answer).
2. Present the next wave to the owner for a go, with these candidates:
   - CHAIN-1: design after ENGINE's answer; a pure `RuleChains` unit plus ValidateScope on Save.
   - D2 split: classify the 43 book-wide `#migrate` lines and the blocks as BDE or not. The BDE book
     keeps its book-wide lines above the first header.
   - Name-drop workaround removal (READY).
   - DRV-1..5, N4-1, N13-1.

## Gotchas
* RESUME.md also carries uncommitted lines from other teams (lsp/engine). Commit it only with a
  hunk-level stage, or leave it to its owners.
* GUI drivers run only under the exclusive `C:\TEMP\claude\lanes\gui.lock` (CreateNew). DRV-4: the
  lock has no heartbeat yet.
* save-encoding and convert-tab are flaky (DRV-1/2): rerun before calling a result red.
