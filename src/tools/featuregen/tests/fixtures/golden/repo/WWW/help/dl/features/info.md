---
id: info
title: info
summary: "Prints engine self-info: version, build date, license (MIT), tree-sitter details, and capabilities"
product: DL
group: maintenance
order: 120008
since: 0.19.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# info

Prints engine self-info: version, build date, license (MIT), tree-sitter details, and capabilities.

## How to run it

Full flag list: [info in the CLI reference](../cli.md#info).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--json` |  |  |  |
| `--db` | `<file.sqlite>` |  |  |

## Details

Prints engine self-info: version, build date, license (MIT), tree-sitter
details, and capabilities. Reach for it to check which build of drag-lint
you are running, or to script a version check.

### Running it from the CLI

```text
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

### Reaching it in the IDE

CLI+internal: the plugin calls this internally from
`DragLint.Plugin.About.pas:217` (the About dialog). There is no menu item
for it beyond that internal call site.

### What it needs

No index required -- `info` reports on the engine binary itself, not on any
indexed project.

### Example

Illustrative:

```text
drag-lint info --json
```

This would print the engine's version, build date, and capabilities as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
