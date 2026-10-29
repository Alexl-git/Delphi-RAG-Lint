---
id: init-wiring
title: "init: one command from a project to a wired AI client"
summary: Registers a project in the manifest, indexes it, finds its index and wires Claude Code, VS Code and Cursor to serve it, in one command
product: DL
group: editor-integration
order: 110009
since: 1.38.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# init: one command from a project to a wired AI client

Registers a project in the manifest, indexes it, finds its index and wires Claude Code, VS Code and Cursor to serve it, in one command.

Run drag-lint init --project plus your project file once per project (try --dry-run first) and an AI client can query that project's index: it registers the project, builds the index, then points Claude Code, VS Code and Cursor at it. It only runs existing verbs, so each step can also be run by hand.

## How to run it

```text
drag-lint init --project <file.dproj> [--dry-run] [--home-dir <dir>] [--appdata-dir <dir>]
```

Example:

```text
--project C:\Projects\MyApp\MyApp.dproj --dry-run
```

Full flag list: [init in the CLI reference](../cli.md#init).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<file.dproj>` |  |  |
| `--dry-run` |  |  |  |
| `--home-dir` |  |  |  |
| `--appdata-dir` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

**Registers a project, indexes it and points Claude Code, VS Code and Cursor at its index**, so an AI client can query it straight away. The verb is `drag-lint init`; it adds no logic of its own, it runs four existing verbs in order.

### Running it

```text
drag-lint init --project C:\Projects\MyApp\MyApp.dproj --dry-run   (print the four commands, run nothing)
drag-lint init --project C:\Projects\MyApp\MyApp.dproj
```

### The four steps

1. `register-project <proj> --apply` -- adds the project's section to the manifest (a no-op when it is already registered).
2. `index --project <proj>` -- builds the project's index.
3. `resolve-dbs --project <proj>` -- finds the index that owns the project.
4. `mcp-config --all --db <that index>` -- writes the MCP entry for Claude Code, VS Code and Cursor ([Register the MCP server](mcp-config-writer.md)); a client that is not installed is skipped.

Each step's output is echoed under a `step n/4` heading. A failing step stops the run and its exit code is the verb's (a step that could not start, or timed out after an hour, is 1). Every step is safe to repeat, so a second `init` changes nothing.

### Flags

* `--project <file.dproj>` -- required; the project file must exist (usage error, exit 2, otherwise).
* `--dry-run` -- prints the four commands and runs none of them: nothing is registered, indexed or written.
* `--home-dir <dir>` / `--appdata-dir <dir>` -- passed to step 4: where the client files are looked for (used by tests; the defaults are your user profile and `%APPDATA%`).

Tests: `tests\autotest\run_init_verb.ps1` (scratch engine copy and scratch home; it asserts the real client files are unchanged).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
