# context

Returns a compact context bundle for a symbol -- its doc comment, class
surface (signatures), the target's own body, and a capped list of callers
-- instead of whole source files. Reach for it before editing or explaining
a symbol so you read a fraction of the tokens a full-file read would cost.

## Running it from the CLI
```
drag-lint context --task "verb qname" [--db <file.sqlite>] [--format md|json|raw] [--max-callers N] [--context N] [--no-docs] [--full-surface]
```
`--task "verb qname"` names the symbol and intended action (e.g. `"modify
Foo.Bar"`). `--format` selects `md`, `json`, or `raw`. `--max-callers N`
caps how many callers are included. `--context N` is present in the usage
line; its effect is not documented beyond the flag name. `--no-docs` omits
doc comments from the bundle.

The class surface is lean by default. For a MEMBER target (a method, field or
property) it lists the owner's declarations without their comment-only lines
(`//` and `///`) -- the target's own doc is in `## Doc`, and the other
members' prose was over 90% of a large class's surface (a 47.5k-token bundle
fell to a fraction). A TYPE target keeps its members' docs. `--full-surface`
keeps everything, the DFM component fields of a form class included.

## Reaching it in the IDE
No menu item calls this directly. The plugin uses it internally from
`GetActiveEditorInfo (DragLint.Plugin.Editor.pas)`; there is no menu item for it. The MCP
`get_context_bundle` tool wraps this same engine.

## What it needs
The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example
Illustrative only:
```
drag-lint context --task "modify CustomerOrder.TCustomerOrder.Total" --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format md
```
This would return `Total`'s doc comment, its class's surface, its own body,
and a capped list of callers, as markdown.

## Library calls

When the project was indexed with a library (`--library-db`, or `libraryResolve` in the manifest), a routine whose body calls library members gets one extra line above `## Callers`: `Library calls: N (top: a, b, c)`. N counts the calls whose stored `external_target` is set; the top three targets are the most frequent. `--format json` carries the same as `library_calls` (`count`, `top`). The count is also query-time by default: calls with no stored link whose receiver is typed by name are bound against the library now (the same binding `find-callees` uses, read-only; a library that cannot be opened is a stderr NOTE and the stored-only count). The library is `--library-db <library.sqlite>` or a second `--db`; with neither, the manifest's library section for `--platform`, else the platform the project DB was indexed for, else the manifest default. `--library-db none` turns that off, and a project with no library anywhere gets no line and no key. `library_calls.via` says where the count came from: `stored`, or `oracle` when at least one call was bound at query time. This reads only: nothing is written to the project DB, and what an index run stores still needs `--library-db` or `libraryResolve`.

## A whole type: the body cap

`context --task "modify TFoo"` on a class, record or interface would print every method body (`TSQLiteSymbolStore`: ~262k estimated tokens). The bodies are capped at `--max-body-tokens N` estimated tokens (default **20000**; `0` = every body, the old bundle). Which bodies stay: a FOCUS method named after the type (`modify TFoo Bar` -- always kept), then the methods most called by the type's other methods, then the smallest, then source order. Every omitted body is listed as its header line and `L<start>-<end>` under `## Omitted bodies`, ending with `-- N omitted by cap C; rerun with --max-body-tokens 0`. While capped, the class declaration chunk is dropped too (`## Class surface` already lists it), and the surface drops the `///` docs of the members whose body was omitted (CTX-SURFACE-DOCS, 1.42; a kept body, e.g. the focus method, keeps its docs; `--full-surface` keeps all). The MCP tool `get_context_bundle` takes the same budget as `max_body_tokens`. The cap engages only when the bodies exceed it, so a small type is unchanged, and a member target (one method) is never cut. `--format json` adds `body_cap`, `bodies_total`, `bodies_omitted`, `body_tokens_total`, `body_tokens_shown` and `omitted_bodies` (`kind`, `signature`, `start_line`, `end_line`, `tokens`) when the cap engaged. `--full-surface` does not lift it.
## When the phrase is not an identifier

The bundle also carries a `## Wiki` section: if the task phrase matches the
name or an alias of a [`dl:wiki`](Wiki-Blocks-Authoring.md) concept topic in
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
