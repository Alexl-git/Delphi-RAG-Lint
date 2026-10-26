---
id: create-enum-helper
title: create-enum-helper
summary: Generates a Byte-family record helper (ToByte/FromByte/ToInteger/ FromInteger/ToString/FromString) for an enum type
product: DL
group: refactoring
order: 50003
since: 0.94.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# create-enum-helper

Generates a Byte-family record helper (ToByte/FromByte/ToInteger/ FromInteger/ToString/FromString) for an enum type.

Read this when you have an enum and want the usual conversion helpers without writing them by hand. create-enum-helper generates a Byte-family record helper with ToByte, FromByte, ToInteger, FromInteger, ToString and FromString; without --apply it is a dry run (exit 0, nothing written; --json reports action and applied=false). Exit 0 when a helper is built, 1 when refused (for example action=exists), 2 on usage or a missing --db. Note --json together with --apply still writes.

## How to run it

Full flag list: [create-enum-helper in the CLI reference](../cli.md#create-enum-helper).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<TEnum>` |  |  |
| `--apply` |  |  |  |
| `--json` |  |  |  |
| `--no-backup` |  |  |  |
| `--methods` | `<csv>` |  |  |
| `--tostring` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Enum Record Helper (symbol)...**
   1. Put the caret on the enum type in the editor (the name box is prefilled from the caret)
   2. Choose drag-lint > Generate & Export > Enum Record Helper (symbol)...
   3. Confirm the qualified name, then choose Yes to write the helper or No for a dry-run preview; the Structure form right-click Create helper class always writes

## Details

Generates a Byte-family record helper (ToByte/FromByte/ToInteger/
FromInteger/ToString/FromString) for an enum type. Reach for it when you
have an enum and want the usual conversion helpers without writing them by
hand.

### Running it from the CLI

```text
drag-lint create-enum-helper --qname <TEnum> [--apply|--json|--no-backup] [--methods <csv>] [--tostring rtti|case] [--db PATH]
```

`--methods` defaults to all six (tobyte,frombyte,tointeger,frominteger,
tostring,fromstring). `--tostring` defaults to `rtti` (RTTI `GetEnumName`)
or can be `case` (explicit case statement). Idempotent: if a helper for the
enum already exists anywhere in the index, the action reports `exists` and
makes no edit. The usage line lists `--apply` as a flag; whether omitting it
produces a dry run is not documented in the help text for this verb.

### What it needs

The `--db` flag is optional -- drag-lint auto-resolves the index when
omitted. An index must still exist.

### Example

Illustrative:

```text
drag-lint create-enum-helper --qname Unit1.TColorKind --apply --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```

This would generate a record helper with all six default methods for
`TColorKind`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
