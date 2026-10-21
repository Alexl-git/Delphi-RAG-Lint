---
id: backup
title: Backup before overwrite
summary: Create a backup of every file before overwriting it.
group: file-cli-no-preview-effect
order: 10
default: "false"
ini: Backup
since: "1.0.0.0"
status: "stable"
---

# Backup before overwrite

Backups are OPT-IN. With Backup=false (default), in-place formatting
overwrites the source with no copy of the original. Set Backup=true
(or pass --b on the command line) to write a backup before the
in-place edit. Irrelevant when ResultDir is set.

## Related

- [Backup directory](backup-dir.md) - Directory for backups (used when Backup=true). Empty = next to original file.
- [Result directory](result-dir.md) - Directory for formatted output. Empty = format in place.
- [Output encoding](encoding.md) - ANSI keeps each file's own encoding (BOM or detected UTF-8 preserved); UTF-8/UTF-16 convert the output (with BOM).
