---
id: lint-fix-compile-gate
title: Lint --fix through the compile gate
summary: lint --fix --apply --project X.dproj --compile-gate writes the fixes only if the project still builds; a fix that breaks the compile is refused and rolled back
product: DL
group: refactoring
order: 50008
since: 1.50.0-alpha
status: shipped
updated: 1.50.0-alpha
---

# Lint --fix through the compile gate

lint --fix --apply --project X.dproj --compile-gate writes the fixes only if the project still builds; a fix that breaks the compile is refused and rolled back.

Read this before letting lint --fix write into a project you cannot afford to break. With --compile-gate the project builds before and after the write and any compile error rolls every file back. Opt-in: without the flag nothing builds, except a naming rename (field/param/local/const prefix or casing fixes), which is always written through the gate when --project names a .dproj.

## How to run it

```text
drag-lint lint --in <f.pas> --db <db> --fix --apply --project <X.dproj> --compile-gate [--fix-line <L> --fix-rule <id>] [--no-backup] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>]
```

Example:

```text
drag-lint lint --in <f.pas> --db <db> --fix --apply --project <X.dproj> --compile-gate
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--in` | `<f.pas>` |  |  |
| `--db` | `<db>` |  |  |
| `--fix` |  |  |  |
| `--apply` |  |  |  |
| `--project` | `<X.dproj>` |  |  |
| `--compile-gate` |  |  |  |
| `--fix-line` | `<L>` |  |  |
| `--fix-rule` | `<id>` |  |  |
| `--no-backup` |  |  |  |
| `--platform` | `<p>` |  |  |
| `--rsvars` | `<bat>` |  |  |
| `--build-timeout` | `<s>` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

`lint --in <f> --fix --apply` normally writes its fixes and trusts them. With `--compile-gate` (opt-in) the write goes
through the same gate `unwith`, `rename` and `redundant-cast` use: the project builds first, the fix is written
all-or-nothing (with backups and a `recovery.txt`), the project builds again, and a compile error rolls every file back.

```text
drag-lint lint --in <f.pas> --db <db> --fix --apply --project <X.dproj> --compile-gate [--platform <p>] [--rsvars <bat>] [--build-timeout <s>]
```

Exit: 0 applied and built, or nothing to fix. 1 the gate refused (a baseline that does not build, or a fix that breaks the
build): `REFUSED (compile-error)` and the first dcc line on stderr, every file byte-identical. 2 bad flags: `--compile-gate`
needs `--fix` and an existing `--project <X.dproj>`.

Without `--compile-gate` nothing changes: no build, and `--project` stays what it was, a filter on which units are fixed.
The flag is separate from `--project` for that reason.

One exception (1.47, wave 148): a **naming rename** (the casing and prefix fixes, which rewrite a declaration and every
use) is always written through the gate when `--project` names an existing `.dproj`, with or without `--compile-gate`;
stderr says `naming renames are written through the compile gate of <X.dproj>`. Every other edit of the same run goes
through the same all-or-nothing write. Without `--project` a naming rename writes as before, proved but not built.
Guard: `tests\autotest\run_naming_fix_gate.ps1`.

### Example

A rule fixes `Take(AWalk as TObject)` to `Take(AWalk)`. When `AWalk` is an interface that removes the only way to its
instance and the unit no longer compiles (E2010). Plain `--apply` writes it. With `--compile-gate` the run exits 1, names
the error and leaves the file as it was. Guard: `tests\autotest\run_lintfix_compilegate.ps1`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
