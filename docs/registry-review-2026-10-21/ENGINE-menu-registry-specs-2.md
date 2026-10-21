# ENGINE menu access -- registry surface specs, batch 2 (2026-10-21)

Add each line with `featuregen add/--surface` (full path; `&&` in source is `&` in the path).
Nothing under `features\entries` or `features\generated` was edited. Captions are exactly those
built in `RegisterDragLintMenu` (`src\delphi-plugin\DragLint.Plugin.Editor.pas`).
Wiki: `docs\wiki\IDE-Menu-Reference.md` updated.

## New menu items

| feature id | surface to add |
|---|---|
| lint-project | `ide-menu:drag-lint > Code Quality > Project Structure Rules (god-class, layering...)...` |
| query-ancestors | `ide-menu:drag-lint > Inspect Symbol > Ancestors of Type (full chain)...` |
| query-descendants | `ide-menu:drag-lint > Inspect Symbol > Descendants of Class...` |
| compare | `ide-menu:drag-lint > Reports > Compare a Saved Report or Chart with Current Code...` |

`compare` sits in Reports (under the header "Is a saved report still true?") because the plugin has
no charts submenu: charts are reached from Reports (butterfly question) and Generate & Export
(Export Graph (DOT)), and what `compare` reruns is a Reports question. The dialog takes a report
.txt / forms .csv / chart .dot (Yes) or a bundle folder (No) and runs `compare --old <x> --format text`.

## Already reachable (no new item; add/confirm this surface on the entry)

| feature id | existing surface | why it is the same verb |
|---|---|---|
| circular-dependency-report | `ide-menu:drag-lint > Uses & Dependencies > Circular Uses Report (cycles + fix plan)...` | The entry is the worked example of this report; the item runs `cycles --plan --edges --causes`. Reports > "Circular unit dependencies..." (`ask cycles`) is the question form. |
| query-find-callers | `ide-menu:drag-lint > Find Usages...` | The Find Usages tree (UsagesForm, also the dock panel tab) runs `query find-callers` on Enter. |
| reverse-call-tree-clickable-messages-window | `ide-menu:drag-lint > Uses & Dependencies > Reverse Call Tree (who calls this, N-deep)...` | Asks where to render; Yes = IDE Messages window (clickable), No = text buffer. |
| ghost-recover | `ide-about:Recover Buffer-Compile Files` | Exact About-dialog button caption (AboutForm.pas AddProcButton). |

## Not added

| feature id | reason |
|---|---|
| convert-apply-migrate | `#migrate` is a directive inside a `#convert` rules block fed to `convert-apply --rules`. It is rules-file syntax for the conversion tooling (CONVERTER-owned; conversion editor and CLI), not a standalone action, so there is nothing for an IDE menu click to run. Reference it from the converter's own surface. |