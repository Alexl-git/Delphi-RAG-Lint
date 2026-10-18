<!-- Copied 2026-09-28 (autonomous housekeeping run) from the old session
     scratchpad C:\TEMP\claude\c--Projects-Delphi-RAG-lint\e32bbd16-840c-4d24-ac69-68be582720d4\scratchpad\cv7-gallery-review.md,
     which can be cleaned up or vanish at any time. This copy is the durable
     home. It holds the six CONV-8 owner decisions for GLYPH-CLASSES.md
     (Q1 consistency; TdxBarLargeButton's one 2-slot instance of 109; the
     M2022 scope note for section H; +5 non-glyph false positives in H;
     accept/defer ~140 form classes; the 6 single-glyph classes note). See
     `BACKLOG-TRIAGE-2026-09-28.md` CONV-8. -->

# CV-2 glyph-vacuum gallery review -- M2022 (owner review, drafted by subagent)

Copy reviewed: C:\TEMP\claude\vacuum-m2022\ (gallery.html, classes.tsv,
instances.tsv, skipped.tsv). Verified byte-identical in content to the
committed C:\Projects\Delphi-RAG-lint\docs\glyph-vacuum-results\m2022\ copy
-- same 887 distinct-payload images, same 213 <h2> class sections, same
classes.tsv (no diff). The only difference is card ORDER within a class
section (the HTML differs at byte 647; sorted image-src sets and <h2>
order are identical) -- this is non-deterministic hash-map iteration in the
vacuum, not a content drift, and does not affect any finding below.

No image viewer was used; every finding below is derived from gallery.html
own text (captions, separator-div counts, box width/height) and classes.tsv
/ instances.tsv, parsed programmatically. Stated plainly per the task own
allowance.

## Decisions for the owner

**RESOLVED 2026-10-05 (job item C11, owner ruling):** all six accepted as
recommended, for now, and applied to `docs\GLYPH-CLASSES.md`. Provisional --
the owner may correct them during the real conversion (long-term direction:
BMP glyphs -> SVG). Per-decision status is tagged below.

1. Accept as-is: Q1 consistency (all 5 dynamic/strip classes and all
   documented single-glyph/false-positive classes match the doc; agree=Y:75,
   agree=N:0, confirmed directly from instances.tsv, matching the doc
   claim). No correction needed to any existing GLYPH-CLASSES.md section.
   [RESOLVED 2026-10-05, C11: accepted; recorded in the M2022 corpus block.]
2. Decide: should TdxBarLargeButton get its own note that ONE of its 109
   instances (Glyph.Data, 32x16, inferred N=2, no declared count) is a real
   2-slot strip, contradicting its current blanket classification as
   ORM3-corpus "single-glyph, no strip" in section E? It is the only class the
   M2022 gallery own "strip or declared count" selection criterion misses.
   [RESOLVED 2026-10-05, C11: yes -- note added in section E.]
3. Decide: add a short M2022-scope note to section H
   (TOvcSimpleField/TOvcDbSimpleField/TOvcTCSimpleField/TQuery/
   TcxTreeList/TdxComponentPrinter) -- its instance counts (2/18/16/3/4/2)
   are ORM3-only and unlabeled as such; M2022 counts for the SAME classes are
   4/516/40/71/2/9, an order of magnitude different for TOvcSimpleField. A
   reader sizing "how much of this is false positive" from section H alone
   would be off by 28x on M2022.
   [RESOLVED 2026-10-05, C11: yes -- scope note added to section H.]
4. Decide: extend section H with 5 more M2022-only non-glyph false
   positives never documented: TFDMemTable.Content (2), TdxDBGrid.Filter.
   Criteria (3), TdxMemData.Persistent.Data (14), TTreeView.Items.Data
   (1), TcxGridTableView.DataController.Data (1) -- all blank-format,
   0x0x0, not images, same shape as the existing 6 H-classes.
   [RESOLVED 2026-10-05, C11: yes -- the 5 added to section H.]
