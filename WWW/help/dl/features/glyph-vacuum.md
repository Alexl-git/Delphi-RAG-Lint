---
id: glyph-vacuum
title: glyph-vacuum
summary: Measure every streamed glyph or picture under a tree before writing a glyph rule
product: DL
group: component-conversion
order: 60010
since: 1.15.0-alpha
status: shipped
updated: 1.15.0-alpha
---

# glyph-vacuum

Measure every streamed glyph or picture under a tree before writing a glyph rule.

## How to run it

```text
drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...] (measure every streamed graphic under the roots before writing a glyph rule: walks .dfm/.fmx, decodes each Picture.Data/Glyph.Data blob (wrapper class, format, width/height/bpp/palette), pairs it with its count property (NumGlyphs and kin), writes instances.tsv + classes.tsv + skipped.tsv + images\ + gallery.html into --output; --append merges into an existing --output; --db only qualifies class_unit / declared count default / runtime_refs)
```

Full flag list: [glyph-vacuum in the CLI reference](../cli.md#glyph-vacuum).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
