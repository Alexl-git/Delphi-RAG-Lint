---
id: convrules-examine
title: "Examine: mark the properties a form uses"
summary: "ConvRulesEditor Conversion menu: pick .dfm/.pas files and mark in green the From properties they actually use"
product: DL
group: component-conversion
order: 60012
since: 1.31.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Examine: mark the properties a form uses

ConvRulesEditor Conversion menu: pick .dfm/.pas files and mark in green the From properties they actually use.

See which properties of a class your forms really use before mapping.

## Details

A class can have hundreds of properties and a form uses a handful. Examine reads the
`.dfm` / `.pas` files you pick and marks, in green, the From properties those files
actually use, so you map those first.

### Where it shows
**Conversion > Examine...** picks the files. **Conversion > Clear marks** drops the
examination and unmarks every row. "Types on form (Examine to fill)" is the list the
examination fills.

### What it changes
Nothing in the book: the marks are a view aid and never touch the rule book, its
Snapshot or its dirty flag.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
