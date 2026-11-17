---
id: editor-context-menu
title: Editor right-click submenu
summary: "The drag-lint submenu of the code editor's right-click menu: the 1.52 caret commands, enabled by what the caret is on"
product: DL
group: editor-integration
order: 110006
since: 1.51.1-alpha
status: shipped
updated: 1.51.1-alpha
---

# Editor right-click submenu

The drag-lint submenu of the code editor's right-click menu: the 1.52 caret commands, enabled by what the caret is on.

Read this when you want a drag-lint command for the code under the caret without going through the main menu. Right-click in the code editor and open the drag-lint submenu (after the Refactor group). It lists every 1.52 command whose row in the plugin command table names the editor surface; an item that needs a symbol is enabled only with an identifier under the caret, one that needs a finding only when a drag-lint finding is on the caret line. The submenu is hidden while none of its commands is switched on.

## Where to click

* Right-click in the Editor: **drag-lint**
   1. Put the caret on the identifier or on the line of the finding
   2. Right-click in the code editor and open the drag-lint submenu (after the Refactor group)
   3. Choose the command; an item greyed out needs a symbol under the caret or a finding on the caret line

## Details

The **drag-lint** submenu of the RAD Studio code editor's right-click menu
(1.52). It carries the caret commands of the 1.52 plugin command table, so a
command about the code under the caret is one right-click away instead of a
walk through the main menu.

### Where it is

Right-click anywhere in a code editor tab. The **drag-lint** submenu sits after
the IDE's Refactor group. It is rebuilt every time the menu opens, so it is the
same in every editor window, docked or undocked, and after closing and
reopening files.

The submenu is **hidden while none of its commands is switched on**: each 1.52
command ships hidden in its own unit and appears once its lane enables it.

### What is enabled

Each command declares what the caret must be on:

| Needs | Enabled when |
|---|---|
| nothing | always |
| symbol | an identifier is under the caret (a number literal is not) |
| finding | a drag-lint finding (gutter marker) is on the caret line |

A disabled item is still listed, so the menu does not jump around as the caret
moves.

### The 1.52 commands and their surfaces

| Command | Main menu | Right-click | Needs |
|---|---|---|---|
| Check Initialization of Identifier at Cursor... | Analyze | yes | symbol |
| Disable Rule... | Code Quality | yes | finding |
| Extract Constant (literal at cursor)... | drag-lint | yes | nothing |
| Fix with drag-lint (finding at cursor) | Code Quality | yes | finding |
| Verify All Callers Pass an In-Range Index... | Code Quality | yes | finding |
| Open Field Repository Editor... | Field Repository | no | -- |

### For plugin developers

One table, two surfaces. A command lives in its own
`DragLint.Plugin.Cmd.<X>.pas` and registers one `TCmd152Command` row
(`DragLint.Plugin.Cmd152`). `Surfaces` says where it appears
(`csMainMenu`, `csEditorContext`), `Needs` what enables it on the right-click
menu (`cnNothing`, `cnSymbol`, `cnFinding`). The editor hook is
`DragLint.Plugin.EditorLocalMenu`: one action list registered through the
Open Tools API's `INTAEditorLocalMenu` (no per-window notifier), unregistered
before the package unloads.

The feature registry records each visible right-click item as an
`ide-context` surface with host `Editor` and caption
made of the submenu name, a greater-than sign and the item caption; `featuregen check` harvests the live captions from
the command units and fails on an unregistered one.

Test: `tests\autotest\run_v152_PLUGCTX_menu.ps1` (add `-Build` for the Win32 +
Win64 package builds).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
