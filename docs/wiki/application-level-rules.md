# Application-level lint rules

Rules about what a whole program or unit does at run time rather than how one
statement is written. All are text-based, run per unit in `lint` and `lint-all`,
and need no index (`writeln-in-gui-app` uses one to find the program).

| Rule | Default | Severity | Fires on |
|---|---|---|---|
| `tls-verification-disabled` | ON | warning | certificate validation switched off in code (see the fixture for the recognised shapes) |
| `ui-call-in-console-or-service` | ON | warning | `ShowMessage`, `MessageDlg`, `Application.MessageBox` and similar in a console program, a service or a unit they own: nobody sees the dialog and the process hangs |
| `weak-cipher` | ON | warning | DES, 3DES, RC2, RC4 or ECB mode |
| `dunitx-test-without-assert` | ON | info | a DUnitX test method that checks nothing |
| `asm-without-win64-variant` | ON | warning | an `asm` block with no `{$IFDEF CPUX64}` variant and no Pascal fallback |
| `writeln-in-gui-app` | ON | warning | `Write` / `WriteLn` to the console in a VCL / FMX unit of a program with no console |
| `contract-unit-declares-class` | OFF | info | a unit named Intf, Interfaces or Contracts that declares a class: policy, enable with `--rule` |

`writeln-in-gui-app` skips a write whose first argument is a text-file or stream
variable, including one declared in another unit and named `*File`, `*Log`,
`*Txt`, `*Writer` or `*Stream`; it also skips code under `{$IFDEF CONSOLE}` /
`DEBUG` and routines that test `IsConsole`.

The rule also asks the program the file belongs to (1.54.1): the project whose index
the run uses, or `--project <x.dproj>`. No finding when that program is a console
program:

- `{$APPTYPE CONSOLE}` in its `.dpr`, not in a comment or a string. The last
  `{$APPTYPE}` wins, as in the compiler. A conditional `CONSOLE` counts, a conditional
  `GUI` does not.
- no `{$APPTYPE}`: `DCC_ConsoleTarget` = true in the `.dproj` for the indexed platform and
  config. `AppType` = Console alone is IDE metadata, the compiler never sees it.
- `AllocConsole` or `AttachConsole` in the `.dpr`.

The `.dpr` / `.dproj` are read when linting, once per run, only when there is a write to
report. A loose file, a folder index, a package and a library have no known program: the
file's own text decides. `{$APPTYPE}` inside an include file of the `.dpr`, and a console
allocated in another unit, are not seen.

`ui-call-in-console-or-service` decides "console program" the same way (1.54.1): the
`{$APPTYPE}` directives of the `.dpr` (not a comment or a string, the last one wins, a
conditional `CONSOLE` counts), `AllocConsole` / `AttachConsole`, and `DCC_ConsoleTarget`
of the run's `.dproj`. Per file it reports a dialog call in the program source itself
and in a method of a Windows service class. In `lint-all` a second pass follows the
program into the units it uses (transitively): each call in the program of a
stand-alone routine that shows a dialog is reported at the call.

Known limit: that pass follows stand-alone routines only (a method call needs a
receiver type the text cannot give), matched by simple name; a dialog reached only
through a method of a used unit is not reported. A dialog call in a unit that no
program of the run uses is not reported either.
