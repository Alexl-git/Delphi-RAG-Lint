# T-22 apply report -- MicroniteTests + PdfOcrImportTests (2026-10-26, lane t22)

REPORT ONLY. Nothing was applied to the real projects: no `--apply`, no `--db`, no reindex.
The controller applies after review.

- Engine: the lane worktree build (`<worktree>\src\cli\Win64\Debug\drag-lint.exe`). It carries
  the T-22 change: the project-or-library verdict, `--to library`, and library `include` roots.
- Manifest: a COPY of `third_party\dll-win64\drag-lint.json` in `C:\TEMP\claude\lanes\t22\`,
  passed with `--config`.
- Checked before and after: the size and mtime of both project DBs and all four project files
  did not change. `MicroniteTests.sqlite` 10768384 B and `PdfOcrImportTests.sqlite` 7745536 B;
  the `.dpr` / `.dproj` files are as of 2026-07-09 and 2026-06-23. No `.bak` was written.

```
drag-lint reconcile-project C:\Projects\DB\ORM3\TESTER\Tests\MicroniteTests.dproj         --config <copy> [--json]
drag-lint reconcile-project C:\Projects\DB\ORM3\TESTER\PdfOcrImport\PdfOcrImportTests.dproj --config <copy> [--json]
```

Ownership: both projects declare `ownRoots: ["..\\.."]` (= `C:\Projects\DB\ORM3`) in
`_D-RAG\drag-lint-project.json`. A unit under ORM3 is a project unit; anything else is third-party.

## Result

| Project | MISSING | project units | third-party | of which `.inc` | extra | stale |
|---|---|---|---|---|---|---|
| MicroniteTests | 48 | 2 | 46 | 1 (`DUnitX.inc`) | 0 | 0 |
| PdfOcrImportTests | 46 | 0 | 46 | 1 (`DUnitX.inc`) | 0 | 0 |

The counts match the earlier read (48 / 46). The verdicts match the owner's ruling exactly:
FlexDateTime and MSCTYPES are project units, and the DUnitX units are third-party.

### MicroniteTests -- what the DEFAULT fix would add to .dpr + .dproj

| Unit | relPath | used by |
|---|---|---|
| FlexDateTime | `..\..\COMMON\FlexDateTime.pas` | Test.FlexDateTime |
| MSCTYPES | `..\..\COMMON\MSCTYPES.pas` | Test.FtrName |

```
drag-lint reconcile-project "C:\Projects\DB\ORM3\TESTER\Tests\MicroniteTests.dproj" --only FlexDateTime,MSCTYPES --apply
```

### Both projects -- what the LIBRARY fix would add to the manifest

Every third-party unit sits in ONE folder: `C:\Projects\DUnitX\Source`. That is 45 `.pas` units
plus `DUnitX.inc`, which is not a unit: it is reported but refused by either write. So the library
fix writes exactly one `"include"` entry into the `Library` section (`"source":
"registry-libraries"`, platforms Win32 + Win64) of the manifest:

```
drag-lint reconcile-project "<either .dproj>" --only <the 45 DUnitX units> --apply --to library [--config <drag-lint.json>]
```

The text report prints this command with the full `--only` list already filled in. Without
`--config` the command writes `drag-lint.json` beside the exe, and mirrors it to the
dll-win32 / dll-win64 twin.

## Rescan after the library fix (simulated on the manifest copy)

`C:\Projects\DUnitX\Source` was added by hand to the copy's `Library` `include` (what
`--apply --to library` writes), and both projects were scanned again:

| Project | MISSING after | remaining |
|---|---|---|
| MicroniteTests | 2 | FlexDateTime, MSCTYPES (the default fix covers these) |
| PdfOcrImportTests | 0 | -- |

`index --all --dry-run --json --platform Win64`: the library plan grows from 148 to 149 roots, so
the next library index (`index --all --only Library`) walks DUnitX on both platforms. Nothing new
surfaced in the rescan.

## For the controller (apply order)

1. MicroniteTests: run the default-fix command above, then `index --project ... --db ...`
   (incremental), and check `files=`. Per PLAN-project-completeness-sweep section 0, these units are
   resolvable and probably already indexed, so `files=` may stay the same. The real gain is IDE
   hygiene.
2. DUnitX: run the library-fix command once, against the real `third_party\dll-win64\drag-lint.json`
   (it mirrors to dll-win32). This is owner ruling 1's "DUnitX -> LIBRARY, Win32 + Win64". Then
   re-index the library for both platforms. That needs the deploy go, and no conversion may run
   while it does.
3. Scan both projects again: expect MISSING 0. lint-all `unit-not-in-library` should then report 0
   on both, and `unit-not-in-dpr` should report 0 on MicroniteTests.
