---
id: format-with-yadf
title: Format with YADF
summary: Reformats one Pascal unit by driving the external YADF formatter
product: DL
group: linting
order: 30013
since: 0.16.0-alpha
status: shipped
updated: 1.38.0-alpha
---

# Format with YADF

Reformats one Pascal unit by driving the external YADF formatter.

Read this when you want one unit reformatted by the YADF formatter. Careful: drag-lint format rewrites the file in place; try --diff (formats a copy and prints the diff) or --dry-run first, and commit before running it for real.

## How to run it

Full flag list: [format in the CLI reference](../cli.md#format).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--yadf-path` | `PATH` |  |  |
| `--dry-run` |  |  |  |
| `--diff` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Format with YADF**
   1. Open the unit in the editor
   2. drag-lint > Format with YADF
   3. The unit is rewritten in place by YADF

## Details

Reformats one Pascal unit by driving the external **YADF** formatter.

> **This verb rewrites the file in place.** It is the only drag-lint verb that
> can destroy your work, so read the safety section before using it on anything
> you have not committed.

### Running it from the CLI

```text
drag-lint format <file> [--yadf-path PATH] [--dry-run] [--diff]
```

| flag | what it does |
|---|---|
| *(none)* | formats the file **in place**, after backing it up and verifying the result |
| `--dry-run` | resolves YADF, checks its version, prints which binary it **would** run -- and writes nothing |
| `--diff` | formats a **copy** in a scratch directory and prints a diff; the original is never opened for writing |
| `--yadf-path PATH` | use this formatter instead of the configured one |

Prefer `--diff` before a first run on unfamiliar code.

### How YADF is found

1. `--yadf-path <path>`, if given;
2. otherwise `HKCU\Software\YADF\ExePath`.

**There is no hardcoded fallback path.** Two used to exist and both pointed at
`Win32` locations that no build has ever occupied, so they could never resolve
while making the failure look like something else. A miss is now loud.

### The two safety gates

**Minimum version.** A YADF older than **1.0.6.6** is refused outright (exit
`4`, nothing written), naming the version found, the version required and the
path. That release fixed the inline-`var` split; older builds can rewrite a unit
into something that no longer means the same thing.

The version is read from the executable's **version resource**, not by running
it -- YADF exposes no `--version` flag. A formatter with no version resource (a
wrapper script) is *not* refused; it runs with a warning, because the second
gate protects the file regardless.

**Post-format verification.** After a real write, the file is re-parsed and its
set of **declared symbols** compared against the pre-format parse. A formatter
may rewrite every byte of layout; it may not change what the unit declares. On
divergence the original is **restored from backup** and the run exits `5`.

If the file did not parse *before* formatting, the check is skipped -- there is
no baseline to compare against. A file that parsed before and does not parse
after is treated as corruption.

### Exit codes

`0` done, or YADF declined (it printed `Declined: <file>` -- its content guard
left the file unchanged; not a failure) ; `2` usage, or the target does not exist ; `3` no usable YADF
resolved ; `4` YADF below the minimum version, nothing written ; `5` formatting
changed the declared symbols, file restored ; `1` any other formatter failure.

### What it needs

No index. It needs YADF installed and resolvable.

### Example

```text
drag-lint format C:\Projects\MyApp\frmOrders.pas --diff
```

Prints what formatting would change, and writes nothing.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
