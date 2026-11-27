# Glyph strips: convert-glyph-stitch

`--glyph-stitch` is a switch of `convert-apply` and `convert-validate`. It is OFF by default.
Since 1.56 the engine advertises it (`info --json` capability `glyph_stitch`), so the
conversion editor runs G-link books instead of greying them.

## What it does

A `#link` of a conversion book may carry a glyph expression `G[I/N]` (slot I of an N-slot
bitmap strip; see `docs\CONVERSION-RULES.md`). Without the switch, `convert-apply` refuses such a
book. With it, `convert-apply` slices the source `TBitmap` strip, stitches the chosen slots into
a new bitmap of the same height, depth and palette, and writes it to the target `.Data` through
the link's cast (give `--castlib`). `convert-validate --glyph-stitch` also errors on a G-link whose
`--from` class has no glyph-count reader.

## Steps

1. Preview: `drag-lint convert-apply --unit <F.pas> --rules <book.rules> --db <file.sqlite> --castlib <casts> --glyph-stitch`
2. Read the `glyphs[]` rows (`--format json`) or the `*** GLYPH TODO:` lines: `glyph-stitched` is a
   success, any other kind says what is missing.
3. Write: add `--apply`. Backups are kept unless `--no-backup`.

## Ask

- Convert a form with glyph strips: step 1, then step 3.
- Check the book first: `drag-lint convert-validate --rules <book.rules> --glyph-stitch --db <file.sqlite>`.

Full behaviour, outcome kinds and exit codes: [convert-apply](convert-apply).