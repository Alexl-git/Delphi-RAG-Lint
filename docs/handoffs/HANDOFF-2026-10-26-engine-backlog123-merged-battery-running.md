# HANDOFF 2026-10-26 -- ENGINE -- backlog sections 1-3 merged; verify battery running

Controller `delphi-rag-lint-65`. Resumed `HANDOFF-2026-10-26-engine-1350-released-backlog2-next.md` (now closed).
Ledger: `.superpowers\sdd\2026-10-23-engine-3day\progress.md` (rows from "RESUME 10-26" to "VERIFY" at the bottom).

## Status: everything merged to LOCAL main (c2c99868); not pushed (48 ahead incl. CONVERTER lanes), not deployed
- S1: INBOX local-var-read-refs-unbound retired (leaf binds on 1.35.0). Filed: uba-silent-on-unassigned-member-write,
  conv-enc-nonansi-identifiers-lossy (items 2-3 fixed by CONVERTER c1928263; item 1 open),
  engine-output-ansi-and-nonansi-input-lossy (parked-owner). Registry re-verify ff11bc42. Plugin cycle-fix limit
  130 min + vacuous run_cyclefix_timeouts fixed (T5) 272925bc.
- Lanes merged: A2 test acbe4a4d (A2/X-11 were already on main); HYG 0cada3ef + 7a4ddb75 (X-15 0 gaps, X-27 already marked);
  EUK 979944de + 0cddf59d ("Used in classes:"; root cause v23 label run-on); CYC-C 791802bc + 2550ba6d (partial: see ledger);
  T-22 3b434b08 (reconcile-project verdict + `--to library` + rule unit-not-in-library, 195 rules / 142 / 165 on);
  CYC-B 37ec566d (F2092 = old defect, B3, B4 a/b/c/e) + lint 9c45732f; CONVERTER conv-enc-nonansi c1928263;
  FLAG merge (c52ab911 alias policy docs\CLI-FLAG-ALIASES.md + features\flag-aliases.json, 50279dba X-26, 4635bc4a);
  featuregen regen c2c99868 (registry guard PASS with -Engine <merged build>).
- T-22 APPLIED to MicroniteTests (owner ruling): FlexDateTime + MSCTYPES in .dpr/.dproj (.bak beside; copy in
  C:\TEMP\claude\lanes\owed\bak-MicroniteTests), reindexed, both members. PdfOcrImportTests: 0 project units.
- Notified: convrules-editor-31 (re-pinned 1.35.0 at third_party\engine-pinned\1.35.0-alpha-20261025-125433), www-5b, lsp-4e.

## Resume point
1. Battery: verify worktree `.claude\worktrees\verify-1026` (detached at c2c99868, engine built there by its own
   build bat -- its third_party only). Running `tests\run_battery.ps1 -Jobs 6`, log `C:\TEMP\claude\lanes\owed\battery.log`.
   If the log has no final summary, rerun the same command from that worktree. Triage vs known reds:
   run_featuregen_tests frozen banner (CONVERTER), run_reviewmarker_yadf_mirror (env), parallel flakes
   run_uses_fix_json_and_only / run_uses_fix_include_skip / run_procrun_jobs (green serially); r2_dcc z1 if the real
   library-Win64.sqlite mtime moves. run_flag_verb_map should now be GREEN.
2. Final whole-branch lint sweep (repo CLAUDE.md "Two controllers"): lint-all + per changed unit with
   multiple-statements-per-line,magic-literal,commented-out-code + review-marker-stale/unused.
3. Ask owner: (a) deploy go for 1.35.1/1.36.0 (DRAGLINT_VERSION bump + CHANGELOG Unreleased -> version; NO extractor
   bump); (b) push main; (c) DUnitX: test projects use C:\Projects\DUnitX\Source (46 units) while the library DBs hold
   the bundled Studio\37.0\source\DUnitX (92 files, same unit names) -- add the copy as library include (`--to library`,
   needs deploy) or accept the bundled one; (d) `--in` canonical over `--file` (outline --file now shows as --in);
   (e) UTF-8 output INBOX (parked-owner; LSP didSave reads lint --json as UTF8 at LSP.Server.pas:3679); (f) B4-d needs owner ruling 2; (g) branch/worktree cleanup (lane worktrees
   agent-ab5fcea2, a97a7239, ad1b2e68, a3b9d0e9, acd2fb09, ab395cfc, a0b8cb56 + verify-1026 + earlier list).
4. After deploy: tell www-5b (rule counts, outline --in), convrules-editor-31, lsp-4e; reindex; docs-sync guard on the
   deployed exe; doc-drift --fix only AFTER deploy (deployed exe strips the IParser "Used in classes" line).

## Not done (backlog rest)
- CYC-C leftovers (design): C6 indented type/var header; C2 R2 interface name + Get<M>; C7 @ forms, other B.X,
  type-decl/cast/multi-class/member-unsupported/type-unresolved/non-ascii/--rsvars/--build-timeout. B4-f new rank.
- X-26 still-leaking stdout under --json: query unit-usage, impact, wiring, reverse-calltree, outline, find-unit, lint,
  shared-unit error lines. Featuregen cycles-fix entry update (CYC-C/B behaviour).
- ~230 "managed facts block out of date" doc-drift warnings (Storage.SQLite) -- after deploy.
- MicroniteTests build fails PRE-EXISTING: Spring.inc (spring4d\Source) not on its search path (ORM3 owner).
- Plans/backlog docs under docs\superpowers\plans are UNTRACKED (lanes read them from the main path); backlog-full
  rows A2/X-11/X-24/T-22/X-14/X-06/X-27/X-15 now done -- update that table.

## Gotchas
- The main-tree featuregen.exe can be STALE vs its sources: rebuild (`build\_build_featuregen_local.bat`) and pass
  `build --all --engine <merged exe>`, else it renders 194 rules and drops the Flag aliases section.
- Private engine build without deploy: C:\TEMP\claude\lanes\owed\eb.bat (DCC_ExeOutput to scratch exe\).
- Another team's uncommitted edits in main tree: docs/handoffs/RESUME.md, docs/wiki/convrules-editor-encoding.md,
  src/tools/featuregen/FeatureGen.HelpText.pas -- not ours, never commit them.
- INBOX notes are untracked: move with Move-Item, not git mv; keep INBOX-INDEX headline + status table counts in sync
  (run_backlog_index_guard.ps1).
