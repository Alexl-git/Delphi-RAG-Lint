# uses-recover: dependencies of units that ship without source (no .dcu parsing)

Status: design + phase 1 (read-only verb). Lane 148-HP, 2026-11-08. Supersedes the reader path of
`docs\superpowers\specs\2026-11-06-dcu-index.md` (branch `lane/146-x2` 01085ace, reference only).

## Owner ruling this spec obeys

**x2 = NO .dcu parsing of any kind.** Dependency facts come only from text the vendor or the
compiler hands over for reading: C++Builder `.hpp` headers and dcc map output. The x2 `.dcu`
import-table reader is not reused, copied or called. No vendor binary is opened by this verb or
its guard.

## Problem

drag-lint indexes source. A project that uses a library shipped as compiled units only (no
`.pas`) has `unit_uses` rows whose target has no file: the edge stops at the library's edge, and
`query`, `find-unit`, `graph`, `impact` and the uses-cycle rules see nothing past it. The 2026-11-08
`drag-lint.sqlite` index has 1426 of 3164 `unit_uses` rows with `target_file_id IS NULL`, nearly
all RTL units the LIBRARY index has source for -- so "no target in this DB" is not "sourceless":
the library DB must be subtracted first.

## Options

| | Source | Gives | Footing | Cost |
|---|---|---|---|---|
| A | Vendor `.hpp` headers (`#include <X.hpp>` list) | The unit's INTERFACE uses, as plain text | Best: text shipped to be read | S: a line scan |
| B | dcc detailed map (`-GD`, also `-GS`) | The LINKED unit set (`M=<unit>` segment rows): closure membership, no edges | Good: normal compiler output | S: a line scan; needs one build of the project |
| C | dcc `-M` / `--depends` | `-M` is "make modified units" (a build mode, no output to read); `--depends` writes a `.d` with every `.dcu` path of the closure, no per-unit edges | Good | Same facts as B with less structure |
| D | Own `.dcu` reader | Interface + implementation uses | **Ruled out (x2)** | -- |

Measured: `DevExpress\VCL\Library\RS37` ships 1867 `.hpp` for 1865 `.dcu`; `cxGrid.hpp` lists 30
`#include <...hpp>` lines between `#pragma delphiheader begin` and `namespace Cxgrid`, and its
include list matched the x2 prototype's interface-uses read exactly (x2 spec, option A). A fixture
built with `dcc32 -JPHNE` (this lane) shows the header names every interface unit -- including
`System` and `SysInit`, which the compiler adds -- and NO implementation unit. A `-GD` map of a probe
program lists one `M=<unit>` row per code/data segment of every linked unit, implementation-only
units included.

## Chosen

**A for edges, B for closure confirmation. C is documented, not built (B carries the same facts with
structure). D stays ruled out.**

Phase 1 (this lane): a READ-ONLY verb

    drag-lint uses-recover --db <db> --hpp-dir <dir>... [--library-db <db>...] [--map <file.map>] [--json]

1. Sourceless units = distinct `unit_uses.unit_name` whose target is not a `.pas/.dpr/.dpk` file of
   `--db` nor of any `--library-db` (matched by file base name, case-insensitive; a dotted
   default-scope prefix such as `System.` is tried for a bare name like `SysUtils`).
2. For each, find `<unit>.hpp` (or `<scope>.<unit>.hpp`) in the `--hpp-dir` list (first hit wins),
   read the `#include <X.hpp>` / `#include "X.hpp"` lines: each is an `interface` edge.
   `System` and `SysInit` are dropped (implicit in every unit).
3. Classify each target `indexed` (source in `--db`), `library` (source in a `--library-db`) or
   `sourceless`; a sourceless target with a header is followed (breadth-first), reach `header`.
4. `--map`: every `M=<unit>` of the map. Each reported unit gets `in_map` true/false;
   `map_only` = linked units that are neither indexed, library, recovered nor System/SysInit --
   the implementation-only dependencies a header cannot show.
5. Exit 0 = report printed (zero sourceless units included); 2 = usage, missing/unreadable DB,
   header dir or map; 3 = unknown flag (the shared `error[unknown-flag]` exit every self-parsing
   verb uses). Nothing is written: both DBs open read-only.

## The write path (designed in 148; BUILT in 149 HW -- see "149 HW: as built")

Writing recovered edges changes what the index holds and what the resolver reads, so it is a
`DRAGLINT_EXTRACTOR_VERSION` + resolver review and a re-parse. Design for the bump wave:

