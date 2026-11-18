---
id: v1511-cli-fixes
title: CLI fixes in 1.51.1
summary: lint-all --rule a,b runs only those rules, a DB copy stays on the copy; rules --rule; info versions; index parse-errors; resolve-only warning
product: DL
group: linting
order: 30064
since: 1.51.1-alpha
status: shipped
updated: 1.51.1-alpha
---

# CLI fixes in 1.51.1

lint-all --rule a,b runs only those rules, a DB copy stays on the copy; rules --rule; info versions; index parse-errors; resolve-only warning.

Read this when a lint-all --rule run is slow or reaches other databases, when rules or info does not print what you expect, or when you look for the parse-error count of an index run.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output|--report <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none] [--no-budget]
```

Example:

```text
drag-lint lint-all --db <file.sqlite> --rule <id>,<id>
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

```text
drag-lint rules [--json] [--category <name>] [--standard cwe|cert|misra] [--rule <id>[,<id>]] [--rules-dir <dir>] [--target-compiler <ver|auto> [--project <.dproj>]] - list every lint rule (catalog; each labelled rule shows its CWE/CERT/MISRA ids, --json adds `compliance` and needs_compiler / compat_since / target_active; --standard lists only rules labelled under it; --rule <id>[,<id>] lists only those rules, an unknown id is exit 2)
```

Example:

```text
drag-lint rules --rule <id>[,<id>] --json
```

Full flag list: [rules in the CLI reference](../cli.md#rules).

```text
drag-lint info [--json] [--db <file.sqlite>]... (engine self-info: product/extractor/resolver versions, build date, MIT, tree-sitter + capabilities; read-only; the text form prints extractor:, resolver: and grammar dlls: (size:sha256-16 per DLL) lines as --json does -- 1.51.0 printed only the ABI line)
```

Example:

```text
drag-lint info --db <file.sqlite>
```

Full flag list: [info in the CLI reference](../cli.md#info).

```text
drag-lint index <path> [--db <file.sqlite>] [--watch [--interval N]] [--library-db <lib.sqlite> ...] [--wait-library <min>] [--require-library] [--stall-exit-min <min>] [--target-compiler <ver|auto>]
```

Example:

```text
drag-lint index --project <X.dproj> --db <file.sqlite>
```

Full flag list: [index in the CLI reference](../cli.md#index).

```text
drag-lint find-deadcode [--kind method|function|...] [--include-private] [--db PATH]
```

Example:

```text
drag-lint find-deadcode --db <file.sqlite>
```

Full flag list: [find-deadcode in the CLI reference](../cli.md#find-deadcode).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Read this when a `lint-all --rule` run is slow or reaches other databases, when `rules` or `info` does not print
what you expect, or when you index a project and look for the parse-error count.

### lint-all --rule a,b runs only those rules
```text
drag-lint lint-all --db <file.sqlite> --rule dictionary-get-without-check,threadvar-managed --json
```
A comma list now narrows EXECUTION as one id does: only the named rules run, and no `--shared-db` peer runs are
derived. On the YADF copy the two-rule run went from 1025.8 s to 13.6 s. Naming an OFF-by-default rule still opts
it in for the run.

### lint-all on a DB copy stays on the copy
`lint-all --db <copy>` on a database the manifest does not register skips the dl:shared marker-peer pass (one
stderr note) and resolves sibling databases to same-named files beside `--db`; a sibling without a copy is
"could not check". In 1.51.0 a copy opened the REAL sibling databases. `--shared-db <db>` is still the opt-in.

### rules --rule
```text
drag-lint rules --rule deep-nesting,missing-doc --json
```
Lists only those rules; an unknown id is exit 2.

### info prints the versions again
`drag-lint info` (text) prints `extractor:`, `resolver:` and `grammar dlls:` (size:sha256-16 per DLL) lines, as
`--json` does. 1.51.0 printed only the ABI line.

### index: parse-errors on the Done line
The `index --project` / `index <dir>` Done line ends in `, parse-errors=N` -- files parsed this run whose syntax
tree had ERROR or MISSING nodes.

### index --resolve-only without the library
A database resolved against a platform library and re-resolved with no library store attached prints
`WARNING: index: no library store attached: external targets will be cleared; pass --library-db <library.sqlite>.`
The targets are still cleared in 1.51.1. Since 1.52 the run KEEPS the library bindings of the last library run and
the warning reads `WARNING: index: no library store attached: library bindings are kept from the last library run, not refreshed; pass --library-db <library.sqlite>.`

### find-deadcode on a library project
`find-deadcode` no longer lists every used unit of a library project as dead.

### lint --fix and lint-all-only rules
A single-file `lint --fix` says that the rules only `lint-all` checks (review-marker-unused, unused-public-symbol,
...) were not run.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
