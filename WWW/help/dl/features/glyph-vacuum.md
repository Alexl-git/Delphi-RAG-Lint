---
id: glyph-vacuum
title: glyph-vacuum
summary: Measure every streamed glyph or picture under a tree before writing a glyph rule
product: DL
group: component-conversion
order: 60015
since: 1.15.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# glyph-vacuum

Measure every streamed glyph or picture under a tree before writing a glyph rule.

Before you write a glyph rule, measure every image embedded in your forms: size, format and how many images each list holds.

## How to run it

Full flag list: [glyph-vacuum in the CLI reference](../cli.md#glyph-vacuum).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--root` | `DIR` |  |  |
| `--output` | `DIR` |  |  |
| `--append` |  |  |  |
| `--db` | `PATH` |  |  |

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Measure every image your forms stream before you write a glyph rule. It walks the
`.dfm` / `.fmx` files under one or more root folders, decodes each `Picture.Data` /
`Glyph.Data` blob (wrapper class, format, width, height, bits per pixel, palette) and pairs
it with its count property (`NumGlyphs` and kin). Use it when you convert a component whose
pictures or glyph strips must survive the conversion and you need to know what is out there
first.

### Running it from the CLI
```text
drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]
```
`--root` is a folder to scan and may be repeated. `--output` is the folder that receives the
result files; `--append` adds this run to a measurement already there instead of replacing it.
`--db` may be repeated.

### What you get
In the output folder: `instances.tsv` (one row per streamed graphic), `classes.tsv` (one row per
wrapper class), `skipped.tsv` (blobs it could not decode, with the reason) and an `images\`
folder with the decoded pictures.

### What it needs
The folders to scan. An index is optional (`--db`).

### Where it fits
Run `glyph-vacuum` first, read `classes.tsv` to see which wrapper classes and sizes occur, then
write the glyph rule in your book and check it with `convert-validate`.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