- A synthetic `files` row per recovered unit: `path = <hpp path>`, `language = 'hpp'`,
  `origin = 'header'`, no symbols in phase 2 (symbols from the header's declarations are phase 3).
- `unit_uses` rows from that file with `section = 'interface'`, `origin_path = <hpp>`, so
  `graph`, `impact` and the cycle rules walk through it; the existing project rows get
  `target_file_id` = the synthetic file.
- Map facts are not edges: a `unit_facts`-style row `linked_in_map = 1` per unit, or nothing.
- Fingerprint units (expected): `DRagLint.Index.*` (the walker that would admit `.hpp`),
  `DRagLint.Storage.SQLite.pas` (rows), `CallResolver.pas` only if `target_file_id` feeds
  resolution (it does for unit-scoped lookups: treat as resolver surface).
- Ledger: `NEXT-BUMP HP uses-recover write path ...` (148 LEDGER, 2026-11-08).

## 149 HW: as built (lane 149-HW, 2026-11-09)

`uses-recover --apply` (OFF unless given). Deviations from the design above, each reversible:

- **No `files.origin` column.** The schema is EX2's alone in 149; `files.language = 'hpp'` is the
  marker (no indexer writes that language). `unit_uses.origin_path` = the header, `include_line`
  0, `section` 'interface', coordinates = the `#include` line inside the header.
- **The binding lives in the uses resolve pass, not in the writer.** `ResolveUnitUseTargets`
  clears and recomputes `target_file_id` on every index run, so a value written once by the verb
  would be wiped by the next re-index. New RULE C there: after rules A/B, a name still NULL binds
  to a header row of the same stem (exact, lower-cased; the reader already chose the canonical
  scoped name when it wrote the row). NULL rows only, so an indexed `.pas` always wins. A DB
  without header rows runs no extra statement and prints no extra log line.
- **One writer:** `TSQLiteSymbolStore.ReplaceHeaderUnits` replaces the whole header set (a header
  no longer recovered is deleted through `DeleteFilesByIds`), then upserts by path and rewrites
  each header's uses in one transaction. The verb then runs `ResolveUnitUseTargets`.
- **The read report is invariant under --apply:** rows bound to a header row still count as uses
  of a sourceless unit, and a header row's own rows are not the project's.
- **CallResolver.pas is not edited.** Its unit-scope map reads `GetUnitScopeEdges` (direct
  `file_id -> target_file_id` pairs), which now includes header targets with no code change;
  header rows carry no symbols, so no candidate set changes. Measured: CLIENT A/B (REPORT).
- **Map facts are not stored** (no `unit_facts` row): nothing reads them yet.
- **Unit aliases (read side):** `--project <x.dproj>` reads every `DCC_UnitAlias` (conditions
  ignored: the union) and then the Windows defaults of `CodeGear.Common.Targets` (Studio 37.0:
  `Generics.Collections/Defaults`, `WinTypes`/`WinProcs` = `Winapi.Windows`, `DbiTypes`/`DbiProcs`/
  `DbiErrs` = `BDE`); first spelling wins. Applied to the project's own uses names only (headers
  name real units). Not written: a `uses WinProcs` row stays unbound.
- **Eviction:** header rows live outside every sweep root unless a `--hpp-dir` sits under a project
  scope root; then a later `index --project` is expected to evict them as out-of-scope (read from
  `EvictOutOfScopeFiles`, not measured; re-run `--apply`).
- Fingerprint units: `src\index\DRagLint.Index.UsesRecoverWrite.pas` (new),
  `src\storage\DRagLint.Storage.SQLite.pas` (ReplaceHeaderUnits + rule C). Guard:
  `tests\autotest\run_uses_recover_write_guard.ps1`.

## Assumptions the owner can reverse

- The verb ships documented (status `shipped`, 1.47.0-alpha), not `internal`: it reads only text.
- Matching is by file base name = unit name (true for Delphi units); a unit whose file name
  differs from its unit name is misclassified as sourceless.
- The default unit-scope list is Delphi's default project list (`Winapi; System.Win; Data.Win;
  Datasnap.Win; Web.Win; Soap.Win; Xml.Win; Bde; System; Xml; Data; Datasnap; Web; Soap; Vcl;
  Vcl.Imaging; Vcl.Touch; Vcl.Samples; Vcl.Shell`); no `--scope` flag yet.
- Headers are trusted as generated: no `#if` evaluation, every `#include <*.hpp>` line counts.
- A unit with no code or data segment (types/consts only) has no `M=` row, so `in_map=false`
  does not prove it is unlinked; the report says "not seen in map", not "not linked".
- Units used with no header anywhere are listed under `no_header`, never guessed at.
