---
id: uses-recover
title: uses-recover
summary: Recovers the uses edges of units that ship without source, from the vendor's .hpp headers and a dcc map; never reads a .dcu; --apply stores them in the index
product: DL
group: search-navigation
order: 20036
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# uses-recover

Recovers the uses edges of units that ship without source, from the vendor's .hpp headers and a dcc map; never reads a .dcu; --apply stores them in the index.

Read this when a project uses a library shipped as compiled units only and you want to know what those units depend on. uses-recover lists every unit the index uses but has no source for, reads its interface uses from the C++Builder header the vendor ships, follows the units those headers name and, given a dcc map, says which the linker pulled in. --project resolves unit aliases first; --apply stores the result so cycles, impact and the uses graph see past the library. No .dcu is read.

## How to run it

Full flag list: [uses-recover in the CLI reference](../cli.md#uses-recover).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<db>` |  |  |
| `--hpp-dir` | `<dir>` |  |  |
| `--library-db` | `<db>` |  |  |
| `--map` | `<file.map>` |  |  |
| `--project` | `<x.dproj>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Finds the units a project uses that have **no source** in any index -- a vendor library
shipped as compiled units only -- and recovers their `uses` edges from the C++Builder `.hpp`
headers the vendor ships beside them. A dcc map file of the project, when given, says which of
those units the linker actually pulled in, and names the linked units no header reaches (the
library's implementation-only dependencies).

No `.dcu` is ever read (owner ruling x2, 2026-11-08). By default nothing is written: every database is
opened read-only. `--apply` (1.49) stores what was recovered in the project index; see below.
Design: `docs\superpowers\specs\2026-11-08-uses-recover.md`.

### Running it from the CLI

```text
drag-lint uses-recover --db <db> --hpp-dir <dir>... [--library-db <db>...] [--map <file.map>]
                       [--project <x.dproj>] [--apply] [--json]
```

* `--db` -- the project index. Every `unit_uses` row whose target has no file is a candidate.
* `--hpp-dir` -- a folder of `.hpp` headers (not recursive; repeatable; the first folder that has
  a header wins). DevExpress ships them in `DevExpress\VCL\Library\RS37`, EurekaLog in
  `EurekaLog 7\Lib\<platform>\<config>\Studio37`. Embarcadero's own RTL/VCL headers exist only
  when the C++Builder personality is installed.
* `--library-db` -- a platform library index (repeatable). A unit with source there is `library`,
  not sourceless. Without it every RTL unit reads as sourceless.
* `--map` -- a dcc map of the project (`-GS` segments or `-GD` detailed). Each `M=<unit>` row is a
  linked unit.
* `--project` -- the project's `.dproj`. Its `DCC_UnitAlias` entries (every one, build conditions
  ignored) and then the aliases the Delphi targets add on Windows (`WinTypes` / `WinProcs` =
  `Winapi.Windows`, `DbiTypes` / `DbiProcs` / `DbiErrs` = `BDE`, `Generics.*`) are applied to the
  project's own `uses` names: a used alias is classified, and followed, by its target. Each one is
  listed under `aliases`.
* `--apply` -- WRITE the result into `--db` (see "Storing the edges").

A unit name matches a file by base name, case-insensitive; Delphi's default unit scopes
(`System.`, `Vcl.`, `Winapi.` ...) are tried for a bare name such as `SysUtils`. `System` and
`SysInit` are dropped from every header (every unit has them).

### What it prints

* `units` -- each sourceless unit with a header: `reach` (`direct` = the project uses it,
  `header` = only another header includes it), `used_by`, the `header` path, `in_map`, and its
  `uses` edges, each `indexed`, `library` or `sourceless`. Sourceless targets are followed.
* `no_header` -- sourceless units no header folder has; nothing is guessed for them.
* `map_only` -- linked units that are neither indexed, library nor reached by a header.
* `aliases` -- with `--project`: each used alias, its target (`to`) and the target's status.
* `applied` -- with `--apply` only: `files` (header rows written), `uses` (their `unit_uses` rows),
  `bound` (`unit_uses` rows now pointing at a header).

A header lists the INTERFACE uses only. A unit with no code or data has no `M=` row, so
`in_map: false` means "not seen in the map", not "not linked".

Exit 0 = report printed (zero units included); 2 = no `--db` / `--hpp-dir`, or a DB, folder,
map or `--project` file that is missing or unreadable, or `--apply` on an index whose schema is
not current; 3 = unknown flag.

### Measured (2026-11-08)

The ORM3 CLIENT index (copy) with the Win32 library DB and the EurekaLog, DevExpress and RTL
header folders: 22 sourceless units used directly (all EurekaLog plus the `WinProcs` / `WinTypes`
aliases); 20 recovered from headers, 43 more reached through them, 465 edges, in 2.2 s. Without `--project`
the two aliases stay in `no_header`; with it they classify as `library` (`Winapi.Windows`).

### Storing the edges (`--apply`)

`--apply` writes the recovered units into `--db` (the library DBs are never written):

* one `files` row per recovered header: `path` = the `.hpp`, `language = 'hpp'`, no symbols;
* its `#include` lines as `unit_uses` rows, `section = 'interface'`, `origin_path` = the header
  (`System`, `SysInit` and the unit itself dropped, as in the report);
* then the uses resolve pass runs: a project row `uses EBase` now has `target_file_id` = the
  `EBase.hpp` row, and header rows point at each other.

So `cycles`, `impact`, `graph` and the other `unit_uses` readers walk through the library
instead of stopping at its edge. A re-index keeps the rows and the binding (the uses pass binds
a still-unbound name to a header row by exact name; an indexed `.pas` of that name always wins).
Running `--apply` again is idempotent; a header no longer recovered (its unit got source, or
the folder was dropped from the command line) loses its row. A run without `--apply` writes
nothing, and the report reads the same before and after `--apply`.

Not stored: the map facts, unit aliases (a `uses WinProcs` row stays unbound), and symbols from
the header's declarations (a later phase). Edges are interface uses only.

Measured 2026-11-09 on an ORM3 CLIENT copy (same header folders, `--project`): 63 header rows, 465`
unit_uses` rows, 325 rows bound to a header (25 of them the project's own), in 4 s; `WinProcs` /`
`WinTypes` classify as `library`. A following `index --resolve-only` kept all 325 bindings and changed`
no call edge (certain 24953 / ambiguous 4277 identical, same ref and target checksums).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
