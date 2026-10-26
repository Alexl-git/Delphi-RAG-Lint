# Reconcile Project Members (.dpr/.dproj)

Lists every unit a project uses that is neither a project member (in the
`.dpr` / `.dproj`) nor in the library, says whose unit each one is, and fixes
it one of two ways. It can also re-scan and recompile every member to heal the
index and findings. Reach for it after moving or adding units by hand, or when
lint reports `unit-not-in-dpr` or `unit-not-in-library`.

## Running it from the CLI
```
drag-lint reconcile-project <App.dpr|.dproj> [--apply] [--to project|library] [--only <unit,...>] [--db <db>] [--full] [--json] [--config <path>]
```
Without `--apply` the command only reports. `--only` narrows MISSING (and so
what `--apply` writes) to the units you name. `--db` also heals the index and
findings for every project member (re-scan + recompile) without editing the
`.dpr`; `--full` forces the recompile even when nothing looks incoherent.

## Project unit or library unit
A unit counts as **in the library** when it sits under a registry library path
(the IDE's Library path) or under a folder that the manifest's library section
(`"source": "registry-libraries"` in `drag-lint.json`) lists in `"include"`.
Such units are never listed.

Every other MISSING unit gets a verdict from the project's own roots (the
`ownRoots` in `<project>\_D-RAG\drag-lint-project.json`, or else the project
folder):

| Verdict | Where the unit is | Suggested fix |
|---|---|---|
| project unit | under the own roots -- your own code, just not listed | `--apply`: add it to the `.dpr` and `.dproj` (the default) |
| third-party | outside the own roots -- a vendor or framework folder | `--apply --to library`: add its folder to the library section's `"include"` |

Both fixes are always open to you; the verdict is a recommendation. The text
report marks each line (`[project unit -> --apply]` or
`[third-party -> library: --apply --to library]`) and ends with a
**SUGGESTED FIXES** block: one command per fix, already narrowed with `--only`
to the units that suit it. `--json` gives each MISSING item `owner`,
`suggestedFix` and `folder`.

`--apply --to library` edits the manifest named by `--config`, or else the
`drag-lint.json` beside the exe. It writes `<manifest>.bak` first and keeps
every key it does not model. If a `dll-win32` / `dll-win64` twin exists, it
copies the result there too. The project files are not touched. The next
`index --all` walks the new folder as a library root on every platform the
section targets, and the next reconcile no longer lists those units.

## In lint-all
`unit-not-in-library` (project-wide, on by default) reports each third-party
unit that is neither a member nor in the library, using the same analysis.
Units under the own roots are `unit-not-in-dpr`'s job (its third direction), so
each unit is reported exactly once.
```
drag-lint lint-all --db <db> --project <App.dproj> --rule unit-not-in-library
```

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Reconcile Project Members (.dpr/.dproj)...

The menu item runs the report, verdicts and SUGGESTED FIXES included. The Uses
tab's checklist applies the default fix to the units you tick. For the library
fix, run the suggested command from a shell.

## What it needs
Optional. An index is not required to run this command, but pass `--db` to
also heal the index and findings for the project's members.

## Example
Illustrative only:
```
drag-lint reconcile-project C:\Projects\MyApp\Tests\MyAppTests.dproj
```
A test project that compiles `..\..\COMMON\FlexDateTime.pas` (inside the
declared own roots) and `C:\Projects\DUnitX\Source\DUnitX.TestFramework.pas`
(outside them) would show FlexDateTime as a project unit
(`--only FlexDateTime --apply`) and DUnitX.TestFramework as third-party
(`--only DUnitX.TestFramework,... --apply --to library`).
