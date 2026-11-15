---
id: v151-exc-rules
title: Exception and inherited lint rules
summary: "Lint rules for exception handlers and inherited calls: shadowed handlers, hand-freed exceptions, wrong or missing inherited, Destroy for Free"
product: DL
group: linting
order: 30045
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Exception and inherited lint rules

Lint rules for exception handlers and inherited calls: shadowed handlers, hand-freed exceptions, wrong or missing inherited, Destroy for Free.

Read this to see what each exception and inherited rule reports, which ship ON or OFF, and why inherited-order is OFF by default.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Rules about exception handlers and `inherited` calls. They walk the syntax tree
per unit in `lint` and `lint-all`; ancestor questions (does a base class declare
this method?) use the project index plus the platform library index.

| Rule | Default | Severity | Fires on |
|---|---|---|---|
| `except-handler-order` | ON | warning | an `on E: T do` handler that an earlier handler for an ancestor type already catches |
| `exception-freed` | ON | warning | `E.Free` inside the handler that received `E`: the RTL frees it |
| `inherited-wrong-method` | ON | warning | an override that calls `inherited` of a different method |
| `message-handler-without-inherited` | ON | warning | a `message` handler with neither `inherited` nor `DefaultHandler` |
| `inherited-without-ancestor` | ON | warning | a bare `inherited` in a method that no ancestor declares |
| `override-only-inherited` | ON | hint | an override whose body is only `inherited` |
| `destroy-called-directly` | ON | warning | `X.Destroy` instead of `X.Free` |
| `missing-inherited-call` | ON | warning | `Loaded`, `CreateParams` and similar component hooks overridden without `inherited` |
| `inherited-order` | OFF | warning | a destructor that calls `inherited` before freeing its own members |

`inherited-order` is OFF by default: over the four sample projects 4 of its 5
findings were `TThread` descendants, where `inherited Destroy` must run first
because it waits for `Execute`. Enable it with `--rule inherited-order` or the
config key `"enabled"`. It stays OFF until classes with a `TThread` ancestor are exempted.

The other eight rules produced no findings over the same projects.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
