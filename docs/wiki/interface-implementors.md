# Interface Implementors Report

**Who implements this interface, which method answers it, and who calls it.** One engine
(`DRagLint.Query.Implementors`) behind the `implementors` verb, the `ask implementors` chart,
the LSP *Go to Implementation* answer, the "N implementors" code lens and the MCP tool
`get_implementors`. Spec: `docs\superpowers\specs\2026-11-01-interface-report-design.md`.

## What you can ask

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

## CLI

`--output <file>` obeys `--output-encoding` and writes no BOM (since 1.44), like every other text report.

```
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

## Chart, IDE, LSP, MCP

* `drag-lint ask implementors --target IJob.Execute --db <project.sqlite>` -- the same report as a
  clickable chart; in RAD Studio *drag-lint > Reports > Who implements this interface (implementors)...*.
* LSP `textDocument/implementation` on an interface lists its implementing classes, and on an
  interface method the answering method of every implementing class (its body; a body-less
  abstract one at its declaration).
* Code lens: "N implementors" above every interface and interface method that has any (the IDE
  plugin shows `[N implementors]` beside `[N callers]`).
* MCP `get_implementors` (`qname`, optional `uses`, `max_sites`, `db`) returns the `implementors/1` JSON.

## Index facts it reads

`type_ancestors` (who lists which interface), `dispatch_edges` `implements` (interface method ->
implementing method, resolution clauses included) and `delegates` (interface -> the delegating
property), `override` edges (subclass overrides), and the resolved caller rows. An index built
before extractor x129 has no `delegates` rows and points a resolution clause at a body-less row;
re-index to get both.
