# Run Lint All (Full Report)

Runs the full rule catalog (178 rules, 152 on by default across 16 categories,
22 auto-fixable) against a project's indexed code and reports every surviving
finding. Reach for it as the overall project health check.

## Running it from the CLI
```
drag-lint lint-all [--db <file.sqlite>] [--project <.dproj>] [--disable id,...] [--output <report.txt>] [--json] [--quiet] [--lint-third-party]
```
`--project <.dproj|.dpr>` reports only on the units that project compiles (its
compile closure + their `.dfm` siblings) -- use it when one folder holds
several projects, or when the DB spans more than the project you are
reviewing. `--quiet` suppresses per-file progress lines written to stderr.
`--lint-third-party` restores the old unscoped whole-index count instead of
only the project's own roots. `--disable id,...` turns off specific rule ids;
`--output` writes the report to a file; `--json` emits JSON.

The shared Output/CI flags also apply: `--format sarif`, `--fail-on <level>`,
`--config <file>`, `--enable id1,id2`, `--profile <name>`, `--baseline <file>`,
`--write-baseline <file>`.

## Reaching it in the IDE
drag-lint > Code Quality > Run Lint All (Full Report)...

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint lint-all --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --output report.txt
```
This would report every surviving finding across `MyApp`'s own compile
closure and write it to `report.txt`.
