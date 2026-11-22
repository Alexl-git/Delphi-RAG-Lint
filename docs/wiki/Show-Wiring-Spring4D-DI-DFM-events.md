# Show Wiring (Spring4D DI + DFM events)

Surfaces bindings the compiler does not make obvious: Spring4D container
registrations and DFM event hookups for a type. Reach for it when tracing how
an interface gets resolved, or which handler a DFM event actually calls.

## Running it from the CLI
```
drag-lint wiring --qname <IIntf|TForm> [--db <file.sqlite>] [--format text|json]
```
A separate coverage mode is also documented:
```
drag-lint wiring --coverage [--db <file.sqlite>] [--format text|json]
```
which reports DI registrations that remain unresolved to an interface-to-type pairing.

## Reaching it in the IDE
drag-lint > Uses & Dependencies > Show Wiring (Spring4D DI + DFM events)...

## What it needs
Optional. An index is not marked required, but the wiring data comes from
whatever has been indexed.

## Example
Illustrative only:
```
drag-lint wiring --qname MyApp.TfrmMain --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format text
```
This would list Spring4D DI registrations and DFM event edges touching `TfrmMain`.

## Form bindings (GitHub #21)
A DFM event binding is listed under a form class only when it comes from that form's own DFM, or from the DFM of a form that descends from the queried class (a descendant that redeclares the handler is kept). Bindings of unrelated forms that share a handler name (FormShow, FormCreate) are dropped. The MCP tool get_wiring and the context verb use the same check, so the three agree.
