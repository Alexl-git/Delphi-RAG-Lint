---
id: fix-all-reliability
title: Fix all reliability (1.31.3)
summary: Fix all no longer drops every rename for library-root members, shows a wait cursor and refuses a second fix, and keeps E-prefixed exception classes
product: DL
group: linting
order: 30008
since: 1.31.3-alpha
status: shipped
updated: 1.31.3-alpha
---

# Fix all reliability (1.31.3)

Fix all no longer drops every rename for library-root members, shows a wait cursor and refuses a second fix, and keeps E-prefixed exception classes.

Autofix fixes: owner freshness ignores library-root members, IDE busy guard, exception ancestor prefix

## How to run it

```text
drag-lint lint <path> [--rule <id>] [--disable id1,id2] [--rules-dir <dir>] [--json] [--no-preprocess] [--library-db <lib.sqlite>]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |
| `--disable` |  |  |  |
| `--rules-dir` | `<dir>` |  |  |
| `--json` |  |  |  |
| `--no-preprocess` |  |  |  |
| `--library-db` | `<lib.sqlite>` |  |  |
| `--db` | `<index.sqlite>` |  |  |
| `--project-rules` |  |  |  |
| `--stand-in-for` | `<realpath>` |  |  |

## Where to click

* Right-click in the Structure form: **Fix all in unit**

## Details

Three fixes to the autofix path (CLI `lint --fix` / `--apply` and the IDE "Fix all in unit").

* **Library-root members no longer make an owner stale.** A `.dproj` member that lives under a
  registry library root (for example `ArrayHelper.pas`) is not owned by the project and is ignored
  by the multi-project rename freshness check. Before, the owner was permanently stale and every
  rename was dropped. The CLI now prints `autofix: nothing written -- N rename(s) dropped: <reason>`.
* **IDE wait cursor and single fix at a time.** While a fix job runs the Structure form shows the
  wait cursor; a second Fix all is refused instead of queued.
* **Exception classes keep their `E` prefix.** `EKeyViolation = class(EDatabaseError)` is no longer
  reported by `type-name-prefix` and is not renamed to `TEKeyViolation`.

See also [Fix-all-in-unit](fix-all-in-unit.md) and [Fix-all-in-project](fix-all-in-project.md).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
