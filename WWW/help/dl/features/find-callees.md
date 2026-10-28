---
id: find-callees
title: find-callees
summary: Lists the resolved outgoing calls of one routine, plus the library-bound ones
product: DL
group: search-navigation
order: 20006
since: 0.91.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# find-callees

Lists the resolved outgoing calls of one routine, plus the library-bound ones.

Read this when you want to know what a routine actually calls, resolved through the index rather than by reading its source. find-callees --qname Foo.Bar lists its outgoing calls; add --json for machine-readable output.

## How to run it

Full flag list: [find-callees in the CLI reference](../cli.md#find-callees).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.Bar>` |  |  |
| `--db` | `PATH` |  |  |
| `--library-db` | `LIBRARY` | the library index to bind library-bound callees against at read time (a second --db does the same) |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > What This Routine Calls (callees)...**
   1. Needs an index of the project
   2. drag-lint > Uses & Dependencies > What This Routine Calls (callees)...
   3. Enter or confirm the routine; its resolved outgoing calls are listed

**Needs:** index

## Details

Lists the resolved outgoing calls of one routine. Reach for it to see what
a routine actually calls, resolved through the call-edge index rather than
by reading its source.

### Running it from the CLI
```text
drag-lint find-callees --qname <Foo.Bar> --db PATH [--db LIBRARY | --library-db LIBRARY] [--json]
```
`--qname <Foo.Bar>` is the routine to inspect. `--json` emits
machine-readable output.

### Library-bound callees
After the resolved callees, `find-callees` lists the calls that go into a library
(RTL, VCL, DevExpress), marked `(library`. A project index never holds a call
edge into another index; it records the target by qualified NAME on
`refs.external_target` when a library was open while it was built (`index
--library-db`, or the manifest section key `"libraryResolve": true`, default
false). Those rows are printed as `(library, by name)` (`--json`: `"external":
true, "via": "edge"`).

A project index built WITHOUT a library can still be read against one: pass the
library index as a second `--db` or as `--library-db`. The call sites whose
receiver type is recorded (`refs.receiver_type_text`) are then bound now, printed
`(library, resolved now)` (`"via": "oracle"`). A site binds only when exactly one
type and exactly one member match; a same-named member on an unrelated type is
never listed.

With no library open the output ends `M external (library not open)`: M is the number of calls whose receiver type is known but which only a
library can answer.

### What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example
Illustrative only:
```text
drag-lint find-callees --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would list every routine that `Total` resolves calls to.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
