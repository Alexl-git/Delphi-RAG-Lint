# Glyph classes -- the authoritative record of how legacy controls hold their glyphs

Maintained by the AI session that investigates a class; consulted BEFORE any
`G[...]` rule is written (spec: docs\superpowers\specs\2026-09-17-glyph-strip-G-grammar-design.md,
section 5). A G-link on a class with no section here is a validate error by design.
Informal on purpose: collect whatever helps the goal of a deterministic N
algorithm. Regenerate the corpus numbers with `drag-lint glyph-vacuum`.

**First real run: 2026-09-17.** `glyph-vacuum --root C:\Projects\DB\ORM3 --out
C:\TEMP\claude\vacuum-orm3 --db <abc5-scratch-lib> --db
C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite` -- `dfm=108 graphics=1016
distinct=208 skipped=0`, 72 distinct component classes in classes.tsv. The
`--root` walked ORM3's `BACKUP\` folder too (not only `CLIENT\`), which is why a
few instances below cite a `BACKUP\*.dfm` source -- noted per class where it
matters.

**Re-measured 2026-09-17 after Task 10** (same command, no `--append` --
replaces the first run's output; `dfm=108 graphics=1016 distinct=208 skipped=0`
and 72 classes are unchanged, since decoding does not change what gets
harvested, only whether `format`/`width`/`height` fill in): `ParseStreamedGraphic`
now also decodes raw SVG text (`TdxSmartGlyph`) and the length-prefixed bare
bitmap form (`[Int32 LE length][image]`, no class name -- `TBitmap`-typed
properties such as `TBitBtn.Glyph.Data`), and the EMF sniff requires the real
`" EMF"` signature instead of the bare `01 00 00 00` iType alone. Rows with a
non-empty `format` went from **161 of 1016 (before Task 10)** to **947 of 1016**;
the remaining 69 blank-`format` rows are the genuine non-image blobs in section H
plus the still-open container/collection cases noted in sections D and E.
`agree = Y` went from 23 to **25** rows (2 more `TBitBtn` instances now have a
decoded width/height to compare against their `NumGlyphs`); `agree = N` is still
zero. See the per-class updates below and the **Gallery review** section at the
bottom.

**Read this before trusting a row below:** the vacuum harvests every binary
(`dnkBinary`) property in a `.dfm`, not just ones named Glyph/Picture/Icon/Image.
Several classes in the corpus have NO image property at all; their binary blob
is something else entirely that happens to stream as a hex block. Those are
called out explicitly in section H so nobody writes a glyph rule against them.

Also see the **Vacuum findings (2026-09-17)** block at the top of the grammar
spec for the two systemic decode gaps the first run exposed (SVG glyphs, and a
4-byte-length-prefixed bare bitmap form) -- both are FIXED as of Task 10 (commit
`2343c0bc`); the notes below record what changed in the corpus, not an open gap.

---

## A. Classes with a real glyph-count property

### A.1 Abcbtn.TabcCustomPicSpeedBtn (and every descendant: TabcToggleBtn, TabcPicSpeedBtn, ...)

- **Image property:** `Picture: TPicture` (streams as `Picture.Data`, wrapper `TBitmap`)
- **N:** `NumGlyphs: TabcNumGlyphs = 1..5`, declared `default 1`; declared
  `{after picture!}` (`C:\Projects\ABC5\ABC5\Source\Abcbtn.pas:324`) -- order-dependent
  at stream time. `TabcNumGlyphs = 1..5` itself is declared at `Abcbtn.pas:48`.
