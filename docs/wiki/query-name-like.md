# query --name-like

Case-insensitive **substring** search over symbol names. This is the discovery
query -- the one you reach for when you do **not** know the identifier yet.

Every other drag-lint lookup assumes you already have the name. This one gets
you *to* it.

## The question it was built for

> Does this Delphi install have anything that can rasterise an SVG?

`query --name SVG` answers that with two rows, both literally *named* `SVG`.
The types that actually mattered -- `Vcl.Skia.TSkSvgBrush`, `FMX.Skia.TSkSvg`,
`dxSVGCore.TdxSVGBrush` -- were previously found by guessing candidate names one
at a time, or by grepping the RTL and DevExpress trees.

```
drag-lint query --name-like svgbrush --db C:\Projects\.drag-lint\library-Win32.sqlite --limit 5
```

```
kind         name                           qualified_name
---------------------------------------------------------------------------
field        FSvgBrush                      Vcl.Skia.TSkSvgGraphic.FSvgBrush : TSkSvgBrush
class        TSkSvgBrush                    FMX.Skia.TSkSvgBrush
class        TSkSvgBrush                    Vcl.Skia.TSkSvgBrush
class        TdxSVGBrush                    dxSVGCore.TdxSVGBrush
5 match(es)
```

## Running it from the CLI

```
drag-lint query --name-like <substring> [--kind class,interface,...] [--limit N] [--json] --db <file.sqlite>
```

## Reaching it in the IDE

No IDE surface -- this is a CLI-only feature.

## What it needs

An index IS required. Resolve it with
`drag-lint resolve-dbs --project <X.dproj>` or `--in <X.pas>`. For API discovery
the **library** index is usually the one you want, since that is where the RTL,
VCL, FMX and third-party symbols live.

## How it differs from `--name`

| | matches |
|---|---|
| `--name Foo` | the symbol *named* `Foo`, plus an **edit-distance** fallback for near-misses |
| `--name-like Foo` | every symbol with `foo` anywhere in its name |

They are separate flags on purpose. Quietly widening `--name` into a substring
search would change what every existing caller gets back, the IDE plugin
included.

The edit-distance fallback is not a substring search and cannot stand in for
one: `SVG` does not fuzzy-match `TSkSvgBrush`, because the candidate is four
times longer than the query. Nor does `query --text`, which searches string
*literals* -- captions, constants, SQL messages -- and cannot see a type name at
all.

## Ordering and the cap

Results come back **shortest name first**, then alphabetically. For a discovery
question `TSkSvg` is a far more useful first row than
`TdxSVGImageCollectionHelperInternal`.

`--limit` defaults to 50. When it truncates it says so:

```
-- LIMIT REACHED at 50; there may be more. Pass --limit N, or narrow with --kind.
```

`--kind` takes a comma-separated list (`class,interface,record,type,function,
procedure,field,...`) and is usually the better way to cut noise, because
discovery is nearly always "what *class* does X".

## Speed, and the one case that is slow

The search is driven by the `symbol_trigrams` table rather than a bare
`LIKE '%x%'`, which cannot use an index because of the leading wildcard.
Measured on `library-Win32.sqlite` (3.3 GB): **18,923 ms** for the bare scan
versus **12 ms** driven from trigrams.

A term **shorter than three characters** has no trigram, so it falls back to
that full scan. The command tells you before the wait:

```
NOTE: "cx" is shorter than 3 characters, so the trigram index cannot narrow it
-- this falls back to a full scan and will be slow on a large index.
```

## JSON

`--json` emits the same row shape as `query --name`, with one difference worth
knowing: rows are labelled `"match_kind": "substring"`. They are **not**
`"exact"` -- `exact` is a claim that the symbol *is* what you asked for, and
`qlitesymbol` is not the name of `TSQLiteSymbolStore`.
