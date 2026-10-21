---
id: scan-todos-fixmes
title: Scan TODOs / FIXMEs
summary: Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers
product: DL
group: graphs-reports
order: 70016
since: 0.12.0-alpha
status: shipped
updated: 1.33.0-alpha
---

# Scan TODOs / FIXMEs

Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers.

Read this when you want to see the outstanding work left in code: it lists TODO, FIXME, HACK, XXX, REVIEW and NOTE markers in a path, as text or JSON.

## How to run it

Full flag list: [todos in the CLI reference](../cli.md#todos).

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Scan TODOs / FIXMEs...**

## Details

Scans source for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers. Reach for it to
triage outstanding work markers left in code.

### Running it from the CLI
```text
drag-lint todos [<path>] [--json]
```
`<path>` is optional per the usage banner; `--json` emits JSON instead of
text. No further defaults for an omitted `<path>` are documented.

### Reaching it in the IDE
drag-lint > Code Quality > Scan TODOs / FIXMEs...

### What it needs
No index required -- this command has no `--db` flag; it scans source files
directly for TODO/FIXME/HACK/XXX/REVIEW/NOTE markers.

### Example
Illustrative only:
```text
drag-lint todos C:\Projects\MyApp\src --json
```
This would list TODO/FIXME/HACK/XXX/REVIEW/NOTE markers found under
`C:\Projects\MyApp\src`, as JSON.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
