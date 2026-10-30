---
id: outline
title: outline
summary: Prints the file-scoped symbol outline for one Pascal unit
product: DL
group: search-navigation
order: 20017
since: 0.86.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# outline

Prints the file-scoped symbol outline for one Pascal unit.

Read this when you want a unit symbol list outside the IDE, or want to see what feeds the Structure tree. Give it a .pas file and it prints that file symbol outline as text or JSON.

## How to run it

Full flag list: [outline in the CLI reference](../cli.md#outline).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `<path.pas>` |  |  |
| `--db` | `<path>` |  |  |
| `--format` |  |  |  |
| `--json` |  |  |  |
| `--kind` | `<k[,k...]>` |  |  |
| `--no-locals` |  |  |  |
| `--limit` | `N` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Show Structure**
   1. Open the unit in the editor
   2. drag-lint > Show Structure
   3. The Structure form lists the unit's symbols

## Details

Prints the file-scoped symbol outline for one Pascal unit. Reach for it when
you want a unit's symbol list outside the IDE, or want to understand what
feeds the Structure tree.

### Running it from the CLI
```text
drag-lint outline --in <path.pas> [--db <path>] [--format text|json]
                  [--kind <k[,k...]>] [--no-locals] [--limit N]
```
`--in <path.pas>` is the unit to outline. `--db <path>` is optional;
without it the database is resolved **from the file being read**. `--format`
selects `text` or `json`.

The outline lists every symbol, locals and parameters included -- a large unit
runs to thousands of rows. Three options narrow it, and without them nothing is
left out (the IDE's Structure form reads it whole):

* `--kind <k[,k...]>` keeps only those kinds, spelled as the outline prints them
  (`class`, `method`, `field`, `property`, ...);
* `--no-locals` drops the `local_var` and `param` rows;
* `--limit N` prints the first N rows and says how many matched -- on the last
  line in text, on stderr with `--format json` (the array stays the document).

### How the database is resolved

Without `--db`, `outline` resolves the same way
[`resolve-dbs --in <file>`](show-resolved-dbs-debug.md) does -- the manifest's
folder-based candidates **plus a membership probe** that asks each candidate
index whether it actually contains the file. It then reads from the first index
that holds the file.

The probe is what makes a unit living **outside its own `.dproj`'s folder**
resolvable -- a common shape, since a project file in one directory routinely
pulls in units from a dozen siblings. Before this, `outline` resolved only from
`--platform` / the current directory / the manifest default, and could report
"no project database resolves here" for a file `resolve-dbs --in` listed three
databases for.

A file that is in **no** index is refused (exit `2`) rather than answered with
an empty outline, which would be indistinguishable from a unit that declares
nothing.

### Forward declarations

A forward stub (`TFoo = class;` completed later in the same unit) and its real
declaration BOTH stay listed, and the stub row is tagged `[forward -> line N]`
(JSON: `forward_target_line`). Everywhere else a name is looked up -- `query`,
`hover`, completion, class metrics -- the stub is folded into the real
declaration. A lone stub with no completion in the unit is still a class.

### What it needs
Optional, per the feature map's Index column.

### Example
Illustrative only:
```text
drag-lint outline --in C:\Projects\MyApp\frmOrders.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```
This would print the symbol outline of `frmOrders.pas` as JSON -- the same
data the Structure form displays as a tree.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
