---
id: project-facts
title: project-facts
summary: "Report what the build does: defines that are on and what sets each, imports, output paths and packages"
product: DL
group: compiler
order: 90011
since: 1.20.0-alpha
status: shipped
updated: 1.20.0-alpha
---

# project-facts

Report what the build does: defines that are on and what sets each, imports, output paths and packages.

## How to run it

```text
drag-lint project-facts --dproj PATH [--platform win32|win64] [--config Release|Debug] [--db PATH] [--json] (what the BUILD does: defines ON and what sets each, <Import>s, output paths, packages; flags a post-processor define with no build step imported)
```

Full flag list: [project-facts in the CLI reference](../cli.md#project-facts).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--dproj` | `PATH` |  |  |
| `--platform` |  |  |  |
| `--config` |  |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
