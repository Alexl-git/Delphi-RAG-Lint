---
id: ref-type-rules
title: Lint rules on the static type of a reference
summary: "Project lint rules on the static type of a reference (ref_types): is-always-true, argument-narrows and three more; sharper redundant-cast and unsafe casts"
product: DL
group: linting
order: 30031
since: 1.44.1-alpha
status: shipped
updated: 1.44.1-alpha
---

# Lint rules on the static type of a reference

Project lint rules on the static type of a reference (ref_types): is-always-true, argument-narrows and three more; sharper redundant-cast and unsafe casts.

Read this to see which rules stand on ref_types, what each reports and what keeps it silent. They run in lint-all and lint-project over a 1.44 index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule argument-narrows
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Rules that read index fact F1, the `ref_types` table: the static type of a reference, written by the
resolve pass. They run in `lint-all` and `lint-project`, and for one file in `lint <file> --db` when
the rule ships ON. An index older than 1.44 has no such table and these rules answer nothing there.

```text
drag-lint lint-all --db <project.sqlite> --rule is-always-true
drag-lint lint-all --db <project.sqlite> --rule argument-narrows
```

| Rule | Default | Reports |
|---|---|---|
| `is-always-true` | ON | `x is T` where the static type of `x` already descends from `T`: the test only asks whether `x` is nil |
| `upcast-then-downcast` | ON | `TLeaf(TBase(x))` or `(x as TBase) as TLeaf` where `x` already is a `TBase` |
| `with-on-temporary` | ON | `with TFoo.Create do` with no free in the body and no owner taking the object |
| `interface-holder-of-non-refcounted` | ON | An interface variable assigned a `TComponent` / `TNoRefCountObject` / `TSingletonImplementation` descendant (a variable, `as`, a constructor, `Self`) |
| `argument-narrows` | ON | A variable, field or function result passed to a narrower by-value numeric parameter of a project routine |
| `redundant-cast` | ON | Also `T(a.b)`, `T(F(x))` and `x as T`; the index overrules the per-file type map for `T(x)` |
| `unsafe-typecast-without-is` | OFF | Also `T(a.b)` and `T(F(x))`; with a row in `ref_types` the rule fires only when both ends are classes and the cast narrows |

### What keeps a rule silent

An expression has a static type only as a single name, a member chain, a call, a hard cast or an `as`.
A subscript has none: the row of `List` in `List[i]` types the list, not the element. Neither has a
bare name inside a `with` body, because it may bind to a member of the with-expression.

A class's ancestry is `type_ancestors` in the project, continued by name in the library index. A
homonym keeps only the ancestors every class of that name shares, so it can silence a rule but never
make one fire. Without a library index a class on a library base has an incomplete ancestry.

`argument-narrows` skips overloaded callees (the resolver's overload choice is not proof of a
width), `var` and `out` parameters, constants and expressions other than a single name, chain or call.
Library callees are not checked.

`with-on-temporary` reports constructors only: a function's result may be owned elsewhere.

### Not a rule: `is-never-true`

`x is T` with unrelated classes does not compile (E2010), so in compiling code every finding of that
shape would be an index error. `Intf is TSealed` compiles and can be proved, but the index does not
record `sealed`, and that shape needs an extractor change for a test almost nobody writes.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
