# HANDOFF 2026-10-19 -- converter: A2 + C merged to local main; 2 branches wait for the re-parse

Session: convrules-editor-02 (DL account, `~\.claude-dl`). Standing list:
`docs\CONVERTER-BACKLOG.md` (NOT yet rewritten -- see "Not done yet" 3).

## Status

* **Pin:** `third_party\engine-pinned\1.31.5-alpha-20261019-071827` (sha 201DE760...,
  extractor 1.21.1). Verified: info/rules (190)/query; editor exe + baseline recorded in its
  ENGINE-PIN.json. The 1.27.0 pin is kept.
* **On LOCAL main, NOT pushed:** 3cdadd60 (A2 one-click "qualify #convert" fix) and 1d888db1
  (C minors + #depth repair), squash merges. Main has since moved on (engine rel/1.22 merge
  bd10d7e1 ...); local main is 21 ahead of origin at 1acaab53. **The owner pushes**
  (`! git push origin main`): the autonomy hook refuses a push from the agent.
  Merged tree measured on the 1.31.5 pin: model tests 2281 pass / 5 fail (VARINSP only),
  drivers qualify-fix 20, convert-tab 23, book-depth 21, convert-request 28; 0 lint on changed
  lines; docs-sync, feature-registry and encoding guards PASS.
* **ENGINE 1.22 (product 1.32.0-alpha, extractor 1.22.0) is swapped into dll-win64 and the
  full re-parse is RUNNING (started ~2026-10-19 mid-day, ~5 h).** Until ENGINE announces
  "re-parse done": no index, lint-all or convert against real DBs; no GUI drivers.
  C18 slice 1 (`#migrate X -> Y`, `-> DL_NONE`) contract: `docs\NOTICE-2026-10-19-c18-slice1-migrate.md`.
* **Sent to ENGINE:** `docs\INBOX-REPLY-2026-10-19-converter-to-engine-qualify-and-castlib.md`
  (G1 FYI: one rule line can carry two qualify_fixes and each `replacement` is per-side only;
  request: StripDB castlib to accept string aliases like TFileName -- owner ruling C-1).

## Branches waiting (unmerged, worktrees under `C:\Projects\Delphi-RAG-lint-wt\`)

| branch | worktree | tip | content | owes |
|---|---|---|---|---|
| feat/converter-apply-fields | conv-apply-fields | 7ee877a4 | B1/B3/B6/B7 apply fields (only_matched/unmatched, only_included, unlinked[], descendants[] gated afDescendants, index-gap hint), B8 exit-code half-apply guard (text match kept as legacy fallback), batch parse helpers (NOT wired: B4), C-2 Work list "from the previous run ...; the last Convert was refused" | review + drivers |
| fix/converter-testkit | conv-testkit | 017dd85a | drive-file-menu exit 1 on FAIL; drive-work-list clipboard retry (10 x 200 ms) | driver runs |

Both branched from main 1acaab53. apply-fields: model tests without an engine 2224 pass / 0 fail / 19 skip.

## Resume point -- in order

1. Wait for ENGINE's "re-parse done" message (session delphi-rag-lint-db). Check with
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\check-engine-drift.ps1` (exit 1 = drifted, expected).
2. **Re-pin to 1.32.0** exactly like the 1.31.5 pin: copy dll-win64 (exe, drag-lint.json,
   3 tree-sitter DLLs, casts.castlib, rules\) to `engine-pinned\1.32.0-alpha-<stamp>\`, sha before
   and after the copy, write ENGINE-PIN.json with a SHA you computed, verify info / rules / one
   query. Tell delphi-rag-lint-db at start and end. Then baseline on MAIN: build editor + tests,
   model tests (expect 2281/5 or a new VARINSP count), all 14 drivers incl. drive-qualify-fix.
3. **Review feat/converter-apply-fields on the session model** before merge. Known debts:
   * no test was ever seen RED -> mutation positive controls (as the A2 review did);
   * `ParseApplyJson`: `Obj.GetValue<Boolean>('ok', False)` raises on a non-bool `ok`
     (standing trap: type-check every apply/1 read);
   * decide whether B8's legacy text match stays (backlog said drop it);
   * drivers owed: convert-tab, convert-request, work-list (+ new check: refused Convert keeps rows +
     "previous run" summary), validate-scope, inherited-offer.
   Then fix/converter-testkit: run drive-file-menu (forced FAIL -> exit 1) and drive-work-list.
4. Merge both: squash onto main from an integration worktree, `--ff-only` main, announce to the
   other sessions, owner pushes. Never git add -f docs\superpowers (ignored on purpose, 3d43498d).
5. **A4 `#migrate`** (C18 slice 1): Fable spec + plan from the NOTICE, owner approves, then implement.
6. Re-capture `tests\fixtures\apply1270\` uses rows: the capture project `C:\fix\` is gone --
   rebuild a capture fixture deliberately (needs an indexed unit, so after the re-parse).
7. N1 bug (medium): Convert clicked right after adding a unit or after Save silently does
   nothing (click lost while analysis/validation pending). Driver repro first.

## Not done yet (owner decisions already made, 2026-10-19)

1. C-1 (TFileName StripDB): ENGINE castlib -- waits on ENGINE.
2. C-2: done on feat/converter-apply-fields (keep rows, label as previous run).
3. **Rewrite `docs\CONVERTER-BACKLOG.md`** from the re-triage proposal
   `docs\handoffs\CONVERTER-BACKLOG-proposed-2026-10-19.md` (copied from scratch), applying the owner's answers:
   A2, C, B1/B3/B6/B7/B8, C-2, D test-kit debts done (once merged); **D4** (clickable `#use` alternative
   in the qualify dialog) and **D6** ("Qualify all") ADDED; **B2** and **B5** DROPPED (no longer fire on
   1.31.5); E (instruction trim) DONE; new: N1 lost Convert click, QualifyFix mutant Q08 "retarget
   ignores Applied" survives (low), apply1270 capture project lost, B4 runner batch mode (helpers exist).
4. Cleanup (needs approval, batch at the end): worktrees conv-trial, conv-qualify-fix, conv-c-minors,
   conv-integrate and their branches (tmp/conv-trial, feat/convert-qualify-fix, fix/converter-c-minors,
   conv/integrate) -- all merged or scratch.

## Gotchas

* `git commit -- <path>` cannot record a `git rm --cached` (it commits the on-disk file): check the
  staged set is exactly that deletion, then commit without a pathspec.
* The drag-lint-first hook blocks `Select-String` over .pas: use `git diff --cached --check` for
  conflict markers.
* A fresh worktree has no engine: guards need a copy in `third_party\dll-win64` (registry) and
  `src\cli\Win64\Debug` (docs-sync, use the deployed engine built from main, not the pin).
* The editor has no .dproj: index with `--project <...>.dpr`; `resolve-dbs --project` fails there.
* Model tests with no engine: live tests SKIP (19), so VARINSP fails disappear -- not a fix.
* Subagent "untracked it" claims: verify with `git ls-tree -r --name-only <branch> docs/superpowers`.
