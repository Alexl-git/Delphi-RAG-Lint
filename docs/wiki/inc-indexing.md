# Include-file indexing and {$IF} evaluation

The indexer follows `{$I file.inc}` the way the compiler would for the project's active build, and evaluates the conditions that choose the branch.

## Running it from the CLI
```
drag-lint index --project <file.dproj> --db <file.sqlite>
drag-lint pp-profile --dproj <file.dproj>      (the define set the indexer sees)
```
A project DB indexes only the ACTIVE includes, parsed in the includer's define context. Which include is chosen follows the exact preprocessor values: value defines, `CompilerVersion`, `IFOPT`, true constants of the same file or of a used project / library unit, `Declared()` and arithmetic in `{$IF}`. `lint-all` lints an `.inc` file in the context of its includer. When an `{$IF}` cannot be decided, `lint` reports the `pp-unresolved-if` hint instead of guessing. One exception, with the same hint: a run with no library DB and the newest target reads `Declared(X)` as True for a name nothing else answers, because a miss there proves nothing and such a test usually names what the current compiler has. With a library DB, a miss is False. For an older target it stays False.

A uses list may itself be an include: `uses {$I units.inc}` with the entries and the closing semicolon in the `.inc`. Since extractor 1.35 its entries are host `unit_uses` rows (with `origin_path` = the `.inc`), so `cycles`, `deps` and the charts see the edges; before, the host's uses clause read as empty and swallowed the section after it. The edges are reported, never edited (an `.inc` may be shared by many hosts).

The index also records the facts directly (extractor 1.35, `docs\wiki\Index-DB-Schema.md`): `file_includes` (every resolved include of a file: path, host line, depth, section, whether it stands in a uses list) and `pp_regions` (every conditional branch of a file and whether it was active under the indexed build). Example: `drag-lint sql --query "SELECT f.path, i.inc_path, i.in_uses FROM file_includes i JOIN files f ON f.id = i.file_id" --db <file.sqlite>`.

### An include that several units include (1.51.1)
Code inside an include is resolved in the scope of the unit that includes it. When several units include the same file, each ref in it is resolved once per host. If every host gives the same target the ref is bound like any other. If they differ (`Emit;` in a shared include where each host has its own `Emit`), `refs.symbol_id` stays NULL -- it holds one target -- and the table `ref_host_bindings(ref_id, host_file_id, symbol_id)` (schema 26) holds one row per host; `symbol_id` is NULL for a host that gave no certain answer. Rows exist only for a ref that is unbound on the ref and that at least one host binds: where the hosts agree, `refs.symbol_id` is every host's binding and the table has no row (per-host target in SQL: `COALESCE(hb.symbol_id, r.symbol_id)`). A method body written in a shared include (`procedure TWork.Run;`) belongs to the `TWork` of each host in turn, so its calls to other members bind per host.

`find-callers --name X` reports such a site `exact` when every host binds it; `find-callers --resolved` and a qualified `usages --name Unit.X` list the site under each declaration a host binds it to. Other readers (rename, lint, `refs.symbol_id` joins) still see the ref as unbound where the hosts differ. The rows are written by the resolve pass: an index made by an older engine gets them on its next re-resolve. Example: `drag-lint sql --query "SELECT r.name_text, hf.path AS host, s.qualified_name FROM ref_host_bindings hb JOIN refs r ON r.id = hb.ref_id JOIN files hf ON hf.id = hb.host_file_id LEFT JOIN symbols s ON s.id = hb.symbol_id" --db <file.sqlite>`. Guard: `tests\autotest\run_v1511_INC2_per_host_bindings.ps1`.

### An include parsed per inclusion (1.52)

An include is parsed in the define context of EACH unit that includes it (owner ruling B9i: the contexts need not agree). Units whose context is byte-equal share one parse. When the contexts differ, a declaration or reference every context has is stored once (`inc_variant` 0); one that only some contexts have is stored per context, tagged `inc_variant` = k, and the table `inc_variants(file_id, host_file_id, variant, ctx_sha)` (schema 27) names the hosts of context k. The resolver binds a tagged reference under those hosts only: in `ExBody.inc` with `{$IFDEF COMPILE1} PingA; {$ELSE} PingB; {$ENDIF}`, `find-callers --resolved` lists the `PingA` site under the unit that defines COMPILE1 and the `PingB` site under the one that does not, never the other way round. An incremental run that re-parses the include takes the stored context of a host it skipped (`ctx_sha`) and preprocesses that host again only when the context is unknown or the include itself changed. Example: `drag-lint sql --query "SELECT s.name, s.signature, s.inc_variant FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.inc_variant > 0" --db <file.sqlite>`. Guard: `tests\autotest\run_v152_EXTINC_per_inclusion.ps1`.

## Reaching it in the IDE
No IDE surface; the IDE plugin uses the same index.

## What it needs
A project index built with the 1.37.0 extractor; older DBs re-parse on the next index run.
