# ENGINE menu access -- registry surface specs (2026-10-21)

Add each line to the named entry with `featuregen add/--surface` (type `ide-menu`, FULL path,
`&&` in the source is written `&` in the path). Nothing under `features\entries` was edited by
this change. Menu captions are exactly those built in `RegisterDragLintMenu`
(`src\delphi-plugin\DragLint.Plugin.Editor.pas`). Wiki: `docs\wiki\IDE-Menu-Reference.md` updated.

| feature id | surface to add |
|---|---|
| find-callees | `ide-menu:drag-lint > Uses & Dependencies > What This Routine Calls (callees)...` |
| callgraph | `ide-menu:drag-lint > Uses & Dependencies > Call Tree (callers or callees, N-deep)...` |
| call-path | `ide-menu:drag-lint > Uses & Dependencies > Call Path Between Two Routines...` |
| find-unit | `ide-menu:drag-lint > Uses & Dependencies > Find Unit for Symbol (add to uses)...` |
| safe-delete | `ide-menu:drag-lint > Safe Delete Symbol...` |
| extract-method | `ide-menu:drag-lint > Extract Method (selection)... (Ctrl+Alt+M)` |
| create-enum-helper | `ide-menu:drag-lint > Generate & Export > Enum Record Helper (symbol)...` |
| helpers-of | `ide-menu:drag-lint > Inspect Symbol > Helpers of Type...` |
| document-all | `ide-menu:drag-lint > Generate & Export > Auto-Document Every Indexed Unit...` |
| doc-forget | `ide-menu:drag-lint > Generate & Export > Forget Documentation Project Tag...` ;; `ide-menu:drag-lint > Generate & Export > List Documentation Project Tags` |
| purge-locals | `ide-menu:drag-lint > Index & Maintenance > Shrink Index (purge locals)...` |
| migrate-dbs | `ide-menu:drag-lint > Index & Maintenance > Migrate Index DBs to _D-RAG...` |
| ide-menu-reference | `ide-menu:drag-lint > Help > IDE Menu Reference (wiki)` |
| effect-summary-legend | `ide-menu:drag-lint > Help > Effect Summary Legend (wiki)` |

## Already reachable (no new entry; confirm the existing surface is on the entry)

| feature id | existing surface |
|---|---|
| usages | `ide-menu:drag-lint > Find Usages...` (UsagesForm runs `usages --name`) |
| outline | `ide-menu:drag-lint > Show Structure` (StructureCache runs `outline --format json`) |
| butterfly | `ide-menu:drag-lint > Uses & Dependencies > Call Graph (Butterfly)...` |
| ghost-check | `ide-menu:drag-lint > Compile Buffer (unsaved)` |
| ghost-recover | `ide-about:Recover Buffer-Compile Files` |

## Notes for the registry owner

- Reports also holds `Reports > ... Call path from this routine to another...` and `What this
  routine calls...` (the `ask path` / `ask what-it-calls` questions). Same questions, different
  verb and output; the new Uses & Dependencies items expose the raw `call-path` / `find-callees` /
  `callgraph` verbs. If the owner judges them duplicates, drop those three menu items.
- `helpers-of` and `create-enum-helper` were already reachable from the Structure window's context
  menu (symbol rows); the main-menu entries are additions, not moves.
