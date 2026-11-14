# RTL collection and environment rules

Seven lint checks for common run-time-library mistakes around dictionaries,
string lists, `Null`, the registry, `Random` and elapsed time. They work on one
file at a time, from the declarations the file shows: a name counts as a
dictionary or string list only when this very unit declares it as one (or
creates one into it). Anything the file does not show stays silent.

## Running it from the CLI
```
drag-lint lint <file.pas>
drag-lint lint-all --db PATH --rule <rule-id>
```
`lint-all --rule random-without-randomize` is project-wide: it needs the whole
project in the index, so it never fires from `lint <file>`.

| rule | fires when |
|---|---|
| `dictionary-get-without-check` | `Dict[Key]` or `Dict.Items[Key]` is read on a `TDictionary`, `TObjectDictionary`, `TSortedDictionary` or `IDictionary` and the routine has no `ContainsKey` / `TryGetValue` guard. A write target (`Dict[Key] := ...`) and a read after an `Add` in the same routine stay silent. |
| `stringlist-objects-leak` | `AddObject`, `InsertObject` or `Objects[i] :=` stores a freshly created object into a `TStringList` created in the unit that does not own its objects (no `Create(True)` / `OwnsObjects := True`, and the file never frees the `Objects[]`). |
| `stringlist-unsorted` | `Find`, or a `Duplicates` assignment, on a `TStringList` created in the unit that is never sorted (`Sorted := True`, `Sort`, `CustomSort`). |
| `null-compare` | A variant is compared with `Null` using `=` or `<>`; the result depends on `NullEqualityRule`. Use `VarIsNull`. |
| `registry-hklm-write` | A `TRegistry` rooted at `HKEY_LOCAL_MACHINE` is written in the same routine, or a Win32 `Reg*` write call is given `HKEY_LOCAL_MACHINE`. |
| `random-without-randomize` | `Random` is called but no unit of the project calls `Randomize` or sets `RandSeed`. |
| `gettickcount-wraparound` (extended) | `Now` is taken into a local and subtracted from a later `Now` in the same routine (also the `*Between(Now, Start)` family). |

## Reaching it in the IDE
Findings appear in the editor like every other lint finding.

## What it needs
`lint <file>` needs no index. `lint-all` rules need the project DB, found with
`drag-lint resolve-dbs --project <X.dproj>`.

## Pitfalls
- A dictionary or list declared in another unit (an ancestor's field, a
  parameter type alias from a different unit) is not recognised, so those
  reads stay silent rather than guessed.
- No autofix: every repair changes behaviour or needs the expression extent,
  so each message carries the suggestion instead.
