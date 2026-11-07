---
id: bookmarks
title: bookmarks
summary: "Lists or finds the dl:bk comment-anchor bookmarks in a unit or a folder"
product: DL
group: documentation
order: 40001
since: 1.46.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# bookmarks

Lists or finds the dl:bk comment-anchor bookmarks in a unit or a folder.

Read this when you marked code with // dl:bk3 or // dl:bk:A7K3QX comments and want them listed, or one found by its code: bookmarks prints file:line for each anchor and never writes.

## How to run it

Full flag list: [bookmarks in the CLI reference](../cli.md#bookmarks).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `<file.pas\|dir>` |  |  |
| `--name` | `<code>` |  |  |
| `--json` |  |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Lists or finds the `dl:bk` comment-anchor bookmarks in a unit or a folder. Reach
for it when you marked code with a comment and want every mark listed, or one
mark found by its code.

### What a bookmark is

A bookmark is an ordinary `//` comment whose first token is the tag, so it moves
with its code through edits, reformatting and moves between units. Two kinds:

```text
Foo;   // dl:bk3                           a user bookmark; N is any integer
Bar;   // dl:bk:A7K3QX -- lock order       a DL bookmark: 6-8 letters or digits, then an optional reason
Baz;   // dl:bk12@7f3a                     either kind may carry the construct hash
```

Anything else is not a bookmark: the tag inside a string literal, inside a brace
or star-paren comment, in the middle of a comment's prose, or a DL tag whose code
is not 6-8 characters.

### Running it from the CLI

```text
drag-lint bookmarks --in <file.pas|dir> [--name <code>] [--json]
```

`--in` is a unit or a folder (every `.pas` below it). `--name <code>` keeps only
the anchors with that code (tagged codes match case-insensitively). Output is one
line per anchor, `file:line  kind  code  [@hash]  [-- reason]`; `--json` prints a
bare array of `file`, `line`, `kind`, `code`, `hash`, `reason`. Exit 0 with hits,
3 with none, 1 without `--in`, 2 for a missing path.

The verb only reads. Bookmarks are ordinary committed comments (owner ruling
2026-09-22), so there is no strip or restore here.

### What it needs

No index: the usage line has no `--db` flag; the verb scans the text of the files.

### Example

```text
drag-lint bookmarks --in C:\Projects\App\src --name A7K3QX
```

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
