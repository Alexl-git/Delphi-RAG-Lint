# outline

Prints the file-scoped symbol outline for one Pascal unit. Reach for it when
you want a unit's symbol list outside the IDE, or want to understand what
feeds the Structure tree.

## Running it from the CLI
```
drag-lint outline --file <path.pas> [--db <path>] [--format text|json]
```
`--file <path.pas>` is the unit to outline. `--db <path>` is optional;
without it the database is resolved **from the file being read**. `--format`
selects `text` or `json`.

## How the database is resolved

Without `--db`, `outline` resolves the same way
[`resolve-dbs --in <file>`](Show-Resolved-DBs-debug.md) does -- the manifest's
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

## Reaching it in the IDE
No menu item calls this directly. The plugin's structure cache
(StructureCache.pas:338) shells out to this verb to populate the Structure
form/tree used by "Show Structure" and the drag-lint Panel (dockable),
caching the result per file.

## What it needs
Optional, per the feature map's Index column.

## Example
Illustrative only:
```
drag-lint outline --file C:\Projects\MyApp\frmOrders.pas --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format json
```
This would print the symbol outline of `frmOrders.pas` as JSON -- the same
data the Structure form displays as a tree.
