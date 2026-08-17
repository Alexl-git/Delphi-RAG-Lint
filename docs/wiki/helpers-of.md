# helpers-of

Lists record/class helper edges targeting a given type, anywhere in the
index. Reach for it to see which helpers extend a type across the whole
indexed codebase.

## Running it from the CLI

```
drag-lint helpers-of <T> [--json] --db <db>
```

`<T>` is the target type name. `--db` is required (not bracketed in the
usage line). This verb has no `--apply` flag -- it is a read-only listing.

## Reaching it in the IDE

Reachable in the IDE only through the Structure form's right-click menu, not
the main menu. The feature map's internal call site is
`DragLint.Plugin.StructureForm.pas:1179`; the feature map does not name a
specific menu-item label for it beyond that.

## What it needs

An index IS required. The project's DB lives at
`<project folder>\_D-RAG\<project file>.sqlite`; run
`drag-lint resolve-dbs --project <X.dproj>` if unsure.

## Example

Illustrative:

```
drag-lint helpers-of TColorKind --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would list every record/class helper in the index that targets
`TColorKind`.
