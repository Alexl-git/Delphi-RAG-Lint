---
id: rtti-unavailable
title: RTTI unavailable (lint rule)
summary: "Project lint rule, OFF by default: declarations that lose classic or extended RTTI (enums without type info, record properties, narrowing directives)"
product: DL
group: linting
order: 30036
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# RTTI unavailable (lint rule)

Project lint rule, OFF by default: declarations that lose classic or extended RTTI (enums without type info, record properties, narrowing directives).

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

### What it does not report
- An explicit ordinal that is not an integer literal (`cA = Ord('A')`) -- not judged.
- An ancestor that neither the project nor the library index (nor the short built-in RTL / VCL list) knows -- unknown, silent.
- A `{$RTTI EXPLICIT}` set named through a constant other than the RTL `Default*RttiVisibility` ones -- not judged.
- Anonymous property types (sub-check 5 of the request): a Delphi property declaration requires a type identifier, so there is nothing to find.

### Fixing it
- Enums: never renumber a persisted enum. Add RTTI-safe filler values so the ordinals become contiguous from 0, or use a contiguous enum plus a code map.
- Record properties: stream them in an overridden `DefineProperties` (`Filer.DefineProperty` / `DefineBinaryProperty`); the finding then drops to info.
- Directives: keep `vcPublic` and `vcPublished` in every `{$RTTI EXPLICIT}` set; remove `{$WEAKLINKRTTI ON}` from units that declare persistent classes.
- Classes: derive from `TPersistent` (or `TInterfacedPersistent`), or declare the class under `{$M+}`.

### Fixture and guard
`tests\lint-project\rtti-unavailable\` (the request's snippet plus a clean component unit and a stand-in library) and `run_rtti_unavailable.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
