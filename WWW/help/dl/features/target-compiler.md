---
id: target-compiler
title: Target compiler (--target-compiler)
summary: Names the oldest compiler the code must compile on; modernize findings whose advice needs a newer compiler are not reported
product: DL
group: linting
order: 30025
since: 1.38.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Target compiler (--target-compiler)

Names the oldest compiler the code must compile on; modernize findings whose advice needs a newer compiler are not reported.

Read this when your code must still build on an older Delphi (12, 10.4, XE7 ...): pass --target-compiler or set target_compiler in drag-lint-lint.json, and lint stops suggesting syntax that compiler cannot take.

## How to run it

Full flag list: [lint in the CLI reference](../cli.md#lint).

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

Full flag list: [rules in the CLI reference](../cli.md#rules).

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Run Lint All (Full Report)...**

## Details

`--target-compiler <ver|auto>` tells `lint`, `lint-all` and `rules` the oldest Delphi compiler the code must still compile on. Modernize advice that needs a newer compiler is then not reported, so a project that has to build on Delphi 12 (or 10.4, or XE7) no longer hears "write `X is not T`" or "use an `if` expression". The default is 37 (Delphi 13): without the switch nothing changes.

### Running it from the CLI
```text
drag-lint lint <file.pas> --target-compiler 12           (Delphi 12 = CompilerVersion 36)
drag-lint lint-all --db <db> --target-compiler 10.4
drag-lint lint-all --db <db> --project <x.dproj> --target-compiler auto   (from the .dproj ProjectVersion)
drag-lint rules --json --target-compiler 36              (target_active per rule at that target)
```
Accepted tokens: product versions `13`, `12`, `12.2`, `11`, `10.4`, `10.3`, `10.2`, `10.1`, `10`, `XE8` .. `XE2`, `XE`, `2010`, `2009`, `2007`, `2005`, `7`, `6` (an optional `Delphi` prefix and the code names `Florence`, `Athens`, `Alexandria`, `Sydney`, `Rio`, `Tokyo`, `Berlin`, `Seattle` work too), or a CompilerVersion `14` .. `37`. An unknown token exits 2 and lists the accepted set; drag-lint never guesses.

`auto` reads the `<ProjectVersion>` of the `.dproj` named by `--project` (20.4 -> 37, 20.1-20.3 -> 36, 19.3-19.5 -> 35, 19.0-19.2 -> 34, 18.5-18.8 -> 33, 18.2-18.4 -> 32, 18.1 -> 31). A value outside that table exits 2. ProjectVersion says which IDE last saved the project, not which compilers must accept it -- name the version when they differ.

### The config key
```json
{ "target_compiler": "13", "profiles": { "legacy": { "target_compiler": "12" } } }
```
`"target_compiler"` in `drag-lint-lint.json` takes the same tokens. A profile overrides it (`--profile legacy`), and `--target-compiler` on the command line wins over both. Fix it / Fix all in the IDE run the engine with the project's config, so a project that sets the key is linted and fixed for its target from the IDE too.

Order of precedence: command line, then the config (after `--profile`), then the project context file's `targetCompiler`, then 37.

### What is gated
| rule | what its advice needs | gated below |
|---|---|---|
| `is-not-operator` | `X is not T` | 37 (Delphi 13) |
| `ifthen-to-if-expression` | `X := if C then A else B` | 37 |
| `nonminimal-bool`, the `not (A in S)` form only | `A not in S` | 37 |
| `unreadable-literal` | digit separators `1_000` | 35 (Delphi 11) |
| `pos-for-contains`, the `Contains` forms | `TStringHelper.Contains` | 24 (XE3) |
| `manual-inrange` | `System.Math.InRange` | 14 (Delphi 6) |

The inline-`var` fixes of `swap-without-temp`, `field-by-name-in-loop` and `index-loop-to-for-in` need 33 (10.3): below that the finding is still reported, the edit is skipped, and stderr says `N fix(es) skipped (target-compiler)`.

A non-default target prints one line on stderr: `target-compiler: 36 (Delphi 12) -- N modernize rule(s) gated, M compat rule(s) on`.

### In `rules --json`
Every row carries `needs_compiler` (0 = any compiler), `compat_since` (0 = not a compat rule) and `target_active` (does the rule run by default at this target; equal to `default_enabled` at 37). The root carries `target_compiler`.

### Writing a gated rule
A sidecar `.json` gates its rule with `"needs_compiler": N`; the same key on one `fix` entry gates only the matches that entry would fix. A rule of category `compat` carries `"compat_since": N`, ships `"enabled": false`, and is switched on for a run whose target is older than N. See rules/README.md. The downgrade rules themselves are a separate entry: Downgrade fixes.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
