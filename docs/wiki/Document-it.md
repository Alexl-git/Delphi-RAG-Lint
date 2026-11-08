# Document it

Generates or repairs a managed DocInsight comment on the single symbol
represented by a Structure-tree node. Reach for it when one declaration
needs a doc comment and you do not want to touch the rest of the unit.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click a node in the tree and choose "Document it".

## Running it from the CLI

The feature map lists the underlying verb as `document`. From the usage
banner, the single-symbol form:

```
drag-lint document --qname <Foo.TBar.Baz> [--apply|--json|--no-backup] [--db PATH]
```

Generates/repairs a managed DocInsight comment for that one qualified name.

On a property or field with resolved uses the managed block says where it is
used, with the access mode: `Used in: uCons.TConsumer.Go (uCons.pas) [rw]`. That
line replaces the name-matched `Used by:` (wave 147, on by default); with no
resolved use the `Used by:` line is written as before.

Since wave 148 the line also lists uses that only another project's index
records (`document --db A --db B`: the extra `--db` is asked by the full
qualified name), and a getter or setter keeps `Called from:` and gains
`Used in (via property Value): uCons.TConsumer.Go (uCons.pas) [r]` -- the
property accesses that ran it. Expect a one-time rewrite: the first
`document --apply` on a project rewrites every such block, and `doc-drift`
reports them as a stale facts block until it has run.

## What it needs

Optional, per the feature map's Index column.

## Example

Illustrative:

```
drag-lint document --qname Unit1.TMyClass.DoWork --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would write a managed DocInsight comment onto `DoWork`.
