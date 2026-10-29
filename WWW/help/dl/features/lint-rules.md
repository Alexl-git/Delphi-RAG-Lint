---
id: lint-rules
title: Lint rules
summary: Every lint rule the engine ships, imported from rules --json
product: DL
group: linting
order: 30017
since: 0.2.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Lint rules

Every lint rule the engine ships, imported from rules --json.

Read this to see every lint rule drag-lint can check, with its category and whether it is on by default or fixable. You can filter the list by category or get it as JSON.

## How to run it

Full flag list: [rules in the CLI reference](../cli.md#rules).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--category` | `<name>` |  |  |
| `--standard` | `cwe\|cert\|misra` |  |  |
| `--rules-dir` | `<dir>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Lists the full lint rule catalog: every rule drag-lint can check, with its
category, and its default enabled/fixable status. Reach for it to see what a
lint run can find, or to filter by category.

The catalog currently holds 289 rules -- 245 enabled by default, 110 marked
fixable -- across 18 categories. Of the 289, 196 are built-in and 93 are
external `.scm` rule files.

### Running it from the CLI

```text
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```

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