5. Accept/defer: about 140 M2022 form classes (TAboutBox, TMainFrm,
   TfrmMEStats, ... ) are plain Icon.Data-only classes, the exact shape of
   section F, but none are individually named there (F 39-name list is
   ORM3-only). Given F own text already covers the shape generically, this
   is likely fine to leave as-is -- flagging for the owner to confirm rather
   than recommending a fix.
   [RESOLVED 2026-10-05, C11: left as-is; decision recorded in section F.]
6. Optional: note 6 more DevExpress/Raize single-glyph classes present
   only in M2022 and undocumented in section E (TcxBarEditItem,
   TdxBarDateCombo, TdxBarInPlaceSubItem, TdxBarScreenTip,
   TdxBarScreenTipRepository, TdxRibbonRadialMenu), plus TRzDBTrackBar
   -- a near-namesake of the documented TRzTrackBar (M2022.7) that does
   NOT share its 6-cell CustomThumb strip shape (M2022: single 16x16,
   inf=1, not a strip) -- worth a one-line note so nobody assumes the two
   classes share slot semantics by name proximity.
   [RESOLVED 2026-10-05, C11: SKIPPED; the skip recorded in section E.]

---

## Q1: per-class N/slot consistency vs GLYPH-CLASSES.md

Checked every class the doc claims a shape for, against classes.tsv /
instances.tsv directly (not the doc own restated numbers):

- TabcToggleBtn: n_distribution 4:20, inferred_distribution 4:20, 0
  disagreements. Matches doc exactly (A.1 + M2022 corpus block).
- TBitBtn: n_distribution 2:10;?:6, inferred_distribution
  2:9;1:6;?:1. Matches doc exactly (A.2 M2022 corpus block).
- TcxButton: n_distribution 4:8;2:14;?:57, inferred_distribution
  4:8;2:14;1:3;?:54. Matches doc exactly (A.3 M2022 corpus block).
- TRzBitBtn: n_distribution 4:20;?:1, inferred_distribution
  4:20;1:1. Matches doc exactly (M2022.1).
- TRzToolbarButton: n_distribution 2:4, inferred_distribution
  2:4. Matches (M2022.2).
- TcxGridDBColumn, TdxDBGridCheckColumn, TRzCheckList,
  TRzDBRadioGroup, TRzRadioGroup, TRzTrackBar: all 6 match the doc
  M2022.3-M2022.7 numbers and the shared-payload_sha claim (verified the
  20de6362... sha is shared across TdxDBGridCheckColumn,
  TRzCheckList, TRzRadioGroup, one TcxGridDBColumn instance, exactly as
  claimed; TRzDBRadioGroup and TRzTrackBar carry their own distinct shas
  as claimed).

No class in the gallery disagrees with GLYPH-CLASSES.md stated N /
slot-count claims. agree is Y for 75 rows and N for 0 rows across all
2721 M2022 instance rows (direct count from instances.tsv), matching the
doc claim of "same no declared/inferred disagreement anywhere result as ORM3"
statement exactly.

