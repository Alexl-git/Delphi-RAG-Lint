---
id: document-it
title: Document it
summary: Generates or repairs a managed DocInsight comment on the single symbol represented by a Structure-tree node
product: DL
group: documentation
order: 40007
since: 0.90.0-alpha
status: shipped
updated: 1.47.0-alpha
---

# Document it

Generates or repairs a managed DocInsight comment on the single symbol represented by a Structure-tree node.

Read this when one declaration needs a doc comment and you do not want to touch the rest of the unit. Right-click the symbol in the Structure form and choose Document it to generate or repair its managed DocInsight comment.

## How to run it

Full flag list: [document in the CLI reference](../cli.md#document).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--migrate-pure` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* Right-click in the Structure form: **Document it**
   1. Open the Structure form (drag-lint > Show Structure)
   2. Right-click the symbol node
   3. Choose Document it; its managed DocInsight comment is generated or repaired

## Details

Generates or repairs a managed DocInsight comment on the single symbol
represented by a Structure-tree node. Reach for it when one declaration
needs a doc comment and you do not want to touch the rest of the unit.

### Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the single-symbol form:

```text
drag-lint document --qname <Foo.TBar.Baz> [--apply|--json|--no-backup] [--db PATH]
```

Generates/repairs a managed DocInsight comment for that one qualified name.

On a property or field with resolved uses the managed block says where it is
used, with the access mode: `Used in: uCons.TConsumer.Go (uCons.pas) [rw]`. That
line replaces the name-matched `Used by:` (wave 147, on by default); with no
resolved use the `Used by:` line is written as before.

### What it needs

Optional, per the feature map's Index column.

### Example

Illustrative:

```text
drag-lint document --qname Unit1.TMyClass.DoWork --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write a managed DocInsight comment onto `DoWork`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
