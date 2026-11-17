---
id: v151-oo-rules
title: Object-model lint rules (Equals/hash, events, GUIDs, exports)
summary: "Ten single-file lint rules: Equals/GetHashCode, event calls, duplicate GUIDs, DLL exports, money as float, default params, accessors, forwards, legacy lists"
product: DL
group: linting
order: 30054
since: 1.51.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Object-model lint rules (Equals/hash, events, GUIDs, exports)

Ten single-file lint rules: Equals/GetHashCode, event calls, duplicate GUIDs, DLL exports, money as float, default params, accessors, forwards, legacy lists.

Read this to see what each object-model rule reports, which ship ON and what keeps them silent.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Ten rules that read one file's parse tree; none needs the index. Run them with `drag-lint lint <file>` or
`drag-lint lint-all --db <project.sqlite> --rule <id>`. A rule that ships OFF is switched on with `--rule <id>`
or `"enabled"` in the config.

| Rule | Default | Reports |
|---|---|---|
| `equals-without-gethashcode` | ON | A class overrides `Equals(Obj)` but not `GetHashCode`, or the reverse |
| `event-call-without-assigned` | ON | A method calls an event field (or the property reading it) with no `Assigned` / `<> nil` test of it in the same routine; event types are `T*Event`, `T*Notify`, `T*Callback`, `T*Handler`, `T*Proc` or a procedural type of the file |
| `duplicate-interface-guid` | ON | Two interfaces of one file carry the same GUID (case-insensitive); a dispinterface sharing the GUID of its dual interface is exempt. Cross-unit duplicates wait for the GUID fact of lane EXT |
| `dll-export-unsafe` | ON | A routine listed in `exports` has no stdcall / cdecl / safecall / winapi / pascal convention |
| `money-as-float` | ON | A field, variable, parameter or property whose name has a money word (price, preis, betrag, amount, cost ...) typed Double / Single / Extended / Real; names with percent, rate, factor, count ... are exempt |
| `default-parameter` | OFF | A parameter with a default value (style) |
| `trivial-accessor` | OFF | A getter that only returns a field, a setter that only assigns one, named by a property of the same class (non-virtual) |
| `unneeded-forward-declaration` | OFF | `TFoo = class;` / `interface;` whose full declaration follows in the same type block with no mention of the name between them |
| `legacy-tlist` | OFF | Items of a non-generic `TList` / `TObjectList` read through `T(L[i])`, `T(L.Items[i])`, `T(L.First)` or `as T` |
| `legacy-stack-queue` | OFF | `T(S.Pop)` / `Peek` / `Extract` on a non-generic stack or queue |

`noreturn-returns` is not added: the compiler already reports W1080 for a noreturn routine that can return.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