- **Slots** (derived from the paint path, not guessed): `Paint`
  (`Abcbtn.pas:2823`) delegates to `TabcButtonGlyph(FGlyph).Draw` (`Abcbtn.pas:1598`),
  which calls `DrawButtonGlyph`/`DrawButtonGlyphTiled` (`Abcbtn.pas:1615`,`1631`),
  both of which call `CreateButtonGlyph(State: TabcButtonState)` (`Abcbtn.pas:1249`).
  `TabcButtonState = (absUp, absDisabled, absDown, absExclusive, absMouseOver)`
  (`Abcbtn.pas:46`) -- 5 members, matching `TabcNumGlyphs = 1..5` exactly. The
  slot index is the state's ordinal (`ORect := Rect(Ord(I) * IWidth, 0, ...)`,
  `Abcbtn.pas:1315`, clamped to `absUp` when `Ord(I) >= NumGlyphs` at line 1313-1314):
  - slot 1 (Ord 0) = `absUp` -- normal
  - slot 2 (Ord 1) = `absDisabled` -- disabled (grayed via the highlight/shadow
    remap at `Abcbtn.pas:1337-1368`, or a generated mono mask when `NumGlyphs = 1`)
  - slot 3 (Ord 2) = `absDown` -- down; only reachable when `NumGlyphs >= 3`
    (`if (State = absDown) and (NumGlyphs < 3) then State := absMouseOver;`,
    `Abcbtn.pas:1259`, i.e. a 1-2 glyph strip has no distinct "down" art)
  - slot 4 (Ord 3) = `absExclusive` -- "stay down" (drawn with the brush-pattern
    face fill selected in `Paint`, `Abcbtn.pas:2843-2850`; matches the VCL
    `TNumGlyphs` convention's 4th slot)
  - slot 5 (Ord 4) = `absMouseOver` -- hot/hover highlight. **No VCL/TcxButton
    counterpart** -- standard `TNumGlyphs = 1..4` stops at slot 4, so this is
    ABC's own addition and the reason the source range is 1..5 while every
    known target tops out at 4.
- **Layout:** horizontal strip, square glyphs; `IWidth := PictureBmp.Width div
  FNumGlyphs` (`Abcbtn.pas:1299`) confirms `width = N * height` is read off the
  strip, not assumed.
- **Corpus (ORM3, 2026-09-17, glyph-vacuum):** `TabcToggleBtn`, 20 instances,
  `n_distribution 4:20`, `inferred_distribution 4:20`, `disagreements 0`,
  `formats bmp:20`, `distinct_payloads 3`, `runtime_refs 16`, `count_default 1`
  (confirms the range-mismatch note's expectation exactly: `4:20`, default `1`,
  `bmp:...`).
- **Corpus (M2022, 2026-09-17, glyph-vacuum):** identical shape on a second
  codebase -- `TabcToggleBtn`, 20 instances, `n_distribution 4:20`,
  `inferred_distribution 4:20`, `disagreements 0`, `formats bmp:20`,
  `distinct_payloads 3`, `runtime_refs 16`. See the M2022 corpus block below.
- **Open:** does any corpus hold `NumGlyphs = 5`? ORM3: **0** (every one of the
  20 instances streams `NumGlyphs = 4`). The 5-slot case is a property of the
  control, not of this corpus, per the spec's own framing.

### A.2 TBitBtn (VCL, `Vcl.Buttons`)

- **Image property:** `Glyph: TBitmap` (streams as `Glyph.Data`, wrapper empty
  -- a `TBitmap`-typed property carries no class name, only its own 4-byte
  length prefix; see the fixed decode gap below).
- **N:** `NumGlyphs: TNumGlyphs = 1..4` (VCL standard: normal/disabled/down/stay-down).
- **Corpus (re-measured after Task 10):** 3 instances (all from
  `C:\Projects\DB\ORM3\BACKUP\EWrkSLCT.dfm`, a backup copy under the walked
  root, not `CLIENT\`), `count_value = 2` on all 3, `count_props NumGlyphs`,
  `formats bmp:3`, `distinct_payloads 3`. `btn_Cancel`/`btn_Ok` decode to
  36x18 (`inferred_n 2`, `agree Y`); `Panel3.BitBtn2` decodes to 36x19 (not
  evenly divisible by 2, so `inferred_n`/`agree` stay empty -- a real
  disagreement between the strip's own pixel height and `NumGlyphs`, not a
  decode failure).
- **Corpus (M2022, 2026-09-17, glyph-vacuum):** 16 instances (not 3 -- this is
  a different codebase with its own `.dfm` set), `count_props NumGlyphs`,
  `n_distribution 2:10;?:6` (6 instances don't stream `NumGlyphs` at all),
  `inferred_distribution 2:9;1:6;?:1`, `disagreements 0`, `formats bmp:16`,
  `distinct_payloads 7`. See the M2022 corpus block below for the full table.
- **Fixed (Task 10, commit `2343c0bc`):** all 3 payloads previously failed to
  decode: `wrapper`, `format`, `width`, `height`, `bpp` all came back empty
  despite plausible byte counts (2002, 2002, 502). Read the raw hex for
  `btn_Cancel` in `BACKUP\EWrkSLCT.dfm`: it starts `CE070000 424D CE070000
  ...` -- a little-endian **Int32 byte count (`0x000007CE` = 1998)**,
  immediately followed by a real `BM...` bitmap whose own internal `bfSize`
  happens to equal the same 1998. This is a THIRD streaming form, distinct
  from both forms `DRagLint.Convert.GlyphStrip.ParseStreamedGraphic` knew
  before Task 10 (wrapped-with-classname for `TPicture`, and
  bare-with-magic-at-offset-0): a `TBitmap`-typed property (no class name
  needed, the static type already says `TBitmap`) streams `[Int32
  size][raw bitmap bytes]`, so the `BM` magic sits at **offset 4**, not
  offset 0. `ParseStreamedGraphic` now checks this shape -- `Length(payload)
  >= 8`, the leading Int32 equal to `Length - 4`, and a recognised magic at
  offset 4 -- before the class-name-preamble branch, and reports it with an
  empty `Wrapper` just like the bare-at-offset-0 case. The same shape also
  explains `TOvcNumberEdit.ButtonGlyph.Data` and `TRzMenuButton.Glyph.Data`
  in section E below, both `TBitmap`-typed and now decoding as `bmp` too.

### A.3 cxButtons.TcxButton (target side, for reference)

- `OptionsImage.Glyph: TdxSmartGlyph` (streams as the DOTTED scalar
  `OptionsImage.Glyph.Data`), `OptionsImage.NumGlyphs: TNumGlyphs = 1..4`
  (streamed as the dotted scalar `OptionsImage.NumGlyphs`; **not resolvable
  through either `--db` passed this run** -- `query --name TcxButton --db
  <Micronite2027.sqlite> --exact` returns 0 matches, confirming `TcxButton` is
  a DevExpress library class outside ORM3's own compile closure, not a bug;
  the `1..4` range is carried over from the range-mismatch note, unconfirmed
  by an index this session because `library-Win64.sqlite` is schema v22 and
  refused as stale against this v23 engine).
- **Fix landed this session:** `OptionsImage.NumGlyphs` is a dotted scalar
  name, not a bare sibling of `CountPropNames` -- before the fix, `count_prop`
  came back empty for every `TcxButton` row. `FindCountProp`/`IsCountPropName`
  now match on the LAST dot-segment of the scalar's name and keep the FULL
  dotted name as `count_prop` (`src\report\DRagLint.Convert.GlyphVacuum.pas`,
  `IsCountPropName`). Commit `2df9601f`.
- **Corpus (post dotted-count fix, `2df9601f`):** 36 instances, `count_props
  OptionsImage.NumGlyphs`, `n_distribution 2:3;?:33` (3 instances declare
  `OptionsImage.NumGlyphs = 2`; 33 don't stream it at all -- and `count_default`
  is empty because `TcxButton` isn't in either index, so there is no
  declared-default fallback; the gap here is `TcxButton` being OUT OF SCOPE,
  not the fallback itself -- the final-review wave fixed the fallback so a
  default-valued DOTTED count (e.g. `Options.NumGlyphs`) IS resolvable through
  the tree once its class is indexed, see `FactsFor`/`AddRow`'s count-tree
  walk in `src\report\DRagLint.Convert.GlyphVacuum.pas`), `inferred_distribution 2:3;1:1;?:32`,
  `disagreements 0`, `distinct_payloads 15`; `class_unit`/`runtime_refs` both
  empty (class not indexed).
- **Corpus (re-measured after Task 10, commit `2343c0bc`):** `formats
  bmp:5;svg:31` -- the 31 instances that used to report an unresolved format
  are now confirmed and decoded as SVG (`TdxSmartGlyph` streams raw XML text,
  no preamble). `width`/`height` stay 0 for the SVG rows by design (an SVG
  glyph is not a raster strip; geometry is not inferred from vector text), so
  `agree`/`inferred_n` are unaffected -- still 3 `Y` rows, all from the `bmp`
  side.
- **Corpus (M2022, 2026-09-17, glyph-vacuum):** 79 instances (vs 36 in ORM3),
  `count_props OptionsImage.NumGlyphs`, `n_distribution 4:8;2:14;?:57`,
  `inferred_distribution 4:8;2:14;1:3;?:54`, `disagreements 0`, `formats
  bmp:27;svg:52`, `distinct_payloads 34`. Confirms the dotted-count fix
  (`2df9601f`) generalises to a second codebase: `count_prop` resolves for
  every instance that streams `OptionsImage.NumGlyphs`, including the new
  `4:8` group this corpus adds that ORM3 didn't have. See the M2022 corpus
  block below.

---

## B. Per-button single glyphs, no count property

- **TcxButtonEdit** (8 instances) and **TcxDBButtonEdit** (4 instances): each
  streams up to 4 independent single glyphs, `Properties.Buttons[0..3].Glyph.Data`
  -- these are 4 SEPARATE single-glyph properties on one component, not one
  strip with a count. No `NumGlyphs`-style property applies. `formats svg:8` /
  `svg:4` (confirmed SVG and decoded as of Task 10; previously unresolved). No
  G-rule needs an N here; each `Buttons[i].Glyph` is its own `single`.

## C. Inferred strip, no declared count property (open question)

- **TcxGridDBColumn** (2 instances, `Properties.Glyph.Data`, both from the same
  grid): `n_distribution ?:2` (no count property at all), `inferred_distribution
  6:2` (96x16 -> 6 x 16x16 cells), `formats bmp:2`. A checkbox-style column glyph
  conventionally holds 6 states (3 check states x 2 enabled states). **Open:**
  no property carries this count in the `.dfm`; whether the target reads a
  fixed `6` or a different property needs the DevExpress source, which is not
  in either index this session (`TcxGridDBColumn` not found in `Micronite2027.sqlite`
  or the abc5 scratch library). Do not write a G-rule for this class until that
  is resolved.
- **Corpus (M2022, 2026-09-17, glyph-vacuum):** the same open question, on a
  much larger sample -- 28 instances (not 2), `n_distribution ?:28`,
  `inferred_distribution 6:26;2:1;1:1` (26 of 28 confirm the 6-cell strip; one
  `Properties.Buttons[0/1].Glyph.Data` pair on `MEStats.dfm`'s
  `cxGrid1DBTableView1DBColumn1` decodes as 2 separate 32x16/16x16 single-button
  glyphs, `kind = container`, not the same shape as the `Properties.Glyph.Data`
  strip), `formats bmp:28`, `distinct_payloads 4`, `runtime_refs` empty
  (`TcxGridDBColumn` not found in `m2022-components.sqlite` or the abc5 scratch
  library either -- `proptree --qname TcxGridDBColumn --db <both>` returns
  `class not found` on both DBs passed this session, so there is still no
  source to read a count property from). **Same open question, still open:**
  no DevExpress source is in scope on this box to confirm whether the target
  reads a fixed `6` or a property. Notably, 3 of the 6-cell payloads across
  this run's `TcxGridDBColumn`, `TdxDBGridCheckColumn`, `TRzCheckList` and
  `TRzRadioGroup` rows share the IDENTICAL `payload_sha`
  (`20de6362cd769f0d2bc7de0d3989e2f39f4f3bddfbbc543770b733d6d41704a9`) despite
  belonging to four unrelated component classes across three different vendors
  -- consistent with (but not proof of) a shared "6-state checkbox" default
  bitmap resource. See the M2022 corpus block below for the sibling classes.

## D. Container / list sources (not glyphs themselves)

- **TImageList** (8 instances, `Bitmap`), **TcxImageList** (30 instances,
  `Bitmap` + `ImageInfo[0..5].Image.Data`), **TcxImageCollectionItem** (4
  instances, `Picture.Data`): these hold MANY images as one component (`kind =
  container` in instances.tsv), not a per-control glyph strip. They are
  candidate glyph SOURCES referenced by index from elsewhere (a button's
  `ImageIndex`), which is a different linking shape than `G[I/N]`. See the
  grammar-spec finding (b): `runtime_refs` could not be checked this session
  (none of the three resolve against either `--db` passed), so whether they
  actually appear as glyph sources in `.pas` is still open.
- **Re-measured after Task 10:** `TcxImageList` now `formats svg:24;?:6` --
  most of its `ImageInfo[i].Image.Data` items are individual SVG glyphs and
  decode; 6 items (likely the container's own `Bitmap`, a multi-image strip in
  a format this decoder does not parse as one image) stay unresolved. `TImageList`
  (`?:8`) and `TcxImageCollectionItem` (`?:4`) are UNCHANGED by Task 10's fix --
  neither is SVG nor the length-prefixed bare-bitmap shape, so what their
  binary actually is remains an open question, not a decode-gap this task
  covers.

## E. Single-glyph DevExpress bar/ribbon/misc controls, no count property

`TcxHintStyleController` (1, `HintStyle.Icon.Data`, ico:1), `TcxImage` (6,
`Picture.Data`, still unresolved format -- see the open note below), `TcxMRUEdit`
(2, `Properties.ButtonGlyph.Data`, `svg:2`), `TdxBar` (4, `Glyph.Data`,
`svg:4`), `TdxBarButton` (337, `Glyph.Data`/`LargeGlyph.Data`, `formats
bmp:47;jpg:4;png:2;svg:284` -- by far the largest single class in the corpus),
`TdxBarDBNavButton` (328, `Glyph.Data`, `bmp:10;svg:318`), `TdxBarEdit` (1,
`svg:1`), `TdxBarImageCombo` (5, `bmp:4;svg:1`), `TdxBarLargeButton` (77,
`Glyph.Data`/`HotGlyph.Data`/`LargeGlyph.Data`, `bmp:2;svg:75`),
`TdxBarLookupCombo` (3, `bmp:3`), `TdxBarManager` (2, `HelpButtonGlyph.Data`,
`bmp:2`), `TdxBarSubItem` (4, `Glyph.Data`/`LargeGlyph.Data`, `svg:4`),
`TdxLayoutImageItem` (2, `Image.Data`, `svg:2`), `TdxPDFViewer` (3, three
`OptionsNavigationPane.*.Glyph.Data` properties, `svg:3`), `TdxRibbon` (12,
`ApplicationButton.Glyph.Data`/`BackgroundImage.Data`, `svg:12`),
`TdxScreenTip` (4, `Description.Glyph.Data`, `svg:4`), `TOvcNumberEdit` (3,
`ButtonGlyph.Data`, `bmp:3`), `TRzMenuButton` (2, `Glyph.Data`, `bmp:2`).

None of these declare a count property; every instance is `kind = single` or
`kind = strip` purely from inferred geometry (width/height), never from a
declared N. **The "unresolved format" gap for most of the list above was the
SVG-glyph gap**, FIXED in Task 10 (commit `2343c0bc`) -- confirmed by
hand-decoding two representative payloads (`TcxButton.OptionsImage.Glyph.Data`
in `CMMGetDataMultiplyer.dfm` and `TdxBarButton.Glyph.Data` in `Blueprint4 -
Copy.dfm`): both begin `3C3F786D6C2076657273696F6E...` = `<?xml version=...`,
i.e. a `TdxSmartGlyph` SVG document, not a raster image at all, and both now
report `format svg`. `TOvcNumberEdit`/`TRzMenuButton` were the OTHER gap
(the length-prefixed bare `TBitmap`, see section A.2) and now report `format
bmp`. **Still open:** `TcxImage.Picture.Data` (6 instances) remains
unresolved after both fixes -- it is neither SVG text nor the length-prefixed
bare-bitmap shape, so its actual wire format is still unknown; do not assume
it is SVG without checking the raw bytes.

## F. Form icons -- single ICO, no count property (39 classes, one section)

Every remaining class in classes.tsv whose only graphic property is
`Icon.Data` is a plain VCL form icon: `TDefectListDlg`, `TdlgSetupDefaults`,
`TfrmBlueprint4`, `TfrmCADFNotes`, `TfrmCMMGetDataMultiplier`,
`TfrmCompGroupSetup2`, `TfrmCompRulesImport`, `TfrmConfirmorCancel`,
`TfrmControlPlan2`, `TfrmDataChannels`, `TfrmDefaultForm3`,
`TfrmDefaultTolerance`, `TfrmDefineSerialNumbers`, `TfrmDrawingPages`,
`TfrmEditMRU`, `TfrmEnterPassword`, `TfrmEwrkSlct`, `TfrmGageport2`,
`TfrmGridLayout`, `TfrmImportCADFile`, `TfrmImportPDFFile`, `TfrmJobList`,
`TfrmMAIN`, `TfrmMENotes`, `TfrmMEPDOESampling`, `TfrmMETemplateSetup`,
`TfrmSelectData`, `TfrmSmallBatch100FinalPlanSetup`, `TfrmSPCTplEdit`,
`TfrmTakeJob`, `TfrmTrpsSlct`, `TfrmUIConnect`, `TfrmVarNames`,
`TfrmWaitingToComplete`, `TfrmZ19OSelect`, `TGageBoxTestDlg`, `TVarInspDlg`,
`TZ14slctFrm`, `TZ19slctFrm`.

- **Image property:** `Icon: TIcon` (streams as `Icon.Data`, wrapper `TIcon`,
  `format ico`).
- **N:** none. `count_prop`/`agree`/`inferred_n` all empty in instances.tsv
  (`width`/`height` are 0 -- `SniffImageFormat`/`ParseStreamedGraphic` fill
  geometry for BMP only, per its own doc comment; ICO gets no width/height).
- **Corpus:** 1-3 instances each, `formats ico:N`, `distinct_payloads 1` in
  every case (each form's own icon is a single distinct payload). No G-rule
  applies -- these are `kind = single`, one glyph, nothing to split.

## H. NOT GLYPHS -- harvested false positives (do not write a G-rule)

The vacuum harvests every `dnkBinary` .dfm property regardless of name (by
design -- see `HarvestObject`'s own comment, "harvests every dnkBinary"). These
four classes' only binary properties are NOT images; they decode to nothing
recognisable and have `width=height=0`, confirmed by reading the raw bytes:

- **TOvcDbSimpleField, TOvcSimpleField, TOvcTCSimpleField** (Orpheus numeric
  fields; 2, 18, 16 instances respectively): `RangeHigh`/`RangeLow` are 10-byte
  `Extended`/`Currency` bounds streamed as a binary block, not images. One pair
  of `TOvcSimpleField.RangeLow` instances used to sniff as `format = emf` --
  this was a **false-positive magic-byte collision**: the payload is only 10
  bytes and a real EMF signature needs ~40 bytes plus the `" EMF"` marker, so
  the old `SniffImageFormat` EMF check (bare `01 00 00 00` at offset 0) was
  under-specified. **Fixed in Task 10** (commit `2343c0bc`): the EMF check now
  requires the actual ENHMETAHEADER `" EMF"` signature 40 bytes into the
  header, and the re-measured corpus shows all three classes reporting
  `formats ?:N` -- no `emf` false positive anywhere in the run.
- **TQuery** (3 instances): `Data` is the query's own binary blob (parameter
  set or similar), 1374-1962 bytes, not an image.
- **TcxTreeList** (4 instances): `Data` is the tree's saved layout/state blob,
  485-587 bytes, not an image.
- **TdxComponentPrinter** (2 instances): `PreviewOptions.PreviewBoundsRect` is
  a 16-byte `TRect` (4 x Int32), not an image.

---

## Gallery review (step 2, no browser opened per instructions)

**Re-measured after Task 10:** `agree` is `Y` for **25** of 1016 rows (was 23
before Task 10's decode fixes) and `N` for **zero** rows in this corpus (991
rows have no `agree` value at all -- either no count property or no inferred N
to compare against). The 25 `Y` rows are the 20 `TabcToggleBtn` instances
(declared 4, inferred 4), 3 of the 36 `TcxButton` instances (declared 2,
inferred 2), and 2 of the 3 `TBitBtn` instances (declared 2, inferred 2 --
newly comparable now that the length-prefixed bare bitmap decodes; the third
`TBitBtn` instance, `Panel3.BitBtn2`, decodes to 36x19, not evenly divisible by
its `NumGlyphs = 2`, so it stays without an `inferred_n`/`agree` value rather
than manufacturing a wrong one). **There is still no class in this run with
`agree = N`**, so there is nothing to report for "what the separators show for
every class with agree = N" -- the corpus contains zero declared/inferred
disagreements. (Before the dotted-count fix, `TcxButton` would have shown as
all-`?`/no-agree rather than a real disagreement, since its count property was
never being read at all -- not the same thing as a genuine `N`.)

---

## M2022 corpus (2026-09-17)

The owner named `C:\Projects\M2022` as the legacy tree the conversion will
extract from (Task 11). No manifest section covers M2022 on this box, so a
scratch library index of `Component\` was built first:

```
& $exe index C:\Projects\M2022\Component --db C:\TEMP\claude\vacuum-m2022\m2022-components.sqlite
```
-- `Files: 5, Symbols: 118, Refs: 305, 0.28s` (the folder holds only 3 `.pas` +
2 `.dpk`; the bulk of M2022's component classes are DevExpress/Raize
third-party controls, not project-owned sources, so this index resolves almost
nothing -- see `class_unit`/`runtime_refs` below).

```
& $exe glyph-vacuum --root C:\Projects\M2022 --out C:\TEMP\claude\vacuum-m2022 --db C:\TEMP\claude\vacuum-m2022\m2022-components.sqlite --db C:\TEMP\claude\vacuum-orm3\abc5-lib.sqlite
```
-- `glyph-vacuum: dfm=223 graphics=2721 distinct=673 skipped=0 ->
C:\TEMP\claude\vacuum-m2022`. `skipped.tsv` has a header row and zero data
rows (nothing skipped). Exit 0. 208 distinct component classes in
`classes.tsv`. Across all 2721 rows: `format` resolves (non-blank) for 1969
(72%); `agree = Y` for 75 rows; `agree = N` for **zero** rows -- same "no
declared/inferred disagreement anywhere" result as ORM3.

**No `CountPropNames` gap found this run.** Step 3 of the task brief calls for
adding a new count-property name only when a class shows strip geometry with
an empty `count_prop` AND its `proptree` shows an integer property that
plainly means glyph count. Every M2022 class below with strip geometry and no
`count_prop` (`TcxGridDBColumn`, `TdxDBGridCheckColumn`, `TRzCheckList`,
`TRzDBRadioGroup`, `TRzRadioGroup`, `TRzTrackBar`) returns `class not found`
from `proptree --qname <Class> --db C:\TEMP\claude\vacuum-m2022\m2022-components.sqlite --db C:\TEMP\claude\vacuum-orm3\abc5-lib.sqlite`
against BOTH DBs passed this session -- none of DevExpress's `cxGrid`/`dxDBGrid`
or Raize's `Rz*` sources are in scope on this box, so there is no property to
read a name from. This is a scope gap, not a decode gap: nothing here indicates
`CountPropNames` (`NumGlyphs`, `GlyphCount`, `NumStates`, `ImageCount`) is
missing an entry -- it is that the classes needing one are not indexed. No
`.pas`/guard change made this session.

### Per-class table (every class with a strip or a declared count property)

| class | count_prop | n_distribution | inferred_distribution | formats | instances | runtime_refs |
|---|---|---|---|---|---|---|
| `TabcToggleBtn` | `NumGlyphs` | `4:20` | `4:20` | `bmp:20` | 20 | 16 |
| `TBitBtn` | `NumGlyphs` | `2:10;?:6` | `2:9;1:6;?:1` | `bmp:16` | 16 | (empty) |
| `TcxButton` | `OptionsImage.NumGlyphs` | `4:8;2:14;?:57` | `4:8;2:14;1:3;?:54` | `bmp:27;svg:52` | 79 | (empty) |
| `TRzBitBtn` | `NumGlyphs` | `4:20;?:1` | `4:20;1:1` | `bmp:21` | 21 | (empty) |
| `TRzToolbarButton` | `NumGlyphs` | `2:4` | `2:4` | `bmp:4` | 4 | (empty) |
| `TcxGridDBColumn` | (none) | `?:28` | `6:26;2:1;1:1` | `bmp:28` | 28 | (empty) |
| `TdxDBGridCheckColumn` | (none) | `?:2` | `6:2` | `bmp:2` | 2 | (empty) |
| `TRzCheckList` | (none) | `?:1` | `6:1` | `bmp:1` | 1 | (empty) |
| `TRzDBRadioGroup` | (none) | `?:1` | `6:1` | `bmp:1` | 1 | (empty) |
| `TRzRadioGroup` | (none) | `?:4` | `6:4` | `bmp:4` | 4 | (empty) |
| `TRzTrackBar` | (none) | `?:3` | `6:3` | `bmp:3` | 3 | (empty) |

`disagreements = 0` for every row above (no `class_unit`/`runtime_refs` value
resolves for any class in this table except `TabcToggleBtn`, which is only
found because `abc5-lib.sqlite` was passed as the second `--db`). The first
five rows are already covered above (sections A.1-A.3); the remaining six are
new to this doc and get their own sections below.

### M2022.1 TRzBitBtn (Raize Components, `RzBtnEdt`/`RzButton`-family)

- **Image property:** `Glyph: TBitmap` (streams as `Glyph.Data`, same
  length-prefixed bare-bitmap shape as `TBitBtn` -- see section A.2 -- since
  `Glyph` is `TBitmap`-typed).
- **N:** `count_props NumGlyphs`, a bare (non-dotted) name already in
  `CountPropNames`; resolves for every instance that streams it.
- **Slots:** **open.** Raize's `RzButton.pas`/`RzBtnEdt.pas` source is not in
  either index passed this session (`proptree --qname TRzBitBtn --db <both>`
  -> `class not found`), so the per-slot meaning cannot be read from source.
  The declared/inferred agreement (`4:20`, `agree = Y` on all 20 -- see
  `C:\Projects\M2022\MEStats.dfm:btnCPR` etc., 52x13 decoding to 4 x 13x13
  cells) is consistent with the same normal/disabled/down/stay-down convention
  as VCL `TBitBtn`/`TNumGlyphs = 1..4`, but that is an inference from the
  numbers, not a confirmed read of Raize's source -- do not write a G-rule
  slot mapping from this note alone.
- **Corpus (M2022, 2026-09-17):** 21 instances, `count_props NumGlyphs`,
  `n_distribution 4:20;?:1`, `inferred_distribution 4:20;1:1`, `disagreements
  0`, `formats bmp:21`, `distinct_payloads 2`. 20 instances are on
  `C:\Projects\M2022\MEStats.dfm` (all share one 2762-byte, 52x13 payload); the
  1 outlier (`C:\Projects\M2022\ProcParameters4.dfm:btnSaveOperationSets`)
  doesn't stream `NumGlyphs` at all and decodes to a single 16x16 glyph
  (`kind = single`).

### M2022.2 TRzToolbarButton (Raize Components)

- **Image property:** `Glyph: TBitmap` (streams as `Glyph.Data`, length-prefixed
  bare bitmap).
- **N:** `count_props NumGlyphs`, bare name, already in `CountPropNames`.
- **Slots:** **open** (Raize source not indexed this session -- same gap as
  M2022.1). 36x18 decoding to 2 x 18x18 cells for all 4 instances, declared
  `NumGlyphs = 2`, `agree = Y` on all 4 -- consistent with a simple
  up/down(pressed) pair, unconfirmed by source.
- **Corpus (M2022, 2026-09-17):** 4 instances, all on
  `C:\Projects\M2022\ControlPlanningPresets.dfm` (`btnNewSet`, `btnDeleteSet`,
  `btnPreviousSet`, `btnNextSet`), `count_props NumGlyphs`, `n_distribution
  2:4`, `inferred_distribution 2:4`, `disagreements 0`, `formats bmp:4`,
  `distinct_payloads 4` (each button has its own distinct glyph).

### M2022.3 TdxDBGridCheckColumn (DevExpress `cxDBGrid` predecessor / dxDBGrid)

- **Image property:** `Glyph: TBitmap` (streams as `Glyph.Data`).
- **N:** none declared. `inferred_distribution 6:2` (96x16 -> 6 x 16x16
  cells) on both instances.
- **Slots:** **open** -- no count property in the `.dfm` and
  `proptree --qname TdxDBGridCheckColumn --db <both DBs>` returns `class not
  found` (DevExpress `dxDBGrid` source not in scope on this box). Same
  checkbox-strip convention question as `TcxGridDBColumn` (section C).
- **Corpus (M2022, 2026-09-17):** 2 instances, both from
  `C:\Projects\M2022\Backups\MAIN_X1.dfm` (`dxDBGrid1QFlagOFF`,
  `dxDBGrid1TFlagOff`), identical 4666-byte payload
  (`sha 20de6362cd769f0d2bc7de0d3989e2f39f4f3bddfbbc543770b733d6d41704a9`),
  `formats bmp:2`, `distinct_payloads 1`. This exact payload SHA is shared with
  one `TcxGridDBColumn` instance pair (`MAIN_X1.dfm`), one `TRzRadioGroup`
  instance, and the `TRzCheckList` instance below -- see the shared-payload
  note in section C.

### M2022.4 TRzCheckList (Raize Components)

- **Image property:** `CustomGlyphs: TBitmap` (streams as `CustomGlyphs.Data`).
- **N:** none declared. `inferred_distribution 6:1` (96x16 -> 6 x 16x16 cells).
- **Slots:** **open** (`class not found` in both DBs this session).
- **Corpus (M2022, 2026-09-17):** 1 instance,
  `C:\Projects\M2022\FirstSampleReport.dfm:RzCheckList1`, 4666-byte payload,
  `sha 20de6362cd769f0d2bc7de0d3989e2f39f4f3bddfbbc543770b733d6d41704a9` --
  the SAME sha as `TdxDBGridCheckColumn` above and one `TRzRadioGroup` instance
  below, despite `TRzCheckList` and `TdxDBGridCheckColumn`/`TRzRadioGroup`
  being unrelated classes from two different vendors. `formats bmp:1`.

### M2022.5 TRzDBRadioGroup (Raize Components)

- **Image property:** `CustomGlyphs: TBitmap` (streams as `CustomGlyphs.Data`).
- **N:** none declared. `inferred_distribution 6:1`.
- **Slots:** **open** (`class not found` in both DBs this session).
- **Corpus (M2022, 2026-09-17):** 1 instance,
  `C:\Projects\M2022\ControlPlan.dfm:EdtbyPpk`, a DISTINCT 4666-byte payload
  (`sha 2557e578450137ed82314e371c5ecaecebcda3f3650e8b24dcb02e54c2a29fd2`) --
  same size and 96x16/6-cell geometry as the shared-sha family above, but not
  byte-identical to it. `formats bmp:1`.

### M2022.6 TRzRadioGroup (Raize Components)

- **Image property:** `CustomGlyphs: TBitmap` (streams as `CustomGlyphs.Data`).
- **N:** none declared. `inferred_distribution 6:4` on all 4 instances.
- **Slots:** **open** (`class not found` in both DBs this session).
- **Corpus (M2022, 2026-09-17):** 4 instances, all on
  `C:\Projects\M2022\ControlPlan.dfm` (`RzRadioGroup1`, `RzRadioGroup2`,
  `RzRadioGroup3`) and
  `C:\Projects\M2022\SmallBatch100Final.dfm:rbtControlMode`, all 4 share the
  same 4666-byte payload as `TdxDBGridCheckColumn`/`TRzCheckList`
  (`sha 20de6362cd769f0d2bc7de0d3989e2f39f4f3bddfbbc543770b733d6d41704a9`).
  `formats bmp:4`, `distinct_payloads 1`.

### M2022.7 TRzTrackBar (Raize Components)

- **Image property:** `CustomThumb: TBitmap` (streams as `CustomThumb.Data` --
  a slider thumb bitmap, not a button glyph, but harvested by the same
  `dnkBinary` sweep and worth recording since it shows the identical 6-cell
  strip shape).
- **N:** none declared. `inferred_distribution 6:3` on all 3 instances.
- **Slots:** **open** (`class not found` in both DBs this session). Unlike the
  four classes above, this payload is NOT byte-identical to the shared-sha
  family -- distinct `sha
  1137396f34c1766a9a144363cec11d6c6a875573446280c686defeeae1ac9846`, same size
  (4666 bytes) and geometry (96x16) by coincidence or by shared authoring
  convention, not because it is literally the same resource.
- **Corpus (M2022, 2026-09-17):** 3 instances, all on
  `C:\Projects\M2022\BonusMC.dfm` (`sldTP`, `sldTPB`, `sldTPB2`),
  `distinct_payloads 1`, `formats bmp:3`.

**Summary of the open questions this run adds:** six classes
(`TcxGridDBColumn`, `TdxDBGridCheckColumn`, `TRzCheckList`, `TRzDBRadioGroup`,
`TRzRadioGroup`, `TRzTrackBar`) show a 6-cell 16x16 strip with no declared
count property, and none of their declaring units are in scope on this box
(neither DevExpress's nor Raize's source ships in either `--db` passed this
session). Four of the six share one byte-identical payload across three
vendors' classes, which is evidence of a shared default resource, not evidence
of what the runtime reads as its count. Do not write a `G[...]` rule against
any of these six until a DevExpress/Raize source index resolves the question.
