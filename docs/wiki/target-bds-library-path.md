# Library path of the project's Delphi

`index --project` and `index --all` read a project against the Delphi it targets: not only the defines (`VER<N>0`, `CompilerVersion`), but also the Search Path, Browsing Path, platform list and IDE Environment Variables from that Delphi's BDS registry key, with `$(BDS)` expanding to that Studio's root and `$(BDSCOMMONDIR)` to that Studio's common folder (what its `bin\rsvars.bat` sets; else `%PUBLIC%\Documents\Embarcadero\Studio\<key>`). Reported by Jonathas Paiva (GitHub #13).

## Which key

The same precedence as the defines:

1. `--target-compiler <ver>`
2. the `--project` .dproj's `<ProjectVersion>` (`index --all`: each section's own .dproj, also in `--jobs` children)
3. no target: BDS 37.0, as always

`18.8` maps to CompilerVersion 33, and that to BDS `20.0`, by asking the one mapping `Preprocess.Profile` has.

## What changes for a project on another Delphi

A unit on that Delphi's **Search Path** that the platform library DB does not cover joins the project's closure, searched after the project's own folders, as dcc does:

```
drag-lint index --project App.dproj --platform win32 --db app.sqlite
Library path: BDS 20.0 (target Delphi 10.3)
drag-lint query find-callers --name LibProc --resolved --db app.sqlite
```

These stay out of the closure: folders under that Studio's root or any `\Embarcadero\` folder, and folders on 37.0's library path, which the platform library DB covers. The library DBs are still built from Delphi 13, so a 10.3 project sees 13's RTL symbols.

A project on Delphi 13 is untouched: no tail, no output, the same closure byte for byte.

## When the key is not installed

The run falls back to 37.0 and prints one line:

```
note: library path: target Delphi 10.3 wants BDS 20.0, which is not installed here; using BDS 37.0
```

A key whose `RootDir` folder is gone counts as not installed. `index --project ... --json` ends with one object:

```
{"files":12,"symbols":40,"refs":90,"library_path":{"requested_bds":"20.0","used_bds":"37.0","note":"note: library path: ..."}}
```

`index --all --dry-run --json` has `requested_bds`, `used_bds` and `library_note` on each closure section; `reconcile-project --json` has them at the top level.

No note appears when the project names no target: no .dproj, no `<ProjectVersion>`, or one the table does not map (D5-era and pre-10.1 projects). Those run as before. An explicit `--target-compiler` older than XE6 has no key in the mapping, and says so.

## Which verbs read it

| Reader | Key | Library-path units are |
|---|---|---|
| `index --project`, `index --all`, `--jobs` children, `selftest closure` | the target's | in the closure |
| `reconcile-project`, `unit-not-in-library`, `unit-not-in-dpr`, the `lint` / `lint-all` project scope, autodoc, rename owners | the target's | library: not a project member, no .dpr listing needed |
| `used-unit-not-resolvable` (.dcu search) | the target's, with `--project` or a manifest-owned DB | - |
| `--scan-libraries`, library sections, `library-drift`, `coverage`, `resolve-dbs`, the plugin and config tool | 37.0 | library scope, out of this feature |
| `check-unit` compile, `TStudioEnv` | 37.0 | the compiler drag-lint runs on stays 37.0 |

The LSP and MCP servers read no library path; they read the DB.

## Incremental

The closure is recomputed on every `index --project`, so a library path change alone reaches the next run: added units are indexed and stored callers bind, with no source touched and no `--rebuild`. A folder that LEAVES the path keeps its rows until `--rebuild`, the existing `files > walked` state.

## Tested and not tested

Guards replace the registry with a JSON fixture (`DRAGLINT_TEST_BDS_REGISTRY`, `tests\autotest\run_target_bds_libpath_guard.ps1`). Beyond the fixture, on 2026-11-04 a scratch project with ProjectVersion 20.1 ran against the build box's real Studio 23.0 key: `Library path: BDS 23.0 (target Delphi 12)`, and a unit found only on 23.0's library path joined the closure with its own uses and an include. A Delphi 13 closure is byte-identical before and after the `` change on 3 real projects.

Not tested here:

- a Studio key under `HKLM` / `WOW6432Node` only;
- component installers' path layout on other machines, and how much of it the `\Embarcadero\` rule keeps out;
- the 7 units of the report that came from a different checkout.
