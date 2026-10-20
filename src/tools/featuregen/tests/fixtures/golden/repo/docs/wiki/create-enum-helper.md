# create-enum-helper

Generates a Byte-family record helper (ToByte/FromByte/ToInteger/
FromInteger/ToString/FromString) for an enum type. Reach for it when you
have an enum and want the usual conversion helpers without writing them by
hand.

## Running it from the CLI

```
drag-lint create-enum-helper --qname <TEnum> [--apply|--json|--no-backup] [--methods <csv>] [--tostring rtti|case] [--db PATH]
```

`--methods` defaults to all six (tobyte,frombyte,tointeger,frominteger,
tostring,fromstring). `--tostring` defaults to `rtti` (RTTI `GetEnumName`)
or can be `case` (explicit case statement). Idempotent: if a helper for the
enum already exists anywhere in the index, the action reports `exists` and
makes no edit. The usage line lists `--apply` as a flag; whether omitting it
produces a dry run is not documented in the help text for this verb.

## Reaching it in the IDE

Reachable in the IDE only through the Structure form's right-click menu, not
the main menu -- see [Create helper class](Create-helper-class) for the
IDE-side walkthrough. The feature map's internal call site is
`DragLint.Plugin.StructureForm.pas:1226`.

## What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

## Example

Illustrative:

```
drag-lint create-enum-helper --qname Unit1.TColorKind --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would generate a record helper with all six default methods for
`TColorKind`.
