---
id: parameter-type-too-wide
title: Parameter type too wide (lint rule)
summary: "Project lint rule, OFF by default: a class-typed parameter that an ancestor type could carry, proved by the narrow-param plan"
product: DL
group: linting
order: 30032
since: 1.46.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Parameter type too wide (lint rule)

Project lint rule, OFF by default: a class-typed parameter that an ancestor type could carry, proved by the narrow-param plan.

Read this to see what parameter-type-too-wide reports and how it relates to narrow-param. It runs in lint-all and lint-project over a project index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule parameter-type-too-wide
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A class-typed parameter whose routine only uses members that an ancestor of the declared type already declares. The signature promises more than the body needs, and callers are tied to the wider type. OFF by default.

### Running it
```text
drag-lint lint-all --db <project.sqlite> --rule parameter-type-too-wide
drag-lint lint-project --db <project.sqlite> --rule parameter-type-too-wide
```

### What it reports
One hint per parameter, at the routine's declaration, naming the parameter, the narrower type and the unit that would join `uses`. It reports exactly the fixes of `drag-lint narrow-param --all --plan`; the proof (and every refusal: virtual, overloaded, published, interface method, member write, `with`, by-reference, ...) is that verb's, see its page. The refusals are not findings.

### Applying it
`drag-lint narrow-param --routine <name> --project <x.dproj> --apply` rewrites the parameter through the compile gate.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
