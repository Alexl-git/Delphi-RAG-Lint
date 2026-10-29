---
id: show-wiring-spring4d-di-dfm-events
title: Show Wiring (Spring4D DI + DFM events)
summary: "Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type"
product: DL
group: graphs-reports
order: 70019
since: 0.21.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Show Wiring (Spring4D DI + DFM events)

Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type.

Read this when you are tracing how an interface gets resolved or which handler a DFM event really calls: it shows the Spring4D container registrations and DFM event hookups the compiler does not make obvious.

## How to run it

Full flag list: [wiring in the CLI reference](../cli.md#wiring).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<IIntf\|TForm>` |  |  |
| `--db` | `<file.sqlite>` |  |  |
| `--format` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Show Wiring (Spring4D DI + DFM events)...**
   1. Open the unit that declares the type
   2. Choose drag-lint > Uses & Dependencies > Show Wiring (Spring4D DI + DFM events)...
   3. Read the container registrations and DFM event hookups for the type
   4. From a shell: `drag-lint wiring --qname <IIntf|TForm> [--db <file.sqlite>] [--format text|json]`

## Details

Surfaces bindings the compiler does not make obvious: Spring4D container
registrations and DFM event hookups for a type. Reach for it when tracing how
an interface gets resolved, or which handler a DFM event actually calls.

### Running it from the CLI
```text
drag-lint wiring --qname <IIntf|TForm> [--db <file.sqlite>] [--format text|json]
```
A separate coverage mode is also documented:
```text
drag-lint wiring --coverage [--db <file.sqlite>] [--format text|json]
```
which reports DI registrations that remain unresolved to an interface-to-type pairing.

### What it needs
Optional. An index is not marked required, but the wiring data comes from
whatever has been indexed.

### Example
Illustrative only:
```text
drag-lint wiring --qname MyApp.TfrmMain --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format text
```
This would list Spring4D DI registrations and DFM event edges touching `TfrmMain`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
