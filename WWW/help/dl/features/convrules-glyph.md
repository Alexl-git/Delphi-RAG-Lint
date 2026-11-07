---
id: convrules-glyph
title: Glyph expressions (G[I/N])
summary: "ConvRulesEditor Mapping menu: set, change or clear the G[I/N] glyph expression on the selected link"
product: DL
group: component-conversion
order: 60013
since: 1.31.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Glyph expressions (G[I/N])

ConvRulesEditor Mapping menu: set, change or clear the G[I/N] glyph expression on the selected link.

Edit a link's glyph expression without touching the #link text.

## Details

A glyph expression links a From property to a To property through the index of an
item in a list or its count (C10): `G[I/N]`. ConvRulesEditor sets, changes or clears
it on the selected link so you do not edit the `#link` text by hand.

### Where it shows
**Mapping > Glyph expression...** acts on the selected link. The dialog sets, changes
or clears the expression.

### What to know
* The edit is made in the open book and is not saved until File > Save.
* convert-apply REFUSES a book whose `#link` carries a glyph expression until the
  engine realises G-links (CV-2); the refusal is reported on the Convert tab, not
  hidden.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
