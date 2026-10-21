---
id: encoding
title: Output encoding
summary: ANSI keeps each file's own encoding; UTF-8/UTF-16 convert the output (with BOM).
group: file-cli-no-preview-effect
order: 40
default: "ANSI"
ini: Encoding
cli: --encoding
since: "1.0.0.0"
status: "stable"
---

# Output encoding

Controls the byte-level encoding YADF uses when reading and
writing source files.
  ANSI         (default)  -- KEEP each file's own encoding: a file
                             with a BOM keeps it, a BOM-less file
                             detected as UTF-8 stays UTF-8, anything
                             else stays ANSI. Nothing is converted.
  UTF-8-BOM               -- convert to UTF-8 with the BOM (EF BB BF)
  UTF-16-BOM              -- convert to UTF-16 LE with the BOM (FF FE)

The input's encoding (BOM, or BOM-less UTF-8) is always detected on
load. Only UTF-8-BOM / UTF-16-BOM change the bytes written; the
default ANSI means "preserve", not "write plain ANSI".

Accepted aliases (case-insensitive):
  ANSI
  UTF-8 | UTF8 | UTF-8-BOM | UTF8BOM
  UTF-16 | UTF16 | UTF-16-BOM | UTF16BOM | UTF-16-LE

## Related

- [Backup before overwrite](backup.md) - Create a backup of every file before overwriting it.
- [Backup directory](backup-dir.md) - Directory for backups (used when Backup=true). Empty = next to original file.
- [Result directory](result-dir.md) - Directory for formatted output. Empty = format in place.
