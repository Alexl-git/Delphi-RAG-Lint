---
id: project-context
title: project-context
summary: "Writes or checks the `.dlcontext.json` file beside a project: platform, config and define set, with the .dproj SHA-1 for staleness"
product: DL
group: editor-integration
order: 110019
since: 1.38.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# project-context

Writes or checks the `.dlcontext.json` file beside a project: platform, config and define set, with the .dproj SHA-1 for staleness.

Read this when the language server or a tool must know which platform and configuration a project is built for without guessing. project-context resolves the .dproj (or, for a .dpr with no .dproj, the platform and config you pass) and writes the context file next to the project. --check writes nothing and exits 1 with the reason when the file is missing or stale.

## How to run it

```text
drag-lint project-context --project <x.dproj|x.dpr> [--platform P] [--config C] [--output <file>] [--json] [--check] (writes <base>.dlcontext.json beside the project: platform, config and the complete effective define set, plus the .dproj SHA-1 for staleness; --check writes nothing and exits 1 saying why when the file is missing or stale; a .dpr with no .dproj exits 2 unless --platform and --config are both given)
```

Example:

```text
drag-lint project-context --project C:\X\App.dproj --platform Win64 --config Debug
```

Full flag list: [project-context in the CLI reference](../cli.md#project-context).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--project` | `<x.dproj\|x.dpr>` |  |  |
| `--platform` | `P` |  |  |
| `--config` | `C` |  |  |
| `--output` | `<file>` |  |  |
| `--json` |  |  |  |
| `--check` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Writes, or checks, `<ProjectBase>.dlcontext.json` beside a Delphi project: the
active **platform**, **config** and the complete effective **define set**, plus
the SHA-1 of the `.dproj` it was derived from.

### Why

A language server or tool that opens a loose unit has to guess which platform and
configuration the project is built for. The context file states it. It is read by
the LSP (nearest `*.dlcontext.json` above the unit) and written either by this
verb or by the small setup exe when only a `.dpr` exists.

### Running it

```text
drag-lint project-context --project C:\X\App.dproj                       # active platform + config from the .dproj
drag-lint project-context --project C:\X\App.dproj --platform Win32 --config Release
drag-lint project-context --project C:\X\App.dproj --check               # exit 1 + reason when missing or stale
drag-lint project-context --project C:\X\App.dproj --json                # also prints the context
drag-lint project-context --project C:\X\App.dpr --platform Win64 --config Debug   # no .dproj: built-ins
```

`--out <file>` writes somewhere other than beside the project.

### Exit codes

| code | meaning |
|---|---|
| 0 | written, or `--check` found a fresh file |
| 1 | `--check`: the file is missing, unreadable, or stale (the `.dproj` SHA-1 differs, or the platform/config you asked for differs) |
| 2 | usage: no `--project`, file not found, or a `.dpr` with no `.dproj` and no `--platform`/`--config` ("run dl-project-setup.exe or pass --platform/--config") |

### File shape (schema 1)

`schema`, `generatedBy`, `generatedAt`, `project`, `source {file, mtime, sha1}`,
`platform`, `config`, `targetCompiler` (optional, carried only), `defines`
(lowercased; exactly what the define resolver yields for that platform and
config), `searchPath`, `namespaces`, `unitAliases`, `libraryDb`, `libraryRoots`,
`projectDb`. UTF-8 without BOM.

A context whose source is a `.dpr` is never stale. Only Win32 and Win64 have
define sets today; another platform name is kept but gets the Win64 built-ins.

### Central defaults

`%LOCALAPPDATA%\drag-lint\context-defaults.json` (override: environment variable
`DRAGLINT_CONTEXT_DEFAULTS`) holds per-user fallbacks: `platform`, `config`,
`targetCompiler` and per-platform `libraries`. Readers tolerate its absence.

The RAD Studio plugin writes `libraries.<Platform>.libraryDb` for Win32 and Win64 each time
the IDE starts: the `library-<Platform>.sqlite` under the manifest `indexes.outDir`, only when
that file exists. It changes nothing else in the file (your `platform`, `config`,
`targetCompiler` and `libraryRoots` stay), does not rewrite an unchanged value, and leaves a
file that is not valid JSON alone. Each outcome is in the plugin log under `ctxdefaults`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
