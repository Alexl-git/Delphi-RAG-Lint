# project-context

Writes, or checks, `<ProjectBase>.dlcontext.json` beside a Delphi project: the
active **platform**, **config** and the complete effective **define set**, plus
the SHA-1 of the `.dproj` it was derived from.

## Why

A language server or tool that opens a loose unit has to guess which platform and
configuration the project is built for. The context file states it. It is read by
the LSP (nearest `*.dlcontext.json` above the unit) and written either by this
verb or by the small setup exe when only a `.dpr` exists.

## Running it

```
drag-lint project-context --project C:\X\App.dproj                       # active platform + config from the .dproj
drag-lint project-context --project C:\X\App.dproj --platform Win32 --config Release
drag-lint project-context --project C:\X\App.dproj --check               # exit 1 + reason when missing or stale
drag-lint project-context --project C:\X\App.dproj --json                # also prints the context
drag-lint project-context --project C:\X\App.dpr --platform Win64 --config Debug   # no .dproj: built-ins
```

`--out <file>` writes somewhere other than beside the project.

## Exit codes

| code | meaning |
|---|---|
| 0 | written, or `--check` found a fresh file |
| 1 | `--check`: the file is missing, unreadable, or stale (the `.dproj` SHA-1 differs, or the platform/config you asked for differs) |
| 2 | usage: no `--project`, file not found, or a `.dpr` with no `.dproj` and no `--platform`/`--config` ("run dl-project-setup.exe or pass --platform/--config") |

## File shape (schema 1)

`schema`, `generatedBy`, `generatedAt`, `project`, `source {file, mtime, sha1}`,
`platform`, `config`, `targetCompiler` (optional, carried only), `defines`
(lowercased; exactly what the define resolver yields for that platform and
config), `searchPath`, `namespaces`, `unitAliases`, `libraryDb`, `libraryRoots`,
`projectDb`. UTF-8 without BOM.

A context whose source is a `.dpr` is never stale. Only Win32 and Win64 have
define sets today; another platform name is kept but gets the Win64 built-ins.

## Central defaults

`%LOCALAPPDATA%\drag-lint\context-defaults.json` (override: environment variable
`DRAGLINT_CONTEXT_DEFAULTS`) holds per-user fallbacks: `platform`, `config`,
`targetCompiler` and per-platform `libraries`. Readers tolerate its absence.