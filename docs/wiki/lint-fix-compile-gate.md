# Lint --fix through the compile gate

`lint --in <f> --fix --apply` normally writes its fixes and trusts them. With `--compile-gate` (opt-in) the write goes
through the same gate `unwith`, `rename` and `redundant-cast` use: the project builds first, the fix is written
all-or-nothing (with backups and a `recovery.txt`), the project builds again, and a compile error rolls every file back.

```
drag-lint lint --in <f.pas> --db <db> --fix --apply --project <X.dproj> --compile-gate [--platform <p>] [--rsvars <bat>] [--build-timeout <s>]
```

Exit: 0 applied and built, or nothing to fix. 1 the gate refused (a baseline that does not build, or a fix that breaks the
build): `REFUSED (compile-error)` and the first dcc line on stderr, every file byte-identical. 2 bad flags: `--compile-gate`
needs `--fix` and an existing `--project <X.dproj>`.

Without `--compile-gate` nothing changes: no build, and `--project` stays what it was, a filter on which units are fixed.
The flag is separate from `--project` for that reason.

## Example

A rule fixes `Take(AWalk as TObject)` to `Take(AWalk)`. When `AWalk` is an interface that removes the only way to its
instance and the unit no longer compiles (E2010). Plain `--apply` writes it. With `--compile-gate` the run exits 1, names
the error and leaves the file as it was. Guard: `tests\autotest\run_lintfix_compilegate.ps1`.
