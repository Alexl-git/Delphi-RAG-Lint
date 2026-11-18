---
id: v151-wid-scm-rules
title: Wider scm rules and three new fixers
summary: Seven built-in rules read more constructs; empty-finally, format-string-not-formatted and shared-marker-legacy-shape gain autofixes
product: DL
group: linting
order: 30064
since: 1.51.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Wider scm rules and three new fixers

Seven built-in rules read more constructs; empty-finally, format-string-not-formatted and shared-marker-legacy-shape gain autofixes.

Read this when you want to know which constructs the 1.51 lint rules newly report or exempt, and which new fixes lint --fix offers.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>] [--no-budget]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Six built-in rules read more of the source in 1.51, and three rules gained an autofix.

### Wider rules
* `large-magic-number` no longer fires on a string code page (`AnsiString(1252)`), a numeric label or `goto` target, or an array bound (`array[1..28] of Byte`).
* `deprecated-rtl-function` also reports `GetWindowLong`, `SetWindowLong`, `GetClassLong`, `SetClassLong` (32-bit only; use the `*Ptr` variant) and `Resume` / `Suspend` on a thread-named receiver.
* `locale-sensitive-conversion` also reports `Format('%f', [X])` (and `%e %g %n %m` with a non-zero precision) without a `TFormatSettings`.
* `hardcoded-credential` also reports a property assignment such as `Params.Password := 'x'`.
* `sql-update-delete-without-where` also reports an UPDATE / DELETE built from concatenated literals only.
* `classname-string-compare` also reports `ClassNameIs('TFoo')`, a bare `ClassName` and a literal on the left.
* `division-by-zero-literal` also reports `$0` and `00`.

### 1.51.1
* `division-by-zero-literal` is float-only: `X / 0` and `X / 0.0` are reported; `div 0` / `mod 0` are dcc E2098 compile errors and are not.
* `large-magic-number` also exempts case labels, enum ordinals in a type declaration, `dispid N`, array subscripts (`Params[3]`, `Fields[2]`) and the first argument of `Reg(<int>, 'NAME')`.
* `inherited-bare` is not reported in Destroy / Assign / AssignTo or as the `if not (X is T) then inherited else` fallback.

### New fixers
```text
drag-lint lint --in <file.pas> --fix --fix-rule empty-finally --apply
drag-lint lint --in <file.pas> --fix --fix-rule format-string-not-formatted --apply
drag-lint lint --in <file.pas> --fix --fix-rule shared-marker-legacy-shape --apply   (risky, opt-in)
```
`empty-finally` unwraps an aligned `try ... finally end;`. `format-string-not-formatted` turns `Format('text', [])` into `'text'`. `shared-marker-legacy-shape` rewrites `// note // dl:shared A` to `// dl:shared A // note`; it cannot tell that from prose, so it is opt-in.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
