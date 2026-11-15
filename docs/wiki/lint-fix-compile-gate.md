# Lint --fix through the compile gate

Since 1.51 `lint --in <f> --fix --apply` writes through the compile gate BY DEFAULT whenever `--project` names an
existing `.dproj` (1.47-1.50: opt-in with `--compile-gate`). It is the gate `unwith`, `rename` and `redundant-cast` use:

1. **Build 1** (before the write) keeps ALL its messages: errors, warnings and hints. Any error stops the run:
   `REFUSED (dirty-baseline)`, every error line of build 1 on stderr, nothing written.
2. The fix is written all-or-nothing (with backups and a `recovery.txt`).
3. **Build 2** (after the write): any error rolls every file back, `REFUSED (compile-error)`, every error line on stderr.
4. On success the warnings and hints of build 2 that build 1 did not have are reported as **new**. They are matched
   by file, code and message text, never by line number, because the fix moves lines.

```
drag-lint lint --in <f.pas> --db <db> --fix --apply --project <X.dproj> [--compile-gate | --no-compile-gate] [--platform <p>] [--rsvars <bat>] [--build-timeout <s>]
```

stderr, for a fix that removes `LCount:= LCount;`:

```
compile gate: build 1 (before the write): 0 error(s), 1 warning(s), 2 hint(s)
compile gate: build 2 (after the write): 0 error(s), 0 warning(s), 2 hint(s)
compile gate: 1 new warning(s)/hint(s) after the write:
compile gate: new: GtUnit.pas(18): H2164 Variable 'LCount' is declared but never used in 'Probe'
compile gate: 2 warning(s)/hint(s) of build 1 are gone
```

`--no-compile-gate` writes without building; `--compile-gate` together with it is exit 2. Other verbs that write through
the gate (`create-enum-helper`, `extract-method`) print the same `compile gate:` lines.

Exit: 0 applied and built, or nothing to fix. 1 the gate refused (a baseline that does not build, or a fix that breaks the
build): `REFUSED (compile-error)` and every dcc error line on stderr, every file byte-identical. 2 bad flags:
`--compile-gate` needs `--fix` and an existing `--project <X.dproj>`; `--compile-gate` with `--no-compile-gate`.

Without `--project` (or with one that is not an existing `.dproj`) nothing builds, as before.

A **naming rename** (the casing and prefix fixes, which rewrite a declaration and every use) is gated even with
`--no-compile-gate`; stderr says `naming renames are written through the compile gate of <X.dproj> even with
--no-compile-gate`. Guard: `tests\autotest\run_naming_fix_gate.ps1`.
Guard for the default, the messages and the diff: `tests\autotest\run_v151_GATE_compile_gate.ps1`.

## Example

A rule fixes `Take(AWalk as TObject)` to `Take(AWalk)`. When `AWalk` is an interface that removes the only way to its
instance and the unit no longer compiles (E2010). With `--no-compile-gate` `--apply` writes it. With the gate (the
default with a `.dproj`) the run exits 1, names the error and leaves the file as it was. Guard: `tests\autotest\run_lintfix_compilegate.ps1`.
