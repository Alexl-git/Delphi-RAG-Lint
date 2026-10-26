# Show in Call Graph

Opens the call graph rooted at the symbol represented by a Structure-tree
node. Reach for it when you want to see who calls (or is called by) a
symbol you are already looking at in the Structure outline. It opens the
dock's Call Graph (Butterfly) tab with callers AND callees, depth 3 in each
direction (the same path as [Call Graph (Butterfly)](Call-Graph-Butterfly)).

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Show in Call Graph".

## Running it from the CLI

The feature map lists the underlying verb as `reverse-calltree`; the IDE runs it
twice with `--depth 3 --format json` (once plain for callers, once with
`--direction callees`) and composes the Butterfly tab from both. From the
usage banner:

```
drag-lint reverse-calltree --qname <X> [--direction callers|callees] [--depth N] [--format text|json|dot|mermaid] [--json] --db PATH [--db ...]
```

callers = who calls X (default), callees = what X calls; cycle-guarded.

## What it needs

An index IS required -- `reverse-calltree` reads the project's index
database. The project's DB lives at `<project folder>\_D-RAG\<project file>.sqlite`; run `drag-lint resolve-dbs --project <X.dproj>` if you are
unsure which one.

## Example

Illustrative:

```
drag-lint reverse-calltree --qname Unit1.TMyClass.DoWork --direction callers --depth 2 --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite --format text
```

This would print the callers of `DoWork`, two levels deep.
