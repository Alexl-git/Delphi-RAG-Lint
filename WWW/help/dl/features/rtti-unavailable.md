---
id: rtti-unavailable
title: RTTI unavailable (lint rule)
summary: "Project lint rule, OFF by default: declarations that lose classic or extended RTTI (typeless enums, record properties, narrowing directives, published generics)"
product: DL
group: linting
order: 30036
since: 1.50.0-alpha
status: shipped
updated: 1.51.0-alpha
---

# RTTI unavailable (lint rule)

Project lint rule, OFF by default: declarations that lose classic or extended RTTI (typeless enums, record properties, narrowing directives, published generics).

Read this to see what rtti-unavailable reports and how generated persistence classes keep complete RTTI. It runs in lint-all, lint-project and lint over a project index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule rtti-unavailable
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Declarations that lose classic (TypInfo / TWriter streaming) or extended (`TRttiContext`) RTTI. Written for generated persistence classes -- ORM3's `COMMON\OBJECTS` units -- that must stay readable by a stream and by a future RTTI-based ORM. OFF by default.

### Running it
```text
drag-lint lint-all --db <project.sqlite> --rule rtti-unavailable
drag-lint lint <unit.pas> --db <project.sqlite> --rule rtti-unavailable
```
Opt in per project with `"enabled": ["rtti-unavailable"]` in `drag-lint-lint.json` or `--enable rtti-unavailable`. Pass the platform library index (`--db <library.sqlite>` on lint-all, `--library-db` on lint) so ancestors and record types declared in the RTL / VCL are known.

### What it reports
One finding per declaration or directive. The message starts with the sub-kind:

| sub-kind | fires on | severity |
|---|---|---|
| `enum-no-typeinfo` | an enum whose explicit ordinals are not 0, 1, 2, ... in order (`TGap = (gA = 1, gB = 3)`): the compiler emits no `PTypeInfo`, `TypeInfo(TGap)` fails with E2134; and every published property of such a type | warning |
| `published-record-property` | a published property of a record type (`TSQLTimeStamp`, `TBcd`, a project record): `TWriter.WriteComponent` skips it silently | warning; info when the class's `DefineProperties` names the property (streamed by hand) |
| `rtti-narrowing-directive` | `{$RTTI EXPLICIT ...}` whose METHODS / PROPERTIES / FIELDS set lacks `vcPublic` or `vcPublished`; `{$M-}` / `{$TYPEINFO OFF}` in effect over a published class without an RTTI-bearing ancestor; `{$WEAKLINKRTTI ON}` in a unit declaring `TComponent` descendants | warning |
| `published-without-persistent` | a class with a `published` section, no `TPersistent` ancestor and not declared under `{$M+}` | warning |
| `published-generic-method` | a generic method (`procedure Apply<X>`) in a `published` section: the compiler accepts it, but the method gets no method-table entry (`MethodAddress` returns nil, a stream cannot bind it as an event handler) and no extended RTTI | warning |
| `published-unstreamable-generic` | a published property whose generic type `TWriter` skips: `TArray<..>` (a dynamic array), `TProc` / `TFunc` / `TPredicate<..>` (a reference type), a generic class that does not reach `TPersistent` (`TList<..>`, `TDictionary<..>`, `TObjectList<..>`, ...), or a type parameter of the class constrained to `record` | warning; info when the class's `DefineProperties` names the property |

### Generic types
Measured with dcc64 and a runtime probe (Delphi 13): an open generic type (`TBox<T>`) has no RTTI of its own; every instantiation (`TBox<Integer>`) does, and the published properties of an instantiation keep their property info. So a generic class with a published section is not, by itself, a loss. What is lost:
- a published generic method (no method-table entry, no RTTI) -- `published-generic-method`;
- a published property whose type the stream cannot carry -- `published-unstreamable-generic`; a generic RECORD instantiation (`TPair<string, Integer>`) is reported as `published-record-property`.

The compiler itself rejects a published FIELD of a type-parameter type (E2217), so there is no rule for it.
### What it does not report
- An explicit ordinal that is not an integer literal (`cA = Ord('A')`) -- not judged.
- An ancestor that neither the project nor the library index (nor the short built-in RTL / VCL list) knows -- unknown, silent.
- A `{$RTTI EXPLICIT}` set named through a constant other than the RTL `Default*RttiVisibility` ones -- not judged.
- A published property of an unconstrained or class-constrained type parameter (`property Value: T`) -- its streamability depends on the instantiation; not judged.
- Anonymous property types (sub-check 5 of the request): a Delphi property declaration requires a type identifier, so there is nothing to find.

### Fixing it
- Enums: never renumber a persisted enum. Add RTTI-safe filler values so the ordinals become contiguous from 0, or use a contiguous enum plus a code map.
- Record properties: stream them in an overridden `DefineProperties` (`Filer.DefineProperty` / `DefineBinaryProperty`); the finding then drops to info.
- Directives: keep `vcPublic` and `vcPublished` in every `{$RTTI EXPLICIT}` set; remove `{$WEAKLINKRTTI ON}` from units that declare persistent classes.
- Generic members: move a generic method out of `published`, or publish a non-generic wrapper; stream a generic collection or array in `DefineProperties`, or make the property public when only code reads it.
- Classes: derive from `TPersistent` (or `TInterfacedPersistent`), or declare the class under `{$M+}`.

### Fixture and guard
`tests\lint-project\rtti-unavailable\` (the request's snippet plus a clean component unit and a stand-in library) and `run_rtti_unavailable.ps1`; generic types: `tests\autotest\fixtures\v151-RTTI2\generic\` (every construct compiles with dcc64) and `tests\autotest\run_v151_RTTI2_generic.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
