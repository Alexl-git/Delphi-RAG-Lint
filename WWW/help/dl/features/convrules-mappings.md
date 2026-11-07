---
id: convrules-mappings
title: "Conditional #mapping authoring"
summary: "ConvRulesEditor Mapping menu: author a conditional #mapping (one enum value sets several target properties) and #apply it to a conversion"
product: DL
group: component-conversion
order: 60015
since: 1.31.0-alpha
status: shipped
updated: 1.46.0-alpha
---

# Conditional #mapping authoring

ConvRulesEditor Mapping menu: author a conditional #mapping (one enum value sets several target properties) and #apply it to a conversion.

Write a conditional #mapping without hand-editing #when lines.

## Details

A `#mapping` makes one enum VALUE set several target properties: "when the From
property is `X`, set To property `A` and `B`". ConvRulesEditor authors it for you
instead of hand-writing the `#mapping ... #when` lines.

### Where it shows
**Mapping > Mappings...** opens the mapping editor for the selected conversion. The
dialog authors the `#mapping` block and then `#apply`s it to the open `#convert`
block, so the mapping is written once and can be shared by several blocks.

### What it changes
The `#mapping` lines land in the open rule book and the `#apply Name` line in the
block; nothing is saved until File > Save. Save validates the book (see the scoped
validation page): a mapping path the From or To class does not have is marked on the
mapping line.

Names are matched without regard to case, as the engine does: `#apply M` and
`#apply m` name the same mapping.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