Gap found (see decision 2): TdxBarLargeButton is documented only in
section E as single-glyph, no-strip. The M2022 gallery has 109 instances of
this class; 107 have no usable geometry (93 SVG plus others), but ONE payload
(Glyph.Data, 32x16x32 bmp, inferred N=2, shared by 1 instance, no declared
count) is a genuine 2-slot strip candidate. classes.tsv own
inferred_distribution for this class is 2:1;1:15;?:93 -- meeting the
M2022 per-class table own stated selection bar ("every class with a strip
or a declared count property", GLYPH-CLASSES.md line 378) but not included in
that table.

## Q2: classes with dynamic N (drive per-N grammar alternatives)

Computed directly from classes.tsv (more than 1 distinct numeric N value,
declared or inferred, across instances):

| class | instances | n_distribution (declared) | inferred_distribution |
|---|---|---|---|
| TBitBtn | 16 | 2:10;?:6 | 2:9;1:6;?:1 |
| TcxButton | 79 | 4:8;2:14;?:57 | 4:8;2:14;1:3;?:54 |
| TcxGridDBColumn | 28 | ?:28 (none declared) | 6:26;2:1;1:1 |
| TdxBarLargeButton | 109 | ?:109 (none declared) | 2:1;1:15;?:93 |
| TRzBitBtn | 21 | 4:20;?:1 | 4:20;1:1 |

First 3 and TRzBitBtn are already in GLYPH-CLASSES.md. TdxBarLargeButton
is the one NOT flagged as dynamic-N anywhere in the doc (see decision 2). All
other strip-bearing classes (TabcToggleBtn, TRzToolbarButton,
TdxDBGridCheckColumn, TRzCheckList, TRzDBRadioGroup, TRzRadioGroup,
TRzTrackBar) have a SINGLE fixed N across every instance -- not dynamic.

## Q3: anomalies

- No malformed/zero-width raster images. Scanned every card box
  width/height and bmp-format size string; zero BMP-format entries decode
  to 0x0x0, zero cards contain other than exactly 1 img tag. The many
  0x0x0 captions in the gallery (roughly half of 887 cards) are SVG/ICO/
  PNG/JPG rows -- expected by design, since ParseStreamedGraphic only fills
  width/height/bpp for BMP (GLYPH-CLASSES.md line 288 already states this).
  Not a defect.
- No separator/N mismatches. Every card whose caption states a declared
  N shows exactly N-1 separator divs; the strip-but-no-declared-count
  classes (TcxGridDBColumn, TdxDBGridCheckColumn, TRz-family 6-cell classes)
  correctly draw 0 separators since the gallery only overlays separators from
  count_effective, per the design spec section 5 -- consistent, not a bug.
- Duplicates confirmed: the 4-way shared payload_sha
  20de6362... across TdxDBGridCheckColumn/TRzCheckList/TRzRadioGroup/
  one TcxGridDBColumn instance is exactly as GLYPH-CLASSES.md describes.
- Classes in gallery, missing from doc: 140 (mostly Tfrm-prefixed form-icon
  classes, same shape as documented section F but unnamed -- decision 5) plus
  5 genuine undocumented non-glyph false positives (decision 4) plus 7
  undocumented single-glyph DevExpress/Raize classes (decision 6). Full list
  captured during the review; can be attached if wanted.
- Classes in doc, missing from M2022 gallery: TdxLayoutImageItem,
  TdxPDFViewer, and 4 ORM3-specific form names (TfrmDrawingPages,
  TfrmJobList, TfrmMAIN, TfrmMETemplateSetup) -- all legitimately
  ORM3-only components/forms, not present in M2022 dfm set. Not an
  error.
- Format distribution (all 2721 M2022 rows): svg:939, bmp:849, ico:170,
  png:9, jpg:2, blank:752. Zero wmf/emf (confirmed directly, matching
  the doc ORM3 finding, now also true for M2022).

## Q4: grammar-design assumptions the gallery contradicts or stresses

- Spec section 1 lists only TBitmap/TIcon/TMetafile inside TPicture,
  plus PNG as an outlier, as expected source formats. SVG is 939 of 2721 rows
  (35 percent) in M2022 -- the LARGEST single format, not a corner case --
  already flagged as the spec own most consequential vacuum finding; this
  review confirms it holds at full M2022 scale, not just the smaller ORM3
  sample.
- JPG (2 rows, both TdxBarButton.Glyph.Data) is not named anywhere in
  spec section 1 format list, not even as an outlier alongside PNG. Trivial
  count, but worth a one-line mention for completeness since PNG got one.
- Spec 3.2 "actual N matches nothing" and "glyph-not-a-strip" TODO paths
  remain UNEXERCISED: agree=N is 0 across all 2721 M2022 rows too (matches
  the ORM3-only finding already recorded) -- still no real corpus coverage
  for those two paths; still needs a synthetic fixture, as the spec already
  says.
- Section 5 per-class N-reader table (seeded with TabcCustomPicSpeedBtn)
  has no entry for TdxBarLargeButton one real 2-slot instance (decision
  2) -- a G-link on it would correctly hit the "no N reader" validate error
  per rule 3.2, so nothing in the grammar itself is contradicted, but the
  class-knowledge file would benefit from marking it explicitly "mostly
  single, rare 2-slot outlier" rather than leaving it silent.
