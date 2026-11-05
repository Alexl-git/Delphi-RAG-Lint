# Handoff 2026-11-05: CHARTS docs branch waiting, chart panel spike proposed

## Status
* `ask` verified; `--question`, full `usage`, F1v guard and `--mode` arg fixes are in 1.43 (local main 334e2bb4; engine session reports its guards PASS).
* origin/main = 628652c1 when last checked; the engine session pushes 1.43 and will announce it (publish expected about 17:00-17:30).
* draglint:// re-registered on this machine: `protocol status` reads `ours`, handler `third_party\dll-win64\drag-lint-open.exe`. A bad link is refused with exit 2. NO live click tested (RAD Studio was not running).
* Docs cleanup committed: branch `charts/docs-no-powershell` @ 88e5f2f5, parent 334e2bb4, 41 files, LOCAL ONLY. Registry check, docs-sync, registry and encoding guards PASS with a copy of the 1.43 engine.

## Resume point
1. DECIDED by the owner 2026-11-05: merge the docs AFTER the 1.43 push; 88e5f2f5 stays out of 1.43.
2. DONE: 1.43.0-alpha pushed and released at 3a2b0c5c; the engine session lifted its hold.
3. DONE: docs merged at 1e52cb6b and local main fast-forwarded. featuregen changes nothing; docs-sync, registry and encoding guards PASS. Docs-sync reads src\cli\Win64\Debug\drag-lint.exe, so copy the current engine there first. Push of main awaits the owner's OK.
3a. Owner's IDE test page: C:\Projects\Delphi-RAG-lint\docs\TEST-1.43-owner-checklist.html (untracked). The engine session re-measures the two zero-finding effect rules with a positive control.
4. Ask the owner to click a chart row with RAD Studio open. It should jump to the line; Notepad means the IDE did not answer.

## Not done yet (owner decides)
* Engine output still prints PowerShell style (`COMMAND who-writes -Target ...`, `(-Cap N ...)`). `compare` reads it back from saved reports, so a change must keep old reports working. Separate small task, after the release.
* Remaining accurate mentions left in place: `(no PowerShell)` in the ask and compare help lines and the protocol handler summary.
* Chart panel: owner asked about a floating panel with zoom, pan, resize and clicks, and merging DL-graph (C:\Projects\Delphi-RAG-Lint-Graph). Recommendation given, not yet approved: a 1-2 day spike AFTER 1.43 publishes, in a fresh session with a short design spec. Render the largest real ORM3 chart in the existing `drag_lint_graph.exe` (Skia, out of process), measure load, zoom and click accuracy from `graph.plain`. Then the chart panel (1-2 weeks, rough guess), then one window for both modes. Do not merge the code: keep both layouts. DL-graph plan: `docs/PLAN-2026-09-16-graphviz-skia-render-pipeline.md` in that repo. Hosting proof: `src\delphi-plugin\DragLint.Plugin.GraphWindow.pas`.

## Gotchas
* This worktree's third_party\dll-win64 holds a copy of the 1.43 engine with synced rules, and src\delphi-plugin\_D-RAG is indexed. featuregen with a stale copy or no plugin index silently damages the manifest and rule counts: fix the setup, regenerate, check the diff.
* Use plain msbuild here; build_draglint_win64.bat stages through a step that can kill running engines.
* The old untracked src\cli\_D-RAG\drag-lint-project.json was moved to the session scratchpad; main's tracked version replaces it.
* Other local branches: charts/ask-question-flag (pushed, already in 1.43), charts/ps-free (merged).