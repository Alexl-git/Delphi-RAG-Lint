# Include-file indexing and {$IF} evaluation

The indexer follows `{$I file.inc}` the way the compiler would for the project's active build, and evaluates the conditions that choose the branch.

## Running it from the CLI
```
drag-lint index --project <file.dproj> --db <file.sqlite>
drag-lint pp-profile --dproj <file.dproj>      (the define set the indexer sees)
```
A project DB indexes only the ACTIVE includes, parsed in the includer's define context. Which include is chosen follows the exact preprocessor values: value defines, `CompilerVersion`, `IFOPT`, true constants of the same file or of a used project / library unit, `Declared()` and arithmetic in `{$IF}`. `lint-all` lints an `.inc` file in the context of its includer. When an `{$IF}` cannot be decided, `lint` reports the `pp-unresolved-if` hint instead of guessing. One exception, with the same hint: a run with no library DB and the newest target reads `Declared(X)` as True for a name nothing else answers, because a miss there proves nothing and such a test usually names what the current compiler has. With a library DB, a miss is False. For an older target it stays False.

A uses list may itself be an include: `uses {$I units.inc}` with the entries and the closing semicolon in the `.inc`. Since extractor 1.35 (index schema 24) its entries are host `unit_uses` rows (with `origin_path` = the `.inc`), so `cycles`, `deps` and the charts see the edges; before, the host's uses clause read as empty and swallowed the section after it. The edges are reported, never edited (an `.inc` may be shared by many hosts).

The index also records the facts directly (schema 24, `docs\wiki\Index-DB-Schema.md`): `file_includes` (every resolved include of a file: path, host line, depth, section, whether it stands in a uses list) and `pp_regions` (every conditional branch of a file and whether it was active under the indexed build). Example: `drag-lint sql --query "SELECT f.path, i.inc_path, i.in_uses FROM file_includes i JOIN files f ON f.id = i.file_id" --db <file.sqlite>`.

## Reaching it in the IDE
No IDE surface; the IDE plugin uses the same index.

## What it needs
A project index built with the 1.37.0 extractor; older DBs re-parse on the next index run.
