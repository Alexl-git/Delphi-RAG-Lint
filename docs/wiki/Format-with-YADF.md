# format (Format with YADF)

Reformats one Pascal unit by driving the external **YADF** formatter.

> **This verb rewrites the file in place.** It is the only drag-lint verb that
> can destroy your work, so read the safety section before using it on anything
> you have not committed.

## Running it from the CLI

```
drag-lint format <file> [--yadf-path PATH] [--dry-run] [--diff]
```

| flag | what it does |
|---|---|
| *(none)* | formats the file **in place**, after backing it up and verifying the result |
| `--dry-run` | resolves YADF, checks its version, prints which binary it **would** run -- and writes nothing |
| `--diff` | formats a **copy** in a scratch directory and prints a diff; the original is never opened for writing |
| `--yadf-path PATH` | use this formatter instead of the configured one |

Prefer `--diff` before a first run on unfamiliar code.

## How YADF is found

1. `--yadf-path <path>`, if given;
2. otherwise `HKCU\Software\YADF\ExePath`.

**There is no hardcoded fallback path.** Two used to exist and both pointed at
`Win32` locations that no build has ever occupied, so they could never resolve
while making the failure look like something else. A miss is now loud.

## The two safety gates

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

## Exit codes

`0` done · `2` usage, or the target does not exist · `3` no usable YADF
resolved · `4` YADF below the minimum version, nothing written · `5` formatting
changed the declared symbols, file restored · `1` any other formatter failure.

## Reaching it in the IDE

The plugin's **Format with YADF** menu item calls this verb for the active unit.
See also [Format Whole Project with YADF](Format-Whole-Project-with-YADF.md).

## What it needs

No index. It needs YADF installed and resolvable.

## Example

```
drag-lint format C:\Projects\MyApp\frmOrders.pas --diff
```

Prints what formatting would change, and writes nothing.
