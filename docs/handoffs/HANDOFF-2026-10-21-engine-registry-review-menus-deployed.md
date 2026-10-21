# HANDOFF 2026-10-21 -- ENGINE: registry review done, menus merged, engine + plugin BPL deployed

## Status
- ENGINE feature-registry review COMPLETE and pushed: main 20ffb523 on origin.
  - All 153 ENGINE entries have intro + `featuregen verify --by ENGINE`.
  - Access review (`review-access`): 41 cli-only, 5 repo-tooling stamped; the rest have an IDE surface.
  - Stale wiki pages fixed (lint-project, drag-lint-options/rules.md, ghost-check, full-compile-sweep, context, compile-check, document-all).
  - Stale-entry sweep: nothing removed. resolve-uses is a HIDDEN internal verb (not in --help), kept, verified.
- IDE menu items added and merged (2b2d832a + second merge): Extract Method (Ctrl+Alt+M), Safe Delete, Uses & Dependencies (Find Unit, Call Tree, What This Routine Calls, Call Path), Inspect Symbol (Helpers of Type, Ancestors, Descendants), Generate & Export (Auto-Document Every Indexed Unit, Forget/List Doc Project Tags, Enum Record Helper), Code Quality > Project Structure Rules, Index & Maintenance (Shrink Index, Migrate Index DBs), new Help submenu, Reports > Compare a Saved Report or Chart.
- Engine rebuilt from main and DEPLOYED to third_party\dll-win64 (12:20). Plugin BPL built Win32 Debug and deployed to third_party\dll-win32 (12:28); backup `dclDragLintWizard.bpl.bak-20261021`. Tracked .bpl/.dcp show modified in git, NOT committed (owner's call).
- Guards: registry, docs-sync (F0 now passes), encoding PASS; CONVERTER reported FeatureGenTests 214/0.

## Resume point (first things to do)
1. Owner is starting the IDE to test the NEW menu items and YADFOT. Fix whatever misbehaves (backup BPL is the way back). The new items were built but never exercised in a live IDE.
2. Owner review pending: `call-path`, `find-callees`, `callgraph` Uses & Dependencies items may duplicate Reports questions (`ask path`, `what-it-calls`, `who-calls`). Keep until the owner decides; if the SAME code is called from both, drop the menu items and their registry surfaces.
3. Website publish is NOT mine: www-51 publishes (`WWW\publish.ps1`) only on the owner's direct word in its session. Do not run it. www-51 was told the push landed (20ffb523); CONVERTER (convrules-editor-40) owes the final help/dl notice to it.
4. Decide whether to commit the rebuilt .bpl/.dcp in third_party\dll-win32.

## Not done yet
- Leftover empty dir `.claude\worktrees\agent-a4ab941b3081ee0f1` (git registration + branch removed; Windows said Permission denied -- delete once nothing holds it).
- Remaining registry gaps (not owed for the R2 deadline): no-questions 152, no-steps 103, no-flags 9, no-usage 7 for ENGINE (`featuregen audit --owner ENGINE`).
- SOMEHELPID keying: I recommended one help page per feature plus a shared group id used only as "see also"; no framework ruling found. CONVERTER owns the answer.
- compare (CHARTS) etc: CHARTS done. CONVERTER stamps its own entries.

## Gotchas
- A plain `python -` heredoc hung the Bash tool (killed); use Write for files.
- PowerShell `--set "surfaces=<json>"` breaks on embedded quotes: edit the entry JSON then `featuregen normalise`.
- `usage` of an entry is the help-block OWNER key for the generated --help (query-kind-all owns the whole `query --name` block). Changing usage/help[] of query-* entries drops frozen --help lines (found and fixed in 5d0c1a2b).
- Engine deploy: ide-release + `shutdown --all` first, then rerun build_draglint_win64.bat. VS Code engine copies under globalStorage are separate.
- Subagent worktrees do not have an index; they use grep.
- Reports: docs\registry-review-2026-10-21\report-*.md (ENGINE batches 1-4, fixes), BRIEF-intro-verify.md, ENGINE-menu-access.tsv, ENGINE-menu-registry-specs(-2).md.
