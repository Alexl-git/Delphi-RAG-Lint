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
  declared-default fallback), `inferred_distribution 2:3;1:1;?:32`,
  `disagreements 0`, `distinct_payloads 15`; `class_unit`/`runtime_refs` both
  empty (class not indexed).
- **Corpus (re-measured after Task 10, commit `2343c0bc`):** `formats
  bmp:5;svg:31` -- the 31 instances that used to report an unresolved format
  are now confirmed and decoded as SVG (`TdxSmartGlyph` streams raw XML text,
  no preamble). `width`/`height` stay 0 for the SVG rows by design (an SVG
  glyph is not a raster strip; geometry is not inferred from vector text), so
  `agree`/`inferred_n` are unaffected -- still 3 `Y` rows, all from the `bmp`
  side.

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
