---
id: v152-vsfix
title: Fix with drag-lint (VS Code and RAD Studio)
summary: "Fix the finding at the cursor, all of one rule, or every fixable finding in a file: VS Code code actions and menus, plus a RAD Studio menu entry"
product: DL
group: refactoring
order: 50024
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Fix with drag-lint (VS Code and RAD Studio)

Fix the finding at the cursor, all of one rule, or every fixable finding in a file: VS Code code actions and menus, plus a RAD Studio menu entry.

Read this when you want drag-lint to apply its own deterministic fix instead of editing by hand. In VS Code, use the light bulb (`Fix: <rule>`, `drag-lint: fix all <rule> in file`, `drag-lint: fix all fixable in file`), right-click in the editor or on a Problems entry and choose Fix with drag-lint, or let editor.codeActionsOnSave run source.fixAll.drag-lint. In RAD Studio, put the caret on the finding, right-click in the editor, open the drag-lint submenu and choose Fix with drag-lint (finding at cursor).

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Fix with drag-lint (finding at cursor)**
   1. Put the caret on a line that shows a drag-lint finding
   2. Choose drag-lint > Code Quality > Fix with drag-lint (finding at cursor)
   3. Answer Yes to apply the fix, No to preview it
* Right-click in the Editor: **drag-lint > Fix with drag-lint (finding at cursor)**
   1. Put the caret on a line that shows a drag-lint finding
   2. Right-click in the editor, open the drag-lint submenu and choose Fix with drag-lint (finding at cursor)
   3. Answer Yes to apply the fix, No to preview it

## Details

drag-lint applies its own deterministic autofix from the editor, the same engine call as `lint --fix`.

### VS Code

| Where | What you get |
|---|---|
| Light bulb / Ctrl+. on a finding | `Fix: <rule>` (this finding, quickfix), `drag-lint: fix all <rule> in file` (when the file holds two or more of that rule), `drag-lint: fix all fixable in file` (kind `source.fixAll.drag-lint`) |
| Editor right-click | `Fix with drag-lint` (this finding), `Fix all fixable with drag-lint` (whole file) |
| Problems panel right-click | `Fix with drag-lint` (entry offered where the VS Code build supports the `problems/context` menu; otherwise use Quick Fix on the entry) |
| Save | add `"source.fixAll.drag-lint": "explicit"` to `[pascal] editor.codeActionsOnSave` to fix on save (the shipped default is `never`) |

Only the safe, buffer-checked fixes are offered here (mixed-case-hex, length-zero-compare, deprecated-rtl-function): every edit must replace text the unsaved buffer really holds, so a stale finding gets no action. Risky fixes stay in `lint --fix` and the RAD Studio dialog.

### RAD Studio

Put the caret on the finding's line, then right-click in the editor, open the drag-lint submenu and choose `Fix with drag-lint (finding at cursor)`. Yes applies (all modules are saved first and the engine keeps a backup copy), No previews, Cancel does nothing.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
