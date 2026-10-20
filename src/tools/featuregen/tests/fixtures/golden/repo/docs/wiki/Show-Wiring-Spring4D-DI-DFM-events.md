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
which reports DI registrations not yet resolved to an interface-to-type pairing.

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
