# CLI fixes in 1.51.1

Read this when a `lint-all --rule` run is slow or reaches other databases, when `rules` or `info` does not print
what you expect, or when you index a project and look for the parse-error count.

## lint-all --rule a,b runs only those rules
```
drag-lint lint-all --db <file.sqlite> --rule dictionary-get-without-check,threadvar-managed --json
```
A comma list now narrows EXECUTION as one id does: only the named rules run, and no `--shared-db` peer runs are
derived. On the YADF copy the two-rule run went from 1025.8 s to 13.6 s. Naming an OFF-by-default rule still opts
it in for the run.

## lint-all on a DB copy stays on the copy
`lint-all --db <copy>` on a database the manifest does not register skips the dl:shared marker-peer pass (one
stderr note) and resolves sibling databases to same-named files beside `--db`; a sibling without a copy is
"could not check". In 1.51.0 a copy opened the REAL sibling databases. `--shared-db <db>` is still the opt-in.

## rules --rule
```
drag-lint rules --rule deep-nesting,missing-doc --json
```
Lists only those rules; an unknown id is exit 2.

## info prints the versions again
`drag-lint info` (text) prints `extractor:`, `resolver:` and `grammar dlls:` (size:sha256-16 per DLL) lines, as
`--json` does. 1.51.0 printed only the ABI line.

## index: parse-errors on the Done line
The `index --project` / `index <dir>` Done line ends in `, parse-errors=N` -- files parsed this run whose syntax
tree had ERROR or MISSING nodes.

## index --resolve-only without the library
A database resolved against a platform library and re-resolved with no library store attached prints
`WARNING: index: no library store attached: external targets will be cleared; pass --library-db <library.sqlite>.`
The targets are still cleared in 1.51.1. Since 1.52 the run KEEPS the library bindings of the last library run and
the warning reads `WARNING: index: no library store attached: library bindings are kept from the last library run, not refreshed; pass --library-db <library.sqlite>.`

## find-deadcode on a library project
`find-deadcode` no longer lists every used unit of a library project as dead.

## lint --fix and lint-all-only rules
A single-file `lint --fix` says that the rules only `lint-all` checks (review-marker-unused, unused-public-symbol,
...) were not run.
