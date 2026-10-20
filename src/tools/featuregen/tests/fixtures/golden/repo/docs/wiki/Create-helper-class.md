# Create helper class

Generates a Byte-family record helper for an enum type represented by a
Structure-tree node. Reach for it when you have an enum and want the usual
ToByte/FromByte/ToInteger/FromInteger/ToString/FromString helper methods
without writing them by hand.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click an enum type's node in the tree and choose "Create helper
class".

## Running it from the CLI

The feature map lists the underlying verb as `create-enum-helper`. From the
usage banner:

```
drag-lint create-enum-helper --qname <TEnum> [--apply|--json|--no-backup] [--methods <csv>] [--tostring rtti|case] [--db PATH]
```

`--methods` defaults to all six (tobyte,frombyte,tointeger,frominteger,
tostring,fromstring). `--tostring` defaults to `rtti` (GetEnumName) or can
be `case` (explicit case statement). Idempotent: if a helper for the enum
already exists anywhere in the index, the action reports `exists` and makes
no edit.

## What it needs

Optional, per the feature map's Index column.

## Example

Illustrative:

```
drag-lint create-enum-helper --qname Unit1.TColorKind --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would generate a record helper with all six default methods for
`TColorKind`.
