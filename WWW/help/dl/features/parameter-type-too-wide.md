---
id: parameter-type-too-wide
title: Parameter type too wide (lint rule)
summary: "Project lint rule, ON since 1.52 (warning, autofix): a class-typed parameter that an ancestor type could carry, proved by the narrow-param plan"
product: DL
group: linting
order: 30033
since: 1.46.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Parameter type too wide (lint rule)

Project lint rule, ON since 1.52 (warning, autofix): a class-typed parameter that an ancestor type could carry, proved by the narrow-param plan.

Read this to see what parameter-type-too-wide reports and how it relates to narrow-param. It runs in lint-all and lint-project over a project index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output|--report <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none] [--no-budget]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule parameter-type-too-wide
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A class-typed parameter whose routine only uses members that an ancestor of the declared type already declares. The signature promises more than the body needs, and callers are tied to the wider type. ON by default since 1.52 (a warning), with an autofix: see [v152-ptw](v152-ptw.md).

### Running it
```text
drag-lint lint-all --db <project.sqlite> --rule parameter-type-too-wide
drag-lint lint-project --db <project.sqlite> --rule parameter-type-too-wide
```

### What it reports
One warning per parameter, at the routine's declaration, naming the parameter, the narrower type and the unit that would join `uses`. It reports exactly the fixes of `drag-lint narrow-param --all --plan`; the proof (and every refusal: virtual, overloaded, published, interface method, member write, `with`, by-reference, ...) is that verb's, see its page. The refusals are not findings.

### Applying it
`drag-lint lint <unit.pas> --db <project.sqlite> --rule parameter-type-too-wide --fix --fix-rule parameter-type-too-wide --apply --project <x.dproj> --compile-gate` fixes the unit's findings (1.52); `drag-lint narrow-param --routine <name> --project <x.dproj> --apply` rewrites one routine through the compile gate.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
