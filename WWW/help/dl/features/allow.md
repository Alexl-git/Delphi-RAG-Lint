---
id: allow
title: allow
summary: "Records a dl:ok review of one finding, so it stops being reported without being fixed"
product: DL
group: refactoring
order: 50001
since: 0.54.0-alpha
status: shipped
updated: 1.32.0-alpha
---

# allow

Records a dl:ok review of one finding, so it stops being reported without being fixed.

## How to run it

Full flag list: [allow in the CLI reference](../cli.md#allow).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--fix-line` | `<L>` |  |  |
| `--fix-rule` | `<id>` |  |  |
| `--apply` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--config` | `<file>` |  |  |
| `--profile` | `<name>` |  |  |
| `--enable` |  |  |  |
| `--disable` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

## Details

Records a `dl:ok` review of one finding, so it stops being reported without
being fixed. Reach for it when a lint finding is a deliberate, reviewed
exception rather than something you intend to change.

### Running it from the CLI

```text
drag-lint allow <file> --fix-line <L> --fix-rule <id> [--apply]
```

`--fix-line` and `--fix-rule` identify the exact finding to allow. Per the
usage banner, this is a dry run without `--apply`: "record a dl:ok review of
ONE finding; dry-run without --apply".

### Reaching it in the IDE

Reachable in the IDE through the Structure form's right-click menu -- see
[Allow this message](allow-this-message.md) for the IDE-side walkthrough
(drag-lint > Show Structure, then right-click a finding and choose "Allow
this message"). There is no main-menu item; the feature map's internal call
site is `DragLint.Plugin.StructureForm.pas:1061`.

### What it needs

No index required -- `allow` records the review directly against the given
file (a `dl:ok` marker), without going through a project index database.

### Example

Illustrative:

```text
drag-lint allow C:\Projects\MyApp\Unit1.pas --fix-line 42 --fix-rule unused-private-member --apply
```

This would record `Unit1.pas` line 42's `unused-private-member` finding as
reviewed, so it no longer appears in future lint runs.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
