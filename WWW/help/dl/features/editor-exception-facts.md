---
id: editor-exception-facts
title: Exception facts in the editor
summary: Hover, code lens and an MCP tool show which exception types a routine raises and handles
product: DL
group: editor-integration
order: 110006
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Exception facts in the editor

Hover, code lens and an MCP tool show which exception types a routine raises and handles.

Read this when you want to see, without leaving the editor, which exceptions a routine raises and which it catches. Hovering a routine adds one Raises: line (each type once, with how it is known: bound, handler, local, name, spelled or unknown); a code lens on the routine header says raises N types, handles M types (VS Code: a click lists the sites; the Delphi IDE lens reads the same titles); the MCP tool get_exception_facts returns the same rows as exception-facts --json. ON by default; lsp --no-exception-facts switches the hover line and the lens off.

## How to run it

```text
drag-lint lsp --db <file.sqlite> [--no-exception-facts]
```

Example:

```text
drag-lint lsp --db <file.sqlite> --no-exception-facts
```

Full flag list: [lsp in the CLI reference](../cli.md#lsp).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--no-exception-facts` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

The index records every `raise`, re-raise and `except` handler with the exception type it
names (`exception-facts`, since 1.46). Since 1.47 the editor shows that fact too, and an MCP
client can ask for it. All three surfaces read through ONE reader
(`DRagLint.Query.ExceptionFacts`, the same code as the `exception-facts` verb), so they cannot
disagree with the CLI.

### Hover: the `Raises:` line

Hovering a routine (LSP `textDocument/hover`, and `draglint/hoverBundle`, which the Delphi IDE
popup uses) adds one line after the other analysis facts:

```text
Raises: EFoo (bound), EArgumentException (spelled)
```

Each type is named once, in source order, with how it is known: `bound` (the index resolved the
type), `handler` (a `raise;` / `raise E` inside `on E: EFoo do`), `local` (a local or parameter of
that type), `name` (the one indexed type of that spelling), `spelled` (the source names it, the
index does not hold it) or `unknown` (`raise MakeError(..)`, a `raise;` under a bare `except`).
A routine that raises nothing gets no line. What a routine CATCHES is the existing `Catches:`
line (the same one `document` writes into the doc block).

### Code lens

`textDocument/codeLens` adds a lens on the routine's declaration line, beside the caller count:

```text
raises 2 types, handles 1 type
```

Distinct raised types and distinct handled types (a bare `except` counts as one); either half is
left out when it is zero.

Since 1.49 the lens is clickable: its command is `draglint.exceptionFacts` with `[uri, line]`
(`workspace/executeCommand`, advertised in `executeCommandProvider`). The server answers the
routine's raise and handler sites, the same rows the title counts:

```text
[{"uri": "file:///C:/p/uExc.pas", "line": 30, "character": 10, "action": "handles",
  "type": "EFoo", "via": "bound", "routine": "uExc.TWorker.Safe"}, ...]
```

(0-based positions; `[]` under `--no-exception-facts` or for a line with no such routine). The
VS Code extension shows them in a quick pick (`handles EFoo` / `line 31 (bound)`); picking one
jumps to the site.

The Delphi IDE lens reads `draglint/callerCounts`, not `textDocument/codeLens`, so since 1.49
that reply carries the same titles too: `exceptions: [{"line": L, "title": "raises 2 types"}]`
beside `counts` and `implementors` (0-based declaration lines; `[]` when switched off; an
older engine sends no `exceptions` key). The plugin renders it beside the caller count.

### MCP: `get_exception_facts`

`tools/call` with `name` = `get_exception_facts` and exactly one of:
- `target`: a routine, qualified or by its trailing part;
- `name`: an exception type, bare or qualified (exact type, no ancestry);
- `db` (optional): an index path when the server was started without one.

The reply is the JSON of `drag-lint exception-facts --json`, byte for byte. Neither or both
selectors is an error.

### Switching it off

ON by default (owner ruling, wave 148). `drag-lint lsp --no-exception-facts` removes the hover
line, the lens and the callerCounts titles (`draglint.exceptionFacts` then answers `[]`); hover is then byte-identical to 1.46. The MCP tool is always available (a new
tool changes no existing answer).

### Cost

The hover reads the routine's rows through the symbols indexes (one store open plus one
indexed query; about 80 ms over a bare store open on the 520k-ref drag-lint index, measured
min-of-10 on a loaded machine). The lens reads the file's rows once per `codeLens` request.

### Limits

No escape analysis: the line lists the routine's OWN raise sites, not what its callees raise
(that is `ask exception-paths`). On an index written before 1.46 the types read `unknown`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
