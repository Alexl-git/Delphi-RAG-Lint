---
id: unit-test-stub-symbol
title: Unit Test Stub (symbol)
summary: Uses generate-test to produce a unit-test skeleton for one qualified symbol
product: DL
group: refactoring
order: 50012
since: 0.27.0-alpha
status: shipped
updated: 1.35.1-alpha
---

# Unit Test Stub (symbol)

Uses generate-test to produce a unit-test skeleton for one qualified symbol.

Read this when a routine has no test yet: generate-test produces a unit-test skeleton for one qualified symbol, in DUnitX or DUnit style.

## How to run it

Full flag list: [generate-test in the CLI reference](../cli.md#generate-test).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--qname` | `<Foo.TBar.Baz>` |  |  |
| `--framework` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Generate & Export > Unit Test Stub (symbol)...**
   1. Put the caret on the routine in the editor
   2. Choose drag-lint > Generate & Export > Unit Test Stub (symbol)...
   3. A unit-test skeleton for the symbol is generated
   4. From a shell: `drag-lint generate-test --qname <Foo.TBar.Baz> [--framework dunitx|dunit] [--db PATH]`

## Details

Uses `generate-test` to produce a unit-test skeleton for one qualified
symbol. Reach for it to scaffold a test file for a routine that has none.

### Running it from the CLI
```text
drag-lint generate-test --qname <Foo.TBar.Baz> [--framework dunitx|dunit] [--db PATH]
```
`--qname` is the fully qualified symbol; `--framework` selects `dunitx` or
`dunit`.

### What it needs
The `--db` flag is optional -- drag-lint auto-resolves the project's index
when omitted. An index must still exist.

### Example
Illustrative only:
```text
drag-lint generate-test --qname MyApp.TCustomerOrder.Total --framework dunitx --db C:\Projects\MyApp\_D-RAG\MyApp.sqlite
```
This would produce a DUnitX test stub targeting the `Total` member of
`TCustomerOrder`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
