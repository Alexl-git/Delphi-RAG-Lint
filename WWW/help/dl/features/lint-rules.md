---
id: lint-rules
title: Lint rules
summary: Every lint rule the engine ships, imported from rules --json
product: DL
group: linting
order: 30014
since: 0.2.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# Lint rules

Every lint rule the engine ships, imported from rules --json.

## How to run it

Full flag list: [rules in the CLI reference](../cli.md#rules).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--category` | `<name>` |  |  |
| `--rules-dir` | `<dir>` |  |  |

## Details

Lists the full lint rule catalog: every rule drag-lint can check, with its
category, and its default enabled/fixable status. Reach for it to see what a
lint run can find, or to filter by category.

The catalog currently holds 190 rules -- 160 enabled by default, 23 marked
fixable -- across 16 categories. Of the 189, 137 are built-in and 53 are
external `.scm` rule files.

### Running it from the CLI

```text
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```

### Reaching it in the IDE

CLI+internal: the IDE's Options dialog loads this catalog by running
`rules --json` internally, from `DragLint.Plugin.LintOptionsFrame.pas:88`.
There is also a menu item that surfaces the catalog for one specific
project: right-click a project in the Project Manager and choose
"drag-lint: Project Rules..." -- see
[drag-lint: Project Rules...](drag-lint-project-rules.md).

### What it needs

No index required -- `rules` reads the static rule catalog, not any
project's indexed data.

### Example

Illustrative:

```text
drag-lint rules --category naming --json
```

This would print the catalog of naming-category rules as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
