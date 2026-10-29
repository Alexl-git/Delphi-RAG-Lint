---
id: lint-project
title: lint-project
summary: Runs project-scoped structural lint rules against an index -- checks such as god-class, unused-public-symbol
product: DL
group: linting
order: 30016
since: 0.48.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# lint-project

Runs project-scoped structural lint rules against an index -- checks such as god-class, unused-public-symbol.

Read this when you want architecture-level findings that need the whole project, such as god-class, circular-uses, unused-public-symbol or layering-violation, rather than per-file diagnostics. It runs those project-scoped rules against an index.

## How to run it

Full flag list: [lint-project in the CLI reference](../cli.md#lint-project).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--db` | `<file.sqlite>` |  |  |
| `--rule` |  |  |  |
| `--layers` | `<f.json>` |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Project Structure Rules (god-class, layering...)...**
   1. Needs an index of the project
   2. drag-lint > Code Quality > Project Structure Rules (god-class, layering...)...
   3. Pick the rule; its project-wide findings are listed

**Needs:** index

## Details

Runs project-scoped structural lint rules against an index -- checks such as
god-class, unused-public-symbol, circular-uses and layering-violation that
need whole-project context rather than a single file. Reach for it for
cross-file architectural findings, not per-file diagnostics.

### Running it from the CLI

```text
drag-lint lint-project --db <file.sqlite> [--rule god-class|unused-public-symbol|interface-reference-cycle|layering-violation|unused-private-member|unused-unit-in-uses|circular-uses|repeated-type-switch|global-only-uses-edge|duplicate-global-decl|uses-global-census|discarded-effect-free-result|query-name-with-effect|assert-with-side-effect|enum-ordinal-persisted] [--layers <f.json>] [--json]
```

### enum-ordinal-persisted

ON by default (warning). Flags an enum type whose ORDINAL crosses a
persistence boundary while some of its values have implicit ordinals --
inserting or reordering a value would then silently change what stored data
means. It fires when all three hold:

1. an ordinal cast of the enum: a hard cast `TKind(x)` (cast-in, bound to the
   type by the index since lane X6) or `Ord(v)` / `Integer(v)` / `Byte(v)` /
   ... on a line with exactly one ref bound to that enum (cast-out);
2. a SINK named in the same routine -- the names in
   `rules\enum-persist-sinks.txt` beside the engine (stream / pipe:
   `WriteBuffer`, `ReadMessage`, ...; dataset: `FieldByName`, `AsInteger`, ...;
   registry / ini: `WriteInteger`, ...). Edit the file to widen or narrow it; if
   it is missing the same list is compiled in;
3. at least one value has no explicit `= N` (comments do not count as a pin).

One finding per enum, at its declaration; the message names one boundary site
and its sink. Fix: pin every value (`kA = 0, kB = 1, ...`).
### What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

### Example

Illustrative only:

```text
drag-lint lint-project --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --rule circular-uses --json
```

This would report circular-uses findings for `MyApp` as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
