# uses-recover

Finds the units a project uses that have **no source** in any index -- a vendor library
shipped as compiled units only -- and recovers their `uses` edges from the C++Builder `.hpp`
headers the vendor ships beside them. A dcc map file of the project, when given, says which of
those units the linker actually pulled in, and names the linked units no header reaches (the
library's implementation-only dependencies).

No `.dcu` is ever read (owner ruling x2, 2026-11-08). Nothing is written: every database is
opened read-only. Design: `docs\superpowers\specs\2026-11-08-uses-recover.md`.

## Running it from the CLI

```
drag-lint uses-recover --db <db> --hpp-dir <dir>... [--library-db <db>...] [--map <file.map>] [--json]
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

A unit name matches a file by base name, case-insensitive; Delphi's default unit scopes
(`System.`, `Vcl.`, `Winapi.` ...) are tried for a bare name such as `SysUtils`. `System` and
`SysInit` are dropped from every header (every unit has them).

## What it prints

* `units` -- each sourceless unit with a header: `reach` (`direct` = the project uses it,
  `header` = only another header includes it), `used_by`, the `header` path, `in_map`, and its
  `uses` edges, each `indexed`, `library` or `sourceless`. Sourceless targets are followed.
* `no_header` -- sourceless units no header folder has; nothing is guessed for them.
* `map_only` -- linked units that are neither indexed, library nor reached by a header.

A header lists the INTERFACE uses only. A unit with no code or data has no `M=` row, so
`in_map: false` means "not seen in the map", not "not linked".

Exit 0 = report printed (zero units included); 2 = no `--db` / `--hpp-dir`, or a DB, folder or
map that is missing or unreadable; 3 = unknown flag.

## Measured (2026-11-08)

The ORM3 CLIENT index (copy) with the Win32 library DB and the EurekaLog, DevExpress and RTL
header folders: 22 sourceless units used directly (all EurekaLog plus the `WinProcs` / `WinTypes`
aliases); 20 recovered from headers, 43 more reached through them, 465 edges, in 2.2 s. The two
aliases stay in `no_header` (unit aliases are not resolved yet).

## Reported, not stored

Recovered edges are reported and never written into the index: storing them is resolver surface,
designed in the spec's "write path" for an extractor/resolver bump.
