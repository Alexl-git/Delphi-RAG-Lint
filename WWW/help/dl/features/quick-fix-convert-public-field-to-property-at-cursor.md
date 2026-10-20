---
id: quick-fix-convert-public-field-to-property-at-cursor
title: "Quick-Fix: Convert Public Field to Property at Cursor"
summary: Rewrites a public field under the caret as a property
product: DL
group: refactoring
order: 50008
since: 0.0.0
status: shipped
updated: 1.32.0-alpha
---

# Quick-Fix: Convert Public Field to Property at Cursor

Rewrites a public field under the caret as a property.

## Where to click

* RAD Studio main menu: **drag-lint > Convert Public Field to Property at Cursor**

## Details

Rewrites a public field under the caret as a property. Reach for it when
tightening up a class's public surface.

### Running it from the CLI
No CLI equivalent - this action is in-process only.

### Reaching it in the IDE
drag-lint > Uses & Dependencies > Quick-Fix: Convert Public Field to Property at Cursor

### What it needs
n/a. This action runs in-process against the open editor buffer; the feature
map does not mark it as needing a separate index step.

### Example
Illustrative only: place the caret on a public field -- for example
`FCustomer: TCustomerOrder;` exposed directly on `TfrmMain` -- and invoke the
quick-fix to convert it into a property.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
