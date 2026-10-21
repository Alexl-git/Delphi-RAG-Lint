---
id: context
title: context
summary: Returns a compact context bundle for a symbol -- its doc comment, class surface (signatures), the target's own body, and a capped list of callers
product: DL
group: search-navigation
order: 20004
since: 0.6.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# context

Returns a compact context bundle for a symbol -- its doc comment, class surface (signatures), the target's own body, and a capped list of callers.

Read this before editing or explaining a symbol. context returns a compact bundle, its doc comment, class surface, own body and a capped list of callers, so you read a fraction of what a whole-file read costs.

## How to run it

Full flag list: [context in the CLI reference](../cli.md#context).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--task` |  |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |
| `--no-docs` |  |  |  |
| `--full-surface` |  |  |  |
| `--max-callers` | `N` |  |  |
| `--context` | `N` |  |  |

## Pitfalls

* ~60x leaner than the source. Add --full-surface ONLY for DFM/component/event work.

## Details

Returns a compact context bundle for a symbol -- its doc comment, class
surface (signatures), the target's own body, and a capped list of callers
-- instead of whole source files. Reach for it before editing or explaining
a symbol so you read a fraction of the tokens a full-file read would cost.

### Running it from the CLI
```text
drag-lint context --task "verb qname" [--db <file.sqlite>] [--format md|json|raw] [--max-callers N] [--context N] [--no-docs] [--full-surface]
```
`--task "verb qname"` names the symbol and intended action (e.g. `"modify
Foo.Bar"`). `--format` selects `md`, `json`, or `raw`. `--max-callers N`
caps how many callers are included. `--context N` is present in the usage
line; its effect is not documented beyond the flag name. `--no-docs` omits
doc comments from the bundle.

### Reaching it in the IDE
No menu item calls this directly. The plugin uses it internally from
`DragLint.Plugin.Editor.pas:633`; there is no menu item for it. The MCP
`get_context_bundle` tool wraps this same engine.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint context --task "modify CustomerOrder.TCustomerOrder.Total" --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format md
```
This would return `Total`'s doc comment, its class's surface, its own body,
and a capped list of callers, as markdown.

### When the phrase is not an identifier

The bundle also carries a `## Wiki` section: if the task phrase matches the
name or an alias of a [`dl:wiki`](wiki-blocks-authoring.md) concept topic in
this index, up to **two** topics are included, above the code, with their
owning symbol, `SeeCode` participants and body. `--no-docs` suppresses it --
a concept body is prose, and `--no-docs` means no prose.

That also makes a failed lookup useful. `--task "modify the streaming path"`
names no symbol, so the bundle reports `NOT FOUND` and **exits 1** -- but if
the phrase names a concept, the topic and its symbols are printed anyway, and
that is the pointer the reader was actually asking for.

> The `NOT FOUND` line and the non-zero exit are recent. Until 2026-08-27 a
> qname that resolved to nothing produced an empty bundle reading
> `Token count (estimated): 0` and **exit 0** -- indistinguishable from a
> symbol that genuinely has no context. The check meant to catch it tested
> whether the bundle carried a qname, which `Build` had already filled in from
> the request, so it never fired.

Topics are read from the SAME index the bundle came from. A concept note from
an unrelated project would be a confidently wrong answer, so cross-database
matching is deliberately not done.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
