---
id: interface-implementors
title: Interface Implementors Report
summary: Who implements an interface, which method answers each interface method in each class, and who calls or uses an interface member
product: DL
group: graphs-reports
order: 70015
since: 1.40.0-alpha
status: shipped
updated: 1.49.0-alpha
---

# Interface Implementors Report

Who implements an interface, which method answers each interface method in each class, and who calls or uses an interface member.

Use this when you work with an interface: it lists the classes that implement it (directly, through a derived interface, inherited from an ancestor class or delegated by an implements property), the method that answers each interface method in each class -- method-resolution clauses included -- and the call, read and write sites of an interface member. Give it an interface, an interface member, a class or a class method.

## How to run it

```text
drag-lint implementors --target <IFoo|IFoo.Bar|TFoo|TFoo.Bar> --db <file.sqlite> [--library-db <lib.sqlite>] [--uses] [--max-sites N] [--include-library] [--format text|json|dot|mermaid] [--json] [--output <file>]
```

Example:

```text
drag-lint implementors --target IJob.Execute --db app.sqlite
```

Full flag list: [implementors in the CLI reference](../cli.md#implementors).

```text
drag-lint query implementors --target <IFoo|TFoo> --db <file.sqlite> [same flags] (alias of the implementors verb; --name is accepted for --target)
```

Example:

```text
drag-lint query implementors --target IJob.Execute --db app.sqlite
```

Full flag list: [query in the CLI reference](../cli.md#query).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--target` | `<IFoo\|IFoo.Bar\|TFoo\|TFoo.Bar>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--uses` |  |  |  |
| `--max-sites` | `N` |  |  |
| `--include-library` |  |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--output` | `<file>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

**Who implements this interface, which method answers it, and who calls it.** One engine
(`DRagLint.Query.Implementors`) behind the `implementors` verb, the `ask implementors` chart,
the LSP *Go to Implementation* answer, the "N implementors" code lens and the MCP tool
`get_implementors`. Spec: `docs\superpowers\specs\2026-11-01-interface-report-design.md`.

### What you can ask

| Target | Answer |
|---|---|
| an interface `IJob` | every class that implements it, and **how**: `lists` it, `via` a derived interface, `inherited` from an ancestor class, or `delegated` by an `implements` property |
| an interface method `IJob.Execute` | the method that answers it in each implementing class -- an inherited one names its declaring class, a subclass override answers for the subclass, a method-resolution clause (`procedure IJob.Execute = RunJob`) answers with `RunJob`; plus its call sites |
| an interface property `IJob.Name` | its read / write sites |
| a class `TJob` | the interfaces it implements (inherited ones too) and what answers each member |
| a class method `TJob.RunJob` | the interface members it answers; `--uses` adds the sites that reach it through the interface |

Call and use sites are attributed to the **interface member** (the RB-5 ruling): an interface
call is never fanned out to the implementors. Only an implementor target lists the sites that
reach it *via* the interface.

### CLI

`--output <file>` obeys `--output-encoding` and writes no BOM (since 1.44), like every other text report.

```text
drag-lint implementors --target IJob.Execute --db <project.sqlite>
drag-lint implementors --target IJob --db <project.sqlite> --library-db <library.sqlite> --include-library
drag-lint implementors --target TPlainJob.Execute --uses --json --db <project.sqlite>
drag-lint implementors --target IJob --format dot --output ijob.dot --db <project.sqlite>
```

Flags: `--uses` (sites; always on for an interface member), `--max-sites N` (default 50; the
total is always printed), `--library-db` (adds the library's implementor count) with
`--include-library` (lists them), `--format text|json|dot|mermaid`, `--json`, `--output`.
Exit 0 answered (zero implementors is an answer), 1 no such target, 2 usage error or an
ambiguous name (the candidates are listed -- qualify it).

`--json` is `implementors/1`: `target {qname,kind,file,line}`, `implementors[]` and
`unanswered[]` rows `{class,how,via,member,method,declared_in,confidence,note,file,line,body_line}`,
`sites[] {mode,file,line,enclosing,via}`, `sites_total`, `library_implementors` (-1 = no library
given) and `notes[]`. Every array is always present.

### Chart, IDE, LSP, MCP

* `drag-lint ask implementors --target IJob.Execute --db <project.sqlite>` -- the same report as a
  clickable chart; in RAD Studio *drag-lint > Reports > Who implements this interface (implementors)...*.
* LSP `textDocument/implementation` on an interface lists its implementing classes, and on an
  interface method the answering method of every implementing class (its body; a body-less
  abstract one at its declaration).
* Code lens: "N implementors" above every interface and interface method that has any (the IDE
  plugin shows `[N implementors]` beside `[N callers]`).
* MCP `get_implementors` (`qname`, optional `uses`, `max_sites`, `db`) returns the `implementors/1` JSON.

### Index facts it reads

`type_ancestors` (who lists which interface), `dispatch_edges` `implements` (interface method ->
implementing method, resolution clauses included) and `delegates` (interface -> the delegating
property), `override` edges (subclass overrides), and the resolved caller rows. An index built
before extractor x129 has no `delegates` rows and points a resolution clause at a body-less row;
re-index to get both.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
