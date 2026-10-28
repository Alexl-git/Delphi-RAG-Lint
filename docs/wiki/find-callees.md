# find-callees

Lists the resolved outgoing calls of one routine. Reach for it to see what
a routine actually calls, resolved through the call-edge index rather than
by reading its source.

## Running it from the CLI
```
drag-lint find-callees --qname <Foo.Bar> --db PATH [--db LIBRARY | --library-db LIBRARY] [--json]
```
`--qname <Foo.Bar>` is the routine to inspect. `--json` emits
machine-readable output.

## Library-bound callees
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

## Reaching it in the IDE
In the IDE choose drag-lint > Uses & Dependencies > What This Routine Calls (callees)... with the caret on a routine.

## What it needs
An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example
Illustrative only:
```
drag-lint find-callees --qname CustomerOrder.TCustomerOrder.Total --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --json
```
This would list every routine that `Total` resolves calls to.
