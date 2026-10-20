---
id: quick-fix-add-unit-for-inline-hint-h2443-at-cursor
title: "Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor"
summary: The same idea as the undeclared-identifier quick-fix, but for compiler hint H2443 -- an inline routine whose declaring unit is not in scope
product: DL
group: refactoring
order: 50006
since: 0.0.0
status: shipped
updated: 1.32.0-alpha
---

# Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor

The same idea as the undeclared-identifier quick-fix, but for compiler hint H2443 -- an inline routine whose declaring unit is not in scope.

## Where to click

* RAD Studio main menu: **drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor**

## Details

The same idea as the undeclared-identifier quick-fix, but for compiler hint
H2443 -- an inline routine whose declaring unit is not in scope. Reach for it
when the compiler flags an inline expansion that needs another unit.

### Running it from the CLI
No CLI equivalent - this action is in-process only.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Quick-Fix: Add Unit for Inline Hint (H2443) at Cursor

### What it needs
n/a. This action runs in-process against the open editor buffer; the feature
map does not mark it as needing a separate index step.

### Example
Illustrative only: with an H2443 hint reported at the caret -- say, on a call
that resolves to an inline method of `TCustomerOrder` -- invoke the quick-fix
to add the unit that declares it to `uses`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
