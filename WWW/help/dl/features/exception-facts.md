---
id: exception-facts
title: exception-facts
summary: Lists which routine raises and handles which exception type, by routine or by type
product: DL
group: search-navigation
order: 20006
since: 1.46.0-alpha
status: shipped
updated: 1.49.0-alpha
---

# exception-facts

Lists which routine raises and handles which exception type, by routine or by type.

Read this when the question is a set: every routine that raises or catches a type, or every type one routine raises and catches. It reads the raise and handler sites the index holds, one row per site, and says how each type is known. For where an exception ends up through the callers, use ask exception-paths.

## How to run it

Full flag list: [exception-facts in the CLI reference](../cli.md#exception-facts).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--target` | `<routine>` |  |  |
| `--name` | `<Type>` |  |  |
| `--db` | `<db>` |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

**Needs:** index

## Details

Lists which routine raises and handles which exception type. Reach for it when the question is a set: every routine that raises or catches a type, or every type one routine raises and catches. It reads the raise and handler sites the index holds, one row per site.

### Running it from the CLI

```text
drag-lint exception-facts --target <routine> --db <db> [--json]
drag-lint exception-facts --name <Type> --db <db> [--json]
```

`--target` takes a qualified routine or its trailing part (`TFoo.Bar`, `Bar`); every routine that matches is listed. `--name` takes a bare type or a qualified one (`ExcA.EDup` picks one of two types of that name). Give exactly one of them.

### What a row says

| field | meaning |
|---|---|
| `action` | `raises`, `raises-expr` (`raise X`), `reraises` (`raise;`), `handles` (`on E: T do`), `handles-all` (a bare `except`, or the `else` after handlers) |
| `type` | the type as spelled, or as derived; empty when nothing tells |
| `type_qname` | the indexed type, empty when the DB does not hold it |
| `via` | how the type is known, see below |
| `routine`, `file`, `line`, `col` | the site |

`via`:

* `bound`: the resolver bound the row to that type, the strongest answer;
* `handler`: the type of the enclosing `on .. do`, for `raise;` and `raise E;`;
* `local`: a `raise X` whose `X` is a local variable or parameter of that one type;
* `name`: the resolver declined, and exactly one indexed type has that spelling;
* `spelled`: the source names it and the DB does not hold it (`on E: Exception` in a project DB). Not an error;
* `unknown`: nothing tells: `raise MakeError(..)`, a `raise;` under a bare `except`;
* empty on `handles-all`, which names no type.

### The language server and the quick pick

The language server advertises the `draglint.exceptionFacts` command only while exception facts are on: under `drag-lint lsp --no-exception-facts` it is not advertised (`showCallers` and `setContext` stay). Guard: `tests\autotest\run_lsp_hover_exceptions_guard.ps1` (150 LX2).

### Read it carefully

* **No ancestry.** `on E: Exception` is not listed under `EFoo`, though it catches one. `ask exception-paths` walks ancestry.
* **No callers.** A routine that lets a callee's exception pass is not listed as raising it. `ask exception-paths` walks the callers.
* **A DB from before this fact.** Rows exist from 1.36.0 on, so the verb answers; `raise;` reads `unknown` until a re-parse, and nothing reads `bound` until a resolve pass.
* **Anonymous methods.** A `raise;` inside an anonymous method inside a handler is given that handler's type, though it runs later.

See also: ask: exception-paths, [usages](usages.md).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
