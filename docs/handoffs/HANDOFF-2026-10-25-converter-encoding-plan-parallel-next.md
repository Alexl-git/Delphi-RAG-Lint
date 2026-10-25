# HANDOFF 2026-10-25 -- converter: text-encoding plan ready; next = parallel SDD execution

Session convrules-editor-31 (was -2d before the 10-25 restart). Supersedes
HANDOFF-2026-10-23-converter-autonomous-3day-wave3.md for the converter stream.

## Status (all on LOCAL main unless said; origin/main = 6511fe41, main is ~12 ahead incl. ENGINE)
* Converter backlog A-E done; FG-M + FG-N merged 8234fe33; FG-O/FG-P 411c1ca7; featuregen 245/0.
* Deep reviews (owner request) filed for ENGINE: docs\INBOX-2026-10-25-converter-to-engine-deep-review-dl.md
  (9 findings; ENGINE fixed F1/F2/F7/F8/F9 on main) and docs\INBOX-2026-10-25-converter-deep-review-editor.md
  (R1-R7 + test gaps, in docs\CONVERTER-BACKLOG.md). ENGINE made exit 6 a contract (675006b6).
* A4 #migrate: owner accepted all recommendations (D0 = B) -> starts after re-parse + re-pin.
* ENGINE re-parse (PID 50768, `index --all --jobs 1`) was STILL RUNNING; wait for ENGINE's
  "re-parse done" before any with-engine model test, GUI driver, conversion or re-pin.

## The work to resume: text encoding (R3 + owner's encoding ladder)
* Spec (approved): `docs\superpowers\specs\2026-10-25-converter-text-encoding-design.md` (section 9 = owner decisions D-A engine checks at write time, D-B UTF-16 books always with BOM; 8a = settled facts).
* Plan (approved for execution): `docs\superpowers\plans\2026-10-25-converter-text-encoding.md`
  (gitignored folder). Read "Parallel lanes" (line ~88) and the trailing "Controller decisions" section.
* Lanes: Task 1 (F, sonnet) first; then 2 (S, session model), 3 (C, sonnet), 4 (E, sonnet), 5 (D, sonnet) IN PARALLEL;
  6 (T, session) after 2+4+5; 7 (W, sonnet) after 2+3+6; 8 (R, session) last, only after "re-parse done".
  Each lane owns its files (table); tests split into tests\inc\Encoding<Lane>Tests.inc; only Task 1 edits the shared .dpr.
* ENGINE lane CONV-ENC accepted the contract as written (encoding_refused + --raise-encoding "<path>=utf8-bom" +
  .dfm #-codes + capability convert_encoding_guard); it starts after the 1.34.1 deploy + re-parse. Fixtures:
  E1' fires only for `ansi` files, "fits" = active ANSI code page round trip (plan, last section).

## Resume point -- exact next actions
1. **R2 FIRST** (owner-approved small change: capability probe = version check + ask-to-wait, engine answer wins,
   no cached failure). Worktree `C:\Projects\Delphi-RAG-lint-wt\conv-r2`, branch `fix/conv-r2-capability-wait`:
   1 commit c51a560c + UNCOMMITTED edits (CapabilityProbe/ConvertTab/Engine/EngineWait/MainForm) when written.
   Its implementer may still be running or may have stopped at the clear: check `ListAgents`, `git -C <wt> log`,
   `git -C <wt> status`; resume or re-dispatch (session model) to finish: no-engine model tests, both builds,
   lint; then report. MERGE R2 to main BEFORE Task 1 -- it edits Engine.pas + ConvertTab.pas (lanes E, T).
   Its with-engine tests + GUI RED proof wait for "re-parse done".
2. Then superpowers:subagent-driven-development over the plan, highly parallel (owner 2026-10-25): Task 1, then
   Tasks 2-5 at once, each in its own hand-made worktree under `C:\Projects\Delphi-RAG-lint-wt\conv-enc-*`
   (Agent isolation:"worktree" is refused while the session cwd is lowercase `c:`). Model per task as in the plan.
3. Merge each green lane to main (cherry-pick or --no-ff merge), announce to ENGINE; featuregen build --all only
   after "ok" from ENGINE (delphi-rag-lint-65) and LSP (lsp-4e).

## Gotchas
* BRIEF for agents: `C:\TEMP\claude\c--Projects-Delphi-RAG-lint-src-tools-convrules-editor\3ea50c2b-f01d-41b6-918c-3dad369d920b\scratchpad\shared\BRIEF.md`
  (owner rulings, GUI lock, 2026-10-24 rule: an engine built from main fingerprints extractor 1.23.0 -- never index a REAL DB with it).
  Run log: same folder RUNLOG.md.
* Never `python -` heredocs (3 orphan spinners burned cores for 1-3 days). Use PowerShell [IO.File].
* A script that runs `git branch -D` in a child pwsh bypasses the autonomy guard -- don't. Owed to the owner:
  `git worktree remove --force C:/Projects/Delphi-RAG-lint-wt/conv-fgorder` + `git branch -D fix/featuregen-helporder-tiebreak`.
* Main-tree dirty files NOT ours: featuregen HelpText.pas / FeatureGenTests.dpr (ENGINE X-26 follow-up), RESUME.md, an ENGINE handoff.
* Pin: still 1.33.0-alpha-20261021-122057 (drifts vs deployed 1.34.0-alpha, expected); re-pin + baseline after "re-parse done".
* Backlog: `docs\CONVERTER-BACKLOG.md` (R1-R7, FG-O/P done, re-pin, A4).
