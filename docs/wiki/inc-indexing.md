# Include-file indexing and {$IF} evaluation

The indexer follows `{$I file.inc}` the way the compiler would for the project's active build, and evaluates the conditions that choose the branch.

## Running it from the CLI
```
drag-lint index --project <file.dproj> --db <file.sqlite>
drag-lint pp-profile --dproj <file.dproj>      (the define set the indexer sees)
```
A project DB indexes only the ACTIVE includes, parsed in the includer's define context. Which include is chosen follows the exact preprocessor values: value defines, `CompilerVersion`, `IFOPT`, true constants of the same file or of a used project / library unit, `Declared()` and arithmetic in `{$IF}`. `lint-all` lints an `.inc` file in the context of its includer. When an `{$IF}` cannot be decided, `lint` reports the `pp-unresolved-if` hint instead of guessing.

## Reaching it in the IDE
No IDE surface; the IDE plugin uses the same index.

## What it needs
A project index built with the 1.37.0 extractor; older DBs re-parse on the next index run.
