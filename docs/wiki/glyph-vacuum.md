# glyph-vacuum

Measure every image your forms stream before you write a glyph rule. It walks the
`.dfm` / `.fmx` files under one or more root folders, decodes each `Picture.Data` /
`Glyph.Data` blob (wrapper class, format, width, height, bits per pixel, palette) and pairs
it with its count property (`NumGlyphs` and kin). Use it when you convert a component whose
pictures or glyph strips must survive the conversion and you need to know what is out there
first.

## Running it from the CLI
```
drag-lint glyph-vacuum --root DIR [--root DIR ...] --output DIR [--append] [--db PATH ...]
```
`--root` is a folder to scan and may be repeated. `--output` is the folder that receives the
result files; `--append` adds this run to a measurement already there instead of replacing it.
`--db` may be repeated.

## What you get
In the output folder: `instances.tsv` (one row per streamed graphic), `classes.tsv` (one row per
wrapper class), `skipped.tsv` (blobs it could not decode, with the reason) and an `images\`
folder with the decoded pictures.

## Reaching it in the IDE
No IDE surface -- this is a CLI-only feature. The glyph expressions of a rule book
(`G[I/N]`) are authored in the ConvRulesEditor; see [ConvRulesEditor](convrules-editor).

## What it needs
The folders to scan. An index is optional (`--db`).

## Where it fits
Run `glyph-vacuum` first, read `classes.tsv` to see which wrapper classes and sizes occur, then
write the glyph rule in your book and check it with `convert-validate`.