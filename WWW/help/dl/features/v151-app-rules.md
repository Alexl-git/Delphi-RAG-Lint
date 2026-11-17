---
id: v151-app-rules
title: Application-level lint rules
summary: "Whole-program lint rules: TLS checks off, UI calls in console/service apps, DUnitX tests without asserts, weak ciphers, asm without Win64, GUI WriteLn"
product: DL
group: linting
order: 30047
since: 1.51.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Application-level lint rules

Whole-program lint rules: TLS checks off, UI calls in console/service apps, DUnitX tests without asserts, weak ciphers, asm without Win64, GUI WriteLn.

Read this to see what each application-level rule reports, which ship ON or OFF, and how the checks avoid the common false positives.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>]
```

Example:

```text
drag-lint lint <unit.pas> --rule tls-verification-disabled
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule writeln-in-gui-app
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Rules about what a whole program or unit does at run time rather than how one
statement is written. All are text-based, run per unit in `lint` and `lint-all`,
and need no index.

| Rule | Default | Severity | Fires on |
|---|---|---|---|
| `tls-verification-disabled` | ON | warning | certificate validation switched off in code (see the fixture for the recognised shapes) |
| `ui-call-in-console-or-service` | ON | warning | `ShowMessage`, `MessageDlg`, `Application.MessageBox` and similar in a console program, a service or a unit they own: nobody sees the dialog and the process hangs |
| `weak-cipher` | ON | warning | DES, 3DES, RC2, RC4 or ECB mode |
| `dunitx-test-without-assert` | ON | info | a DUnitX test method that checks nothing |
| `asm-without-win64-variant` | ON | warning | an `asm` block with no `{$IFDEF CPUX64}` variant and no Pascal fallback |
| `writeln-in-gui-app` | ON | warning | `Write` / `WriteLn` to the console in a VCL / FMX unit of a program with no console |
| `contract-unit-declares-class` | OFF | info | a unit named Intf, Interfaces or Contracts that declares a class: policy, enable with `--rule` |

`writeln-in-gui-app` skips a write whose first argument is a text-file or stream
variable, including one declared in another unit and named `*File`, `*Log`,
`*Txt`, `*Writer` or `*Stream`; it also skips code under `{$IFDEF CONSOLE}` /
`DEBUG` and routines that test `IsConsole`.

Known limit: `ui-call-in-console-or-service` looks at one file; a dialog call in a
unit a console project merely uses is not reported.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
