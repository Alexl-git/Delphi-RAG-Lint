---
id: logging
title: Logging
summary: Write a log file with details of every option resolved and file processed.
group: file-cli-no-preview-effect
order: 50
default: "false"
ini: Logging
since: "1.0.0.0"
status: "stable"
---

# Logging

When true, YADF appends to `%APPDATA%\YADF\yadf-startup.log`
(beside yadf.ini, never beside the exe), capturing the command-line received, the resolved INI path,
the active option values, and the per-file output decision
(in-place / result-dir / unchanged). Also emits the same lines
via OutputDebugString, which CodeSite Live Viewer (or
Sysinternals DebugView) can capture in real time.

Useful for diagnosing why YADF wrote where it wrote when called
from an IDE Tool or a build script. Off by default.
CLI: `--log` to enable, `--no-log` to disable.

## Related

- [Backup before overwrite](backup.md) - Create a backup of every file before overwriting it.
- [Backup directory](backup-dir.md) - Directory for backups (used when Backup=true). Empty = next to original file.
- [Result directory](result-dir.md) - Directory for formatted output. Empty = format in place.
