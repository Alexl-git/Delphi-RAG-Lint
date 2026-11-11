# info

Prints engine self-info: version, build date, license (MIT), tree-sitter
details, and capabilities. Reach for it to check which build of drag-lint
you are running, or to script a version check.

## Running it from the CLI

```
drag-lint info [--json] [--db <file.sqlite>]...
```

Read-only.

With `--json --db <index>` (repeatable) it adds an `indexes` array: per index,
its `indexer_fingerprint` / `resolver_fingerprint`, the booleans
`indexer_stale` / `resolver_stale` / `indexer_newer` / `resolver_newer`, a
`verdict` and a `remedy`. The verdict is one of `current`, `resolve-owed`
(re-resolve: minutes), `reparse-owed` (re-parse: hours), `index-newer` (the
index was built or resolved by a NEWER engine than this one -- reads work, but
`index` with this engine is refused because a writer never downgrades an index;
the remedy is to use a newer engine), `missing` or `unreadable`. Versions are
compared semantically (`1.10.0` is newer than `1.9.0`); an absent stamp is
stale, never newer.

Each `indexes` entry also carries `grammar_dlls_stored` (the size and SHA-256
prefix of the tree-sitter runtime, Delphi and DFM DLLs the index was last
fully parsed with; empty for an index that never recorded it),
`grammar_dlls_loaded` (this engine's) and `grammar_dlls_differ`. A difference
does NOT change the verdict (the parse is not invalidated automatically): the
text form prints a `grammar: DIFFERS` block and the remedy is
`index --rebuild`. An incremental run never relabels an index as parsed with
the new DLLs; only a `--rebuild` or an indexer-fingerprint change does.

## Reaching it in the IDE

CLI+internal: the plugin calls this internally from
`StartBackgroundSelfInfoFetch (DragLint.Plugin.About.pas)` (the About dialog). There is no menu item
for it beyond that internal call site.

## What it needs

No index required -- `info` reports on the engine binary itself, not on any
indexed project.

## Example

Illustrative:

```
drag-lint info --json
```

This would print the engine's version, build date, and capabilities as JSON.
