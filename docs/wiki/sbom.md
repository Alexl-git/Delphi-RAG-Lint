# sbom

Writes a **software bill of materials** for one Delphi project as a CycloneDX 1.6 JSON document:
the application, one component per library the project's units reach, and the dependencies
between them. It is read from the index, so no compiler runs and nothing is written but the
document.

This is the **v1 slice (1.56)**: the *source closure*. What it cannot see is listed under
[Limits of v1](#limits-of-v1) and is stated inside every document it writes.

## Running it from the CLI

```
drag-lint sbom --project <x.dproj> [--out <file.cdx.json>] [--exe <delivered.exe>] [--app-version <v>]
               [--db <project.sqlite>] [--library-db <db>|none]... [--catalogue <file.json>]
```

* `--project` -- the project's `.dproj` (required). Its base name is the application's name.
* `--out` -- the file to write (UTF-8, no BOM). Without it the document goes to stdout.
* `--exe` -- the delivered executable. Its SHA-512 is written to `metadata.component.hashes`.
  The verb does not check that this file was built from the indexed sources: you state that.
* `--app-version` -- the application's version, written as given. Without it no version is claimed.
* `--db` -- the project index. Default: the manifest section that owns the project, else
  `<project folder>\_D-RAG\<project name>.sqlite`. No index = exit 2 with the `index` command to run.
* `--library-db` -- a library index (repeatable). Default: the manifest's library index for the
  platform the project index was built for. `--library-db none` reads none.
* `--catalogue` -- your own library catalogue. Default: `rules\sbom-libraries.json` beside the engine.

Index the project first (`drag-lint index --project <x.dproj>`): the document is exactly as
current as the index.

## What ends up in the document

| Part | Content |
|---|---|
| `metadata.component` | the application: every first-party unit (`drag-lint:unit` properties), the version and hash you gave |
| `components` | one `library` component per unit group, with supplier, name, version, licence and purl from the catalogue |
| `dependencies` | one entry per component and the application; `dependsOn` = the groups its units use |
| `compositions` | `incomplete` -- see the limits |
| `metadata.properties` | `drag-lint:sbom:slice` = `v1`, `drag-lint:sbom:scope`, `drag-lint:sbom:libraryIndex` |

**Which units.** Every unit file of the project index. Each `uses` row is followed: to a project
unit, else to a unit of a library index -- and from there through that library's own `uses`
rows, so a library that only another library uses is listed too -- else it is a unit without
source. A bare name (`SysUtils`) is completed with the default unit aliases and the project's
unit-scope names. `System` and `SysInit`, which no `uses` clause names, are added for every unit.

**Which group.** For each unit, the first that applies:

1. it has a source path and a catalogue row's `paths` match it: that library;
2. it has no source and a catalogue row's `units` match its name: that library, marked
   `drag-lint:attribution` = `unit-name` (name-only evidence);
3. it is first-party -- under the project folder, listed in the `.dproj`, or matched by a row with
   `"firstParty": true` -- : the application;
4. it has a source path: one component per **directory**, supplier `unknown supplier`;
5. it has no source: one component per unit, supplier `unknown supplier`.

Nothing is dropped. Every component without a catalogue row is also named in a `NOTE:` line on
stderr with its directory, so you know which rows to add.

## The library catalogue

`rules\sbom-libraries.json` is a plain file meant to be edited. Each row:

```json
{
  "key": "spring4d",
  "name": "Spring4D",
  "supplier": "Spring4D Team",
  "licenseId": "Apache-2.0",
  "purl": "pkg:bitbucket/sglienke/spring4d",
  "paths": ["\\Spring4D\\"],
  "units": ["Spring", "Spring.*"]
}
```

* `paths` -- file masks (`*`, `?`), case-insensitive, matched anywhere in a unit's full path.
* `units` -- unit-name patterns (a trailing `*` is a prefix); used only for units without source.
* `version` -- a fixed text. `versionFromPath` -- a regular expression whose first group is the
  version, read from the unit paths (the shipped Embarcadero rows read `37.0` from
  `...\Studio\37.0\...`). With neither, no version is claimed.
* `licenseId` (SPDX id), `licenseExpression` (SPDX expression) or `licenseName` (free text).
* `cpe`, `purl` -- optional identifiers.
* `"firstParty": true` -- fold the matching units into the application (your own shared source
  outside the project folder).

The first matching row wins. A row with an unknown member, no `key` / `name`, or neither `paths`
nor `units` is an error (exit 1) -- a typo never silently disables a row.

The shipped rows cover the RAD Studio source tree, Indy, DUnit / DUnitX, DevExpress VCL, Spring4D,
JCL / JVCL, OmniThreadLibrary, FastMM4 and the TurboPack Orpheus / SysTools / Abbrevia libraries.
**Check versions and licences against what you actually ship** -- the catalogue states what is
usual for a library, not what your contract says.

## Limits of v1

The document is built from source, before the build. It therefore says `lifecycles: pre-build`
and `compositions: incomplete`, and it does not list:

* units linked from compiled units (`.dcu`) that no indexed source names -- there is no MAP file
  input yet (`--map` is a later slice and is not accepted);
* runtime packages (`.bpl`) and DLLs the application loads;
* hashes of anything but the one `--exe` file.

There is no BSI TR-03183-2 profile (`--bsi`) and no VEX output yet. Without a library index
(`--library-db none`, or none configured) library units are attributed by name only and their
own dependencies are not walked; the document and a stderr `NOTE:` say so.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | document written |
| 1 | an index, the catalogue or the `--exe` file cannot be read, or `--out` cannot be written; no document |
| 2 | no `--project`, the project file is missing, or it has no index |
| 3 | unknown flag (including `--map` and `--bsi` in this version) |

## Checked by

`tests\autotest\run_v156_SBOM1.ps1` -- a fixture project with a catalogued library, a library
reached only transitively, a library root without a row, units without source, and the
CycloneDX 1.6 JSON schema (vendored in `tests\fixtures\sbom\schema`).
