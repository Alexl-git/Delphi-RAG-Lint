# Wave 146 lane g4: C-SPLITMERGE (glyph generate-and-stitch) and C-VALIDATE-ALL-CACHE

Status: first phase built behind an OFF switch; the owner reverses or promotes it.
Rulings this implements: `2026-09-17-glyph-strip-G-grammar-design.md` (grammar, section 6
realisation) and the wire contract `2026-10-06-c10-engine-asks.md` (N1-N8). Both are
ruled; this note only records what the engine half chose where they leave room.

## 1. C-VALIDATE-ALL-CACHE: FIXED-already, no new cache

The row quotes `INBOX-2026-09-30-engine-followups-from-1.20.5.md` item 10: every-block
validation ~25 min per unit (`TFDQuery` ~5.5 min alone), asking for a persistent tree
cache keyed by (library DB, type, DB stamp).

1.20.6 (88bb82ae, f0ae60d6) removed the premise: no tree is built. Paths resolve segment
by segment against `TPropMemberCache` (per run, one class resolved once), and
`--validate-all-blocks` is gone because every block is always validated.

Measured 2026-11-06 on the deployed 1.44.1 engine, library-Win32 (3 GB), machine
saturated by other lanes, real `convrules\BDE-to-FireDAC.rules` (7 blocks):

| what | before (1.20.5, recorded) | now (measured) |
|---|---|---|
| whole book, one unit, every block validated, `convert-apply` dry run | ~25 min | 49 s, 47 s |
| `convert-validate` of the book against `TQuery -> TFDQuery` | `TFDQuery` ~5.5 min alone | 17.6 s |

`classes_built=30`. The "before" column is the note's number: the 1.20.5 engine cannot
open a current library DB, so it was not re-run. Guard: `run_convert_lazy_paths.ps1`
(R2 pins < 60 s for the whole book with `-RealBook`).

Options considered:

| option | verdict |
|---|---|
| A. Persistent tree cache keyed by DB stamp | Rejected. Solves a cost that no longer exists, and adds an invalidation surface to a read-only verb that opens real DBs read-only. |
| B. Nothing; keep the per-run member cache | **Chosen.** |
| C. Share the member cache across units of one batch | Already so: `TConvertTreeCache` is one per run, so a batch pays once. |

Reversible: if a measured need appears (the editor spawns one engine per unit, so it pays
about 50 s a unit on a loaded machine) option A can be added later without a format change.

## 2. C-SPLITMERGE: options for how it ships

| option | verdict |
|---|---|
| A. Retire the refusal, advertise `glyph_stitch` now | Rejected for this wave: changes default behaviour, and the editor would un-grey G-link books before the owner reviewed the bytes. |
| B. `--glyph-stitch` on `convert-apply` and `convert-validate`, OFF by default; refusal and capability unchanged without it | **Chosen.** Lane rules: "behind an OFF switch ... no default behaviour changed". |
| C. New verb | Rejected: every plan, freshness and report path of `convert-apply` would be duplicated. |

**Promotion (owner's call), three small edits:** drop the switch's test in
`ValidateConvertBook`, drop the `AArgs.GlyphStitch` gate in `DoConvertValidate`, add
`JCap.AddPair('glyph_stitch', TJSONBool.Create(True))` and flip arm I1 of the guard. The
editor needs no edit: it greys G-link books until that key appears.

## 3. What was built

* `DRagLint.Convert.GlyphExpr.SelectGlyphAlternative` (grammar 3.2) and `GlyphCountReaders`,
  the seeded class table (N5), in the pure unit the editor already imports, so `Rules` and
  `DfmReemit` share one table without a new dependency.
* `DRagLint.Convert.GlyphStrip.CheckBitmapStrip`, `StitchBitmapSlots`: slices columns, stitches a
  slot list, same height, bpp, palette and header.
* `DRagLint.Convert.Rules.GlyphReaderIndexFor`, `MissingGlyphCountReaders` (N4).
* `DRagLint.Convert.DfmReemit`: step 3c realises every image G-link and its `G[count]`
  leaves before the leaf walk; G-links can no longer be carried whole by any other path.
* `DRagLint.Convert.Apply`: outcomes, the TODO line at the top of `implementation`.
* `DRagLint.CLI`: `--glyph-stitch`, `glyphs[]`, prominent text lines.

## 4. Assumptions the owner can reverse

1. **`G[count]` counts SLOTS, not written terms.** Grammar 3 says "number of terms" but its
   own table 3.4 gives `G[*/4]` count 4. The table wins: the target must split the image
   back into that many glyphs.
2. **A stitched outcome is a receipt, not an `items[]` entry.** Ask N3 mirrors it into
   `items[]` under field `converted`, but then `converted[]` no longer counts instances and
   the header `%d instance(s) converted` would lie. It goes to `glyphs[]` only, exactly as
   `resolved_defaults` does; the editor's own `apply-glyphs-sample.json` already has that
   shape (`converted[]` holds instance rows only). TODO kinds do go to `items[]` / `todos[]`.
3. **`glyphs[]` is always present** in apply/1, `[]` when none (N3), also with the switch off.
   Additive and harmless; a consumer reads it as optional.
4. **TODO owner is the fixed word `converter`**: the ruling says "fixed owner" and names none.
5. **Without a usable cast nothing is written** (N6's open question answered as its "NO"):
   a missing `--castlib`, or a cast that is not `keep-bytes-if-compatible`, is a
   `glyph-format-unsupported` TODO, image and count both.
6. **A no-cast G-link keeps the source's own framing**, as N6 words it for TBitmap -> TBitmap,
   and is only allowed when the leaf types are identical.
7. **An inherited block with no streamed count property is a TODO.** Absent there means
   inherited, not default, so N is unknown. Never guessed.
8. **An owned part** (the recursion handed the parent's classes) is not stitched: its leaf
   falls to `dropped`, reported, never carried whole.
9. **The N reader consumes the source count property**: when no `#link` names it, it is not
   reported as dropped, since `G[count]` replaced it. A straight carry beside a G-link still
   writes what the author asked for; validate already warns.
10. **A `.pas` access site of a G-linked member is refused per site** (grammar section 7,
    tier 3, build 1). Tiers 1 and 2 stay out of scope (build 2).
11. **Formats:** BI_RGB and BI_BITFIELDS, bpp 1/4/8/16/24/32, headers of 40+ bytes. RLE, a
    core header and an embedded V5 profile are `glyph-format-unsupported`.

## 5. Not built, deliberately

`.pas` tiers 1-2, `.fmx`, PNG/ICO strips, `convert-scaffold`'s stub (N9, optional), the hidden
`convert-reemit` (keeps refusing), the capture swap in the editor's fixture folder (the
capture sits in `tests\fixtures\glyph\`; CONVERTER owns the editor and swaps it).
