---
id: result-dir
title: Result directory
summary: Directory for formatted output. Empty = format in place.
group: file-cli-no-preview-effect
order: 30
default: ""
ini: ResultDir
since: "1.0.0.0"
status: "stable"
---

# Result directory

When non-empty, every formatted file is written to
  <ResultDir>\<basename-of-source>
and the source file is left untouched. Leave empty (the default)
for in-place formatting.
CLI equivalents: --of <folder> sets, --no-o clears.

## Related

- [Backup before overwrite](backup.md) - Create a backup of every file before overwriting it.
- [Backup directory](backup-dir.md) - Directory for backups (used when Backup=true). Empty = next to original file.
- [Output encoding](encoding.md) - ANSI keeps each file's own encoding (BOM or detected UTF-8 preserved); UTF-8/UTF-16 convert the output (with BOM).
