---
id: v152-extract-constant
title: Extract constant (manual fix for magic literals)
summary: Turns one number or string literal into a named constant and replaces every occurrence in the unit; manual fix of the magic-literal rules
product: DL
group: refactoring
order: 50022
since: 1.52.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Extract constant (manual fix for magic literals)

Turns one number or string literal into a named constant and replaces every occurrence in the unit; manual fix of the magic-literal rules.

Read this when a literal should become a named constant. Give the line (and the column when the line holds several literals) and the name; without --name the plan proposes one. Occurrences inside other const declarations, attributes, uses clauses, or in a context of a different declared type are left and listed on stderr. The fix is risky and manual only: a batch --fix never applies it.

## How to run it

```text
drag-lint lint --in <F> [--db <db>] --enable <rule> --fix --fix-rule <rule> --fix-line <n> [--col <c>] [--name <ident>] [--apply] [--project <X.dproj>] - extract the literal at line n (column c) into a named constant and replace every occurrence in the unit; <rule> = extract-constant (any number or string literal, OFF by default, reports only when its fix is asked for), magic-literal, large-magic-number or case-magic-numbers; risky, manual only (a batch --fix withholds it); report on stderr
```

Example:

```text
drag-lint lint --in <F> --db <db> --enable extract-constant --fix --fix-rule extract-constant --fix-line <n> --col <c> --name <ident> --apply
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--fix-rule` | `<rule>` |  |  |
| `--fix-line` | `<n>` |  |  |
| `--col` | `<c>` |  |  |
| `--name` | `<ident>` |  |  |
| `--apply` |  |  |  |
| `--project` | `<X.dproj>` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Extract Constant (literal at cursor)...**
   1. Put the caret on a number or string literal in the editor
   2. drag-lint > Extract Constant (literal at cursor)...
   3. Edit the proposed name in the prompt and press OK; the engine report (replaced and left occurrences) is shown
* Right-click in the Editor: **drag-lint > Extract Constant (literal at cursor)...**
   1. Put the caret on a number or string literal
   2. Right-click in the editor, open the drag-lint submenu and choose Extract Constant (literal at cursor)...
   3. Edit the proposed name in the prompt and press OK

## Details

drag-lint turns one literal into a named constant and replaces every occurrence of that literal in the unit, like MMX's Extract Constant. It is the fix of `magic-literal`, `large-magic-number` and `case-magic-numbers`, and of the on-demand rule `extract-constant`, which reaches any number or string literal (no other rule flags strings).

### From the command line

```text
drag-lint lint --in <F.pas> --db <db> --enable extract-constant --fix --fix-rule extract-constant --fix-line <n> --col <c> --name <ident> [--apply] [--project <X.dproj>]
drag-lint lint --in <F.pas> --db <db> --enable magic-literal --fix --fix-rule magic-literal --fix-line <n> [--name <ident>] [--apply]
```

* `--fix-line` picks the line, `--col` the literal when the line holds several (1-based, any column inside the literal).
* `--name` is the constant's name. Without it the plan proposes one and shows it: `c` + the assigned or compared identifier + the value for numbers (`cCount5000`), `s` + the first three words for strings (`sHelloBigWorld`). A name already used in the unit is refused, and nothing is written.
* Without `--apply` nothing is written; the preview shows the inserted `const` block and every replaced position.
* With `--project <X.dproj>` the write goes through the compile gate: the project is built before and after, and a result that does not compile is rolled back.

The report goes to stderr:

```text
extract-constant: name cMaxCount = 5000 (given), placed in the implementation section; 2 occurrence(s) replaced, 3 left (positions as before the edit)
extract-constant:   left GfUnit.pas:14:12 -- inside a const declaration
extract-constant:   left GfUnit.pas:31:11 -- a different type context: Double (the extracted literal is Integer)
```

### What is replaced and what is left

* The constant goes into a new `const` block right after the uses clause of the `implementation` section when every replaced occurrence is there, else of the `interface` section.
* Every occurrence of the same literal token is replaced (numbers compare case-insensitively, strings exactly), except: inside another `const` / `resourcestring` declaration, an attribute, a uses clause, a label, a composite string such as `'a'#13`, and a context of a different declared type. The type context is the declared type of the identifier the literal is assigned to, compared with, or the `case` selector: `Ratio:= 5000` with `Ratio: Double` is left when the extracted `5000` was assigned to an `Integer`. An unknown type never counts as different.
* The fix is risky (the same value can mean two things) and manual only: a batch `lint --fix` without `--fix-rule` never applies it and says so. `rules --json` shows `fix_manual_only: true` for the four rule ids.

### RAD Studio

Put the caret on a number or string literal, then choose Extract Constant (literal at cursor)... from the drag-lint main menu or from the drag-lint submenu of the editor's right-click menu. All modules are saved, the engine computes the plan, and a prompt pre-filled with the proposed name opens. OK applies the extraction with that name and shows the engine's report; Cancel writes nothing.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
