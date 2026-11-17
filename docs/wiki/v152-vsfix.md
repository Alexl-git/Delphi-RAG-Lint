# Fix with drag-lint (VS Code and RAD Studio)

drag-lint applies its own deterministic autofix from the editor, the same engine call as `lint --fix`.

## VS Code

| Where | What you get |
|---|---|
| Light bulb / Ctrl+. on a finding | `Fix: <rule>` (this finding, quickfix), `drag-lint: fix all <rule> in file` (when the file holds two or more of that rule), `drag-lint: fix all fixable in file` (kind `source.fixAll.drag-lint`) |
| Editor right-click | `Fix with drag-lint` (this finding), `Fix all fixable with drag-lint` (whole file) |
| Problems panel right-click | `Fix with drag-lint` (entry offered where the VS Code build supports the `problems/context` menu; otherwise use Quick Fix on the entry) |
| Save | add `"source.fixAll.drag-lint": "explicit"` to `[pascal] editor.codeActionsOnSave` to fix on save (the shipped default is `never`) |

Only the safe, buffer-checked fixes are offered here (mixed-case-hex, length-zero-compare, deprecated-rtl-function): every edit must replace text the unsaved buffer really holds, so a stale finding gets no action. Risky fixes stay in `lint --fix` and the RAD Studio dialog.

## RAD Studio

Put the caret on the finding's line, then right-click in the editor, open the drag-lint submenu and choose `Fix with drag-lint (finding at cursor)`. Yes applies (all modules are saved first and the engine keeps a backup copy), No previews, Cancel does nothing.
