---
id: interfaced-object-nil-leak
title: Interfaced object set to nil (lint rule)
summary: "Lint rule, OFF by default: an object reference to a TInterfacedObject descendant is set to nil while it holds a fresh instance, which leaks it"
product: DL
group: linting
order: 30019
since: 1.42.0-alpha
status: shipped
updated: 1.42.0-alpha
---

# Interfaced object set to nil (lint rule)

Lint rule, OFF by default: an object reference to a TInterfacedObject descendant is set to nil while it holds a fresh instance, which leaks it.

Read this to see when X := nil leaks a TInterfacedObject descendant and when it only clears an alias. Works per file; an index widens the class-descent check beyond the file.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule interfaced-object-nil-leak
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

An OBJECT reference to a `TInterfacedObject` descendant is set to `nil` while it holds a fresh instance. Only an interface reference counts; an object reference holds no count, so `nil` releases nothing and the instance leaks. OFF by default.

```pascal
function Build: TThing;      // TThing = class(TInterfacedObject, IThing)
begin
  try
    Result := TThing.Create;
    Result.Load;
  except
    Result := nil;           // finding: the instance leaks. Return IThing, or Free it.
  end;
end;
```

### Running it
```text
drag-lint lint <file> --rule interfaced-object-nil-leak
drag-lint lint-all --db <project.sqlite> --rule interfaced-object-nil-leak
```

### What stays silent
- `Result := nil` with no instance created before it (the find idiom).
- A reference that may have reached an interface holder first: a bare use (`I := T`, `Sink(T)`) or a method call on it (`T.Subscribe` can hand over Self). In those cases the `nil` only clears an alias.
- A variable typed as an interface.
- `T.Free` before the `nil`.
- `if C then X := T.Create else X := nil`: the two are on different branches.
- A class whose chain to `TInterfacedObject` is unknown. The rule reads the same file, then the index.
- A plain class. That is a different leak, and not what this rule is about.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
