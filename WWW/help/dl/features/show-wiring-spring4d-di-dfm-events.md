---
id: show-wiring-spring4d-di-dfm-events
title: Show Wiring (Spring4D DI + DFM events)
summary: "Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type"
product: DL
group: graphs-reports
order: 70017
since: 0.21.0-alpha
status: shipped
updated: 0.21.0-alpha
---

# Show Wiring (Spring4D DI + DFM events)

Surfaces bindings the compiler does not make obvious: Spring4D container registrations and DFM event hookups for a type.

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
which reports DI registrations not yet resolved to an interface-to-type pairing.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Show Wiring (Spring4D DI + DFM events)...

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
