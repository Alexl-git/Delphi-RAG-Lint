---
id: drag-lint-project-rules
title: "drag-lint: Project Rules"
summary: Right-click a project in the Project Manager to make it the active project and open its Lint Options tab in the drag-lint dock
product: DL
group: linting
order: 30006
since: 0.95.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# drag-lint: Project Rules

Right-click a project in the Project Manager to make it the active project and open its Lint Options tab in the drag-lint dock.

Read this when you want to review or change the lint rules of one project: in the Project Manager right-click the project and choose drag-lint: Project Rules..., which activates it and opens its Lint Options tab in the drag-lint dock. From the command line, drag-lint rules lists the whole rule catalog (not per project) and needs no index.

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

* Right-click in the Project Manager: **drag-lint: Project Rules**
   1. Open the Project Manager
   2. Right-click the project and choose drag-lint: Project Rules...
   3. The lint rule catalog is shown

## Details

Shows the catalog of lint rules in the context of a specific project. Reach
for it when you want to see which rules exist (and their categories)
starting from the Project Manager rather than the drag-lint main menu.

### Running it from the CLI

The feature map lists the underlying verb as `rules`. From the usage
banner:

```text
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```

Lists every lint rule (catalog).

### What it needs

No index needed, per the feature map's Index column.

### Example

Illustrative:

```text
drag-lint rules --category naming --json
```

This would print the catalog of naming-category rules as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
