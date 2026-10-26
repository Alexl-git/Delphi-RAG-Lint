---
id: doc-drift
title: doc-drift
summary: Diagnostic that computes deterministic doc-vs-code drift findings for one symbol
product: DL
group: documentation
order: 40002
since: 0.93.0-alpha
status: shipped
updated: 1.35.0-alpha
---

# doc-drift

Diagnostic that computes deterministic doc-vs-code drift findings for one symbol.

Read this when you want to know why an existing doc comment is considered out of date. doc-drift prints the deterministic doc-versus-code drift findings for one symbol.

## How to run it

Full flag list: [doc-drift in the CLI reference](../cli.md#doc-drift).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `X` |  |  |
| `--db` | `PATH` |  |  |
| `--json` |  |  |  |

**Needs:** index

## Details

Diagnostic that computes deterministic doc-vs-code drift findings for one
symbol. Reach for it to see exactly why `document`/autodoc considers a
symbol's existing doc comment out of date.

### Running it from the CLI
```text
drag-lint doc-drift --qname X --db PATH [--json]
```
`--qname X` is the symbol to check. `--json` emits machine-readable output.

This is labeled a "diagnostic" in the CLI banner -- it is a troubleshooting
tool, not a daily driver.

### Exceptions raised in callees
An `<exception cref="EFoo">` is not drift when the routine, or a callee up to
three calls down (resolved call edges only), raises `EFoo`. The walk is
breadth-first and cycle-safe, capped at 256 visited symbols
(`CREF_RAISE_MAX_HOPS = 3`, `CREF_RAISE_MAX_VISITS = 256` in
`src\doc\DRagLint.Doc.Drift.pas`) so a hub routine cannot walk the whole call
graph. A raise beyond three hops, or past the cap, is still reported. It used
to be one hop.

### `Used in units:` holds units only
A class name found in a stored `Used in units:` list (one this index resolves
as a class, interface or record and not as a unit) is drift: the fix moves it
to its own `<para>Used in classes: ...</para>` line, written directly after
`Used in units:`. The engine never renders that line itself; it keeps it on
every regeneration, and doc-drift never calls it out of date. A name the index
cannot see stays in `Used in units:`. (Backlog X-24, owner ruling 2026-10-25.)

### Reaching it in the IDE
No IDE surface -- this is a CLI-only feature.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint doc-drift --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would report the specific drift findings between `Total`'s current doc
comment and its code.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
