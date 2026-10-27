# HANDOFF 2026-10-27 -- converter: CHAIN-1 T1-T5 built (T6 next); D2 split + drv2b HELD for ENGINE re-parse

Session convrules-editor-31. Supersedes HANDOFF-2026-10-26-converter-wave-closed-chain1-next.md.

## Status
* Merged to main and PUSHED (main 2cfbca29 and earlier): namedrop (name-drop workaround removed),
  drv3 (DRV-3 driver fixes), n13 (N13-1 BookPlaces split + N4-1 mixed-raise GUI case), opencounts
  (File > Open status shows "Loaded <book> (<enc>): N line(s), N rule(s)" again -- owner asked),
  drvfix (DRV-1/4/5 + DRV-2 partial; new tests\gui\gui-lock.ps1 with heartbeat), CHAIN-1 spec+plan,
  D2 plan, owner GO commit (2cfbca29: every recommended answer to CHAIN-1 Q1-Q8 and D2 Q1-Q7 accepted).
* Merged main verified by drv2b: 2960/0/20 no engine, 3080/0/0 on the 1.35.1 pin, glyph-link 23/0.
* **CHAIN-1** on branch `conv/chain1-impl` = e6d75b2e (T1 86ab5c56, T2 c980f89c, T3 ee57bbec,
  T5 47e2a19d, T4 e6d75b2e). Model tests 3042/0/20 no engine. Worktree with it checked out:
  `C:\Projects\Delphi-RAG-lint-wt\conv-ch-t1` (T4 worktree conv-ch-t4 = same commit).
  GUI driver `tests\gui\drive-rule-chains.ps1` (+ `-ProofNoChain`) written, NEVER RUN.
* **D2 split** on `conv/d2-split` (7ae71edc fixture tests\autotest\fixtures\bdesplit, aa88f72c new
  convrules\DataDB-to-FireDAC.rules, 29d64c46 BDE book trimmed, 194a6466 tests + guard
  tests\autotest\run_convert_book_split.ps1). Two-book apply == one-book apply (dfm byte-identical);
  Q3 measured: `#remove DFM: Origin` copied into Book-2. Model 2966/0/20, 3086/0/0 on pin.
* **drv2b** on `conv/drv2b` (2d0edbdb: drive-convert-tab instrumented). DRV-2b hypothesis: product race
  -- `LostClickTimerFire` (ConvRules.MainForm.pas:6742) vs `TConvertTab.AddSources`
  (ConvRules.ConvertTab.pas:944) overwriting the "Convert was NOT started" notice with its final
  SetStatus. Not proven; convert-tab fails 1-2 checks per run incl. run 1.
* ENGINE deployed 1.36.0-alpha to dll-win64 (main bf29f79b) and is running a FULL RE-PARSE of
  library-Win32/Win64.sqlite + every project DB (hours). ENGINE (delphi-rag-lint-65) will message
  "re-parse done". ENGINE reply sent: docs\INBOX-REPLY-chain1.md (untracked, E1-E4).

## Resume point
1. Wait for ENGINE "re-parse done" (ask delphi-rag-lint-65 if unsure). Then RE-PIN 1.36.0 per the
   editor CLAUDE.md (copy dll-win64 -> third_party\engine-pinned\1.36.0-alpha-<stamp>\, own SHA256,
   verify info/rules/query; tell the engine sessions before + after). `check-engine-drift.ps1`.
2. Then in parallel (lanes, fresh worktrees or the existing ones):
   - CHAIN-1 T6 (session model): plan Task 6 -- build, model runs both, run drive-rule-chains.ps1
     (normal + -ProofNoChain), drive-validate-scope, drive-save-encoding; fill the "TBD" count in
     src\tools\convrules-editor\CLAUDE.md; whole-branch lint (merge-base..HEAD) + review against
     spec 5.4/5.5; check T1-T4 deviations (listed below). Then merge conv/chain1-impl to main + push.
   - D2 resume (sonnet): run run_convert_book_split.ps1 (A/B/C + positive controls), the six engine
     autotests naming the book, lint BlockFile.pas; then merge conv/d2-split + push. Then follow-ups:
     Q4b re-home (step 6), Q6 "Book-2 before BDE book" ValidateScope warning (after CHAIN-1 merges),
     plan step 7 docs (convrules-dsl.md, backlog D2, wiki).
   - drv2b resume (opus): batch convert-tab runs until one fails, read the status trail, fix in a pure
     unit with a failing model test first, 3 consecutive green; merge + push.
   NOTE: dry runs/drivers re-run on the NEW pin; baselines will move -- record fresh ones.

## CHAIN-1 deviations T6 must review
* T1: cycle step walks from every unreported winner; chain Key omits last To when it loops back;
  `chains.text.offer` -> `.offer.all` / `.offer.asked`; added `chains.text.mark.unit.use`.
* T2: casts are `: Cast` in fixtures; ApplyChainMerge uses ABook.ParseLine; a later-stage block running
  to end of book keeps a trailing #migrate (a real file-scope trailer would be treated as that stage's).
* T3: SplitStatusText "then A, then B"; loose Stages list every #convert header at stage 1.
* T4: unit-conflict status also ends with the chain text; appending to an existing stage book drops the
  new #depth line (noted in wiki); driver check 19 tests dirtiness via File > New; after a Merge the
  last stage's old chain mark stays until re-validated (medium confidence -- likely a bug to fix).
* T5: featuregen surface is `exe:Name|menu`; summary max 160 chars. Registry guard FAILS on another
  team's entry `setup-installer` (questions[1].command quotes 'drag-lint > Uninstall') -- tell its owner.

## Not done yet (backlog: docs\CONVERTER-BACKLOG.md)
* `RuleLinesOnly` still splits on LF only (other callers would hit N13-1's bug).
* `#migrate TDBScreenCursors` typo (never matches; left as is, owner not asked to fix).
* namedrop: no capability gate -- an engine older than 1.35.1 silently finds no inherited code uses.
* INBOX note docs\INBOX-2026-10-05-converter-to-engine-local-read-unresolved.md needs a line
  "ask 2 verified cross-unit" (namedrop).
* Close backlog lines for N13-1, N4-1, DRV-1/4/5, opencounts in CONVERTER-BACKLOG.md.
* Cleanup after merges: worktrees under C:\Projects\Delphi-RAG-lint-wt\conv-* and scratch
  C:\TEMP\claude\lanes\1027conv\agent-* (C: is short of space; owner asked www-5b to audit).

## Gotchas
* Owner rule (memory feedback_merge_and_push_finished_lanes): merge each green lane to main and push
  promptly; FYI peers whose local-main commits ride along (LSP lsp-4e merges to main often).
* Lanes do not survive /clear: all lanes are FINISHED at this handoff (none running).
* Ledger copy (TEMP may be cleaned): C:\TEMP\claude\lanes\1027conv\LEDGER.md -- this file holds its content.
* RESUME.md carries other teams' uncommitted lines: stage only your own line (git apply --cached).
* docs\superpowers\ is gitignored; this stream force-adds specs/plans (owner: commit all work).
* GUI drivers: use tests\gui\gui-lock.ps1 (heartbeat) -- a clipboard clash showed lanes overlapping.
