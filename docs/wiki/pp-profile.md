# pp-profile

Diagnostic that prints the resolved preprocessor define profile for a
project, one symbol per line. Reach for it to see exactly which defines
are active for a given project/platform/config combination, before
trusting a `preprocess-file` or compile result.

## Running it from the CLI
```
drag-lint pp-profile [--dproj PATH] [--platform win32|win64] [--config Release|Debug]
```
`--dproj PATH` selects the project. `--platform` selects `win32` or
`win64`. `--config` selects `Release` or `Debug`.

The profile is the platform built-ins plus the `DCC_Define` of FOUR `.dproj`
PropertyGroups, read in MSBuild order: `Base`, `Base_<Platform>`, `Cfg_N` and
`Cfg_N_<Platform>`. The two platform groups are read since v1.17.0-alpha
(extractor 1.18.0-alpha); before that a define set ONLY per platform -- the
usual home of `EUREKALOG` -- was silently inactive, so its `{$IFDEF}` branches
were blanked and units used only inside them fell out of the project closure.
The same profile drives every `index` preprocess and every project closure, so
what this prints is what the indexer parses.

This is labeled a "diagnostic" in the CLI banner -- it is a troubleshooting
tool, not a daily driver.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## What it needs
No index required -- `pp-profile` takes no `--db` flag; it resolves the
define profile directly from the project file.

## Example
Illustrative only:
```
drag-lint pp-profile --dproj C:\Projects\MyApp\MyApp.dproj --platform win64 --config Debug
```
This would print every define active for `MyApp.dproj` under Win64/Debug,
one per line.
