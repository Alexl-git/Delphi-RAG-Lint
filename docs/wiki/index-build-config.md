# index --build-config

A project index is parsed against the project's ACTIVE build config, not a
fixed Release. Reach for it when the index must show the code your IDE
compiles (the `{$IFDEF DEBUG}` branches of a Debug project), or when you want
one specific build indexed on purpose, for example Release for a ship view.

## Running it from the CLI
```
drag-lint index --project <file.dproj> --db <file.sqlite> [--build-config <Release|Debug|name>]
drag-lint index --all [--only <Sec1,Sec2>] [--build-config <Release|Debug|name>]
```
Without `--build-config` the project is parsed with the build the `.dproj`
itself marks as active: the `<Config Condition="'$(Config)'==''">` element the
IDE rewrites when you switch configurations. With `--build-config <name>` that
name wins for this run. A `.dproj` that has no such marker is read through its
`.delphilsp.json` instead (the `-D` defines the IDE wrote for the active
configuration); with neither, the config is Release, as before.

The platform is NOT taken from the project: it stays the section's or the
`--platform` token, so a Win64 database never turns into a Win32 one because a
project marker says so.

## What it records
The indexer fingerprint of a PROJECT database gains two limbs:
```
v=<extractor>;schema=<n>;pp=1;plat=win64;cfg=debug;defs=0de0f2cd
```
`cfg` is the lowercased config name and `defs` is the first 8 hex digits of the
SHA-1 of the sorted define set. When the define set came from `delphilsp.json`
there is no named config, and the limb is the literal `cfg=<json>`. Switching
the active config, or editing the defines of a config, changes the fingerprint,
so the next `index` run re-parses exactly that database
(`Indexer changed since this DB was built`). A line on stderr names the cause:
`index: defines cfg=Debug source=dproj defs=0de0f2cd`.

`index --all --dry-run` (text and `--json`) names the config per section too (`defines cfg=.. source=.. defs=..`;
JSON keys `cfg` and `defs`, empty for library / folder sections), so the cause of a coming re-parse is
visible before the run.

Library and folder databases have no `.dproj`, carry no `cfg=`/`defs=` limbs and
keep a byte-identical fingerprint.

## What it needs
A `.dproj` (via `--project`, or a manifest section whose `include` names one).
No flag is needed for the default behaviour.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

## Example
Illustrative only:
```
drag-lint index --project C:\Projects\MyApp\MyApp.dproj --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --build-config Release
```
This indexes MyApp as its Release build even while the IDE has Debug active,
and re-parses the database the next time the choice changes.
