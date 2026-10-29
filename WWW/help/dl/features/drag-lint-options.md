---
id: drag-lint-options
title: drag-lint Options
summary: "The plugin's settings dialog for drag-lint: lets you browse and toggle the lint rule catalog"
product: DL
group: editor-integration
order: 110004
since: 0.95.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# drag-lint Options

The plugin's settings dialog for drag-lint: lets you browse and toggle the lint rule catalog.

Read this when you want to see which lint rules exist, which are on by default and which have an auto-fix, or to turn rules on and off. Open it from the drag-lint menu; it loads the catalog the same way as drag-lint rules --json.

## Where to click

* RAD Studio main menu: **drag-lint > drag-lint Options...**
   1. Choose drag-lint > drag-lint Options...
   2. Browse the rule catalog (default state, auto-fix)
   3. Toggle rules on or off

## Details

The plugin's settings dialog for drag-lint: lets you browse and toggle the
lint rule catalog. Reach for it to see which rules exist, which are on by
default, and which have an auto-fix, and to change what is enabled.

### Running it from the CLI
The dialog itself is in-process (no CLI shell-out), but it loads its rule
catalog by running:
```text
drag-lint rules --json
```
The equivalent standalone command, with the same catalog:
```text
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```
As loaded by this dialog, the catalog has 290 rules, 111 of them fixable,
246 on by default, across 18 categories.

### What it needs
Not documented as needing an index -- the feature map marks this row's
Index column "n/a" and its Mechanism "in-process". It needs the rule
catalog files that `rules --json` reads; it does not need a project
database.

### Example
Illustrative only: opening drag-lint > drag-lint Options... shows the
full 290-rule catalog, grouped by its 18 categories, with a toggle per
rule and a marker for which of the 111 fixable rules have an auto-fix.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
