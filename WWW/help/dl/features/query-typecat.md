---
id: query-typecat
title: query typecat
summary: Resolves a type's category -- float, string, class, interface, and so on
product: DL
group: search-navigation
order: 20025
since: 0.66.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# query typecat

Resolves a type's category -- float, string, class, interface, and so on.

Read this when you need to know what kind of type a name is, such as float, string, class or interface, before writing code against it. Give it the type name and it resolves the category from the index.

## How to run it

Full flag list: [query in the CLI reference](../cli.md#query).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--name` | `<type>` |  |  |
| `--db` |  |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Resolves a type's category -- float, string, class, interface, and so on.
Reach for it when you need to know what kind of type a name refers to
before writing code against it.

### Running it from the CLI

```text
drag-lint query typecat --name <type> [--db ...] [--json]
```

`--name` is the type to resolve.

### What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example

Illustrative:

```text
drag-lint query typecat --name Currency --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would report which type category `Currency` resolves to.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
