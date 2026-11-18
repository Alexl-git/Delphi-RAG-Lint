---
id: v152-atla-rules
title: Reserved words as names, implicit package imports, contract-unit globs
summary: reserved-word-identifier and implicit-package-import rules; contractUnits globs in drag-lint.json for contract-unit-declares-class
product: DL
group: linting
order: 30066
since: 1.52.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Reserved words as names, implicit package imports, contract-unit globs

reserved-word-identifier and implicit-package-import rules; contractUnits globs in drag-lint.json for contract-unit-declares-class.

Read this to see what the two rules new in 1.52 report, how contract units can be named by glob, and why noreturn-returns is not in 1.52.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>] [--no-budget]
```

Example:

```text
drag-lint lint <unit.pas> --rule reserved-word-identifier
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output|--report <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none] [--no-budget]
```

Example:

```text
drag-lint lint-all --db <package.sqlite> --project <Package.dproj> --rule implicit-package-import
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Three checks added in 1.52. Each one reads the parse tree of one file, so
`lint` (CLI, IDE, LSP) and `lint-all` report them the same way.

### reserved-word-identifier (ON, warning)

A Delphi reserved word used as the name of a variable, field, parameter,
constant or type. The parser accepts directive-like words such as `Inline` and
`Library` as names, but dcc stops with *E2029 Identifier expected*.

```pascal
type
  TOptions = record
    Inline: Boolean;      // reported
    &Library: Boolean;    // fine: the & escape makes it a plain identifier
  end;
```

Only dcc's reserved words are checked (`and`, `array`, ... `inline`, `library`,
`object`, `string`, ... `xor`). Directives such as `at`, `on`, `name`,
`message`, `index`, `read` are legal names and never reported.

Fix: rename the identifier, or escape it with `&`.

### implicit-package-import (ON, warning)

In a package (`.dpk`), a unit from the `contains` clause uses a project unit
that is neither in `contains` nor in a required package. dcc then imports the
unit into the package implicitly (warning W1033), and two packages can end up
holding the same unit.

The finding sits on the `uses` entry. A used unit is reported only when its
source file `<Unit>.pas` is found in the package folder or in the folder of a
contained unit; RTL, VCL and other units without a source file there are taken
to come from a required package. Units of a required package count as provided
when its `.dpk` is found beside the package (same folder, parent folder or a
sibling folder).

`lint <unit.pas>` finds the package in the unit's folder or its parent folder.
`lint-all --project <Package.dproj>` also checks contained units that live
further away.

Fix: add the unit to `contains`, or add the package that contains it to `requires`.

### contract-unit-declares-class: units named in drag-lint.json

The existing rule `contract-unit-declares-class` (OFF by default) reports a
class declared in the interface section of a contract unit. By default a
contract unit is a unit whose last name segment is `Contract(s)`, `Intf`,
`Interface(s)` or `Abstraction(s)`, for example `App.Orders.Contract`.

From 1.52 you can name more contract units with globs in `drag-lint.json`:

```json
{ "contractUnits": ["App.*.Api", "Shared.Types.*"] }
```

`*` and `?` are the wildcards; matching ignores case. A unit that both the
name rule and a glob match is reported once. Exempt: `class of` types, forward
declarations, and classes derived from `Exception` or an `E*` class.

Turn the rule on with `--enable contract-unit-declares-class` or
`"enabled": ["contract-unit-declares-class"]` in the lint config.

### Not in 1.52

`noreturn-returns` (a `noreturn` routine that can return normally) needs the
index to record which routines are `noreturn`, across units and the RTL. That
is an indexer change; this release does not ship the rule.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
