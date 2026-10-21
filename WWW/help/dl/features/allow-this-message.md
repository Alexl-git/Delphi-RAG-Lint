---
id: allow-this-message
title: Allow this message
summary: "Records a dl:ok review of one finding, so it stops being reported without being fixed"
product: DL
group: refactoring
order: 50002
since: 0.54.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Allow this message

Records a dl:ok review of one finding, so it stops being reported without being fixed.

Read this when a finding in the Structure form is a deliberate, reviewed exception rather than something to change. Right-click the finding and choose Allow this message to record a dl:ok review so it stops being reported.

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

## Where to click

* Right-click in the Structure form: **Allow this message**

## Details

Records a `dl:ok` review of one finding, so it stops being reported without
being fixed. Reach for it when a finding is a deliberate, reviewed
exception rather than something to change.

### Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

**The Structure form's right-click menu is the only place "Allow this
message" is reachable in the IDE** -- there is no main drag-lint menu item
for it.

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click the tree node for a finding and choose "Allow this
message".

### Running it from the CLI

The feature map lists the underlying verb as `allow`. From the usage
banner:

```text
drag-lint allow <file> --fix-line <L> --fix-rule <id> [--apply]
```

Records a `dl:ok` review of one finding; dry-run without `--apply`.

### What it needs

No index required -- `allow` records the review directly against the given
file, without going through a project index database.

### Example

Illustrative:

```text
drag-lint allow C:\Projects\MyApp\Unit1.pas --fix-line 42 --fix-rule unused-private-member --apply
```

This would record `Unit1.pas` line 42's `unused-private-member` finding as
reviewed, so it no longer appears in future lint runs.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
