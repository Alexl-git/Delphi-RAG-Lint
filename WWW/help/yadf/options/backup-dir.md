---
id: backup-dir
title: Backup directory
summary: Directory for backups (used when backup is on). Empty = next to the original file.
group: file-cli-no-preview-effect
order: 20
default: ""
ini: BackupDir
since: "1.0.0.0"
status: "stable"
---

# Backup directory

Used only when Backup=true and ResultDir is empty.
  - Non-empty: write a timestamped <name>.<YYYYMMDD-hhmmss>.bak
    under this folder before overwriting the source.
  - Empty (default): write <source>.BCK<N> next to the source,
    where N is the lowest unused integer (1, 2, 3, ...).
CLI equivalent: --b <folder> (with arg) or --b (no arg, sibling).

## Related

- [Backup before overwrite](backup.md) - Create a backup of every file before overwriting it.
- [Result directory](result-dir.md) - Directory for formatted output. Empty = format in place.
- [Output encoding](encoding.md) - ANSI keeps each file's own encoding (BOM or detected UTF-8 preserved); UTF-8/UTF-16 convert the output (with BOM).
