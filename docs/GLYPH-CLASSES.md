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

**Read this before trusting a row below:** the vacuum harvests every binary
(`dnkBinary`) property in a `.dfm`, not just ones named Glyph/Picture/Icon/Image.
Several classes in the corpus have NO image property at all; their binary blob
is something else entirely that happens to stream as a hex block. Those are
called out explicitly in section H so nobody writes a glyph rule against them.

Also see the **Vacuum findings (2026-09-17)** block at the top of the grammar
spec for the two systemic decode gaps this run exposed (SVG glyphs, and a
4-byte-length-prefixed bare bitmap form) -- they affect nearly every class below
that shows a blank `format`/`wrapper`.

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

- **Image property:** `Glyph: TBitmap` (streams as `Glyph.Data`, no wrapper --
  see the decode-gap note below).
- **N:** `NumGlyphs: TNumGlyphs = 1..4` (VCL standard: normal/disabled/down/stay-down).
- **Corpus:** 3 instances (all from `C:\Projects\DB\ORM3\BACKUP\EWrkSLCT.dfm`,
  a backup copy under the walked root, not `CLIENT\`), `count_value = 2` on
  all 3, `count_props NumGlyphs`, `formats ?:3` (unrecognised), `distinct_payloads 3`.
- **Open -- decode gap (real, not a guess):** all 3 payloads fail to decode:
  `wrapper`, `format`, `width`, `height`, `bpp` all come back empty despite
  plausible byte counts (2002, 2002, 502). Read the raw hex for `btn_Cancel`
  in `BACKUP\EWrkSLCT.dfm`: it starts `CE070000 424D CE070000 ...` -- a
  little-endian **Int32 byte count (`0x000007CE` = 1998)**, immediately
  followed by a real `BM...` bitmap whose own internal `bfSize` happens to
  equal the same 1998. This is a THIRD streaming form, distinct from both
  forms `DRagLint.Convert.GlyphStrip.ParseStreamedGraphic` currently knows
  (wrapped-with-classname for `TPicture`, and bare-with-magic-at-offset-0):
  a `TBitmap`-typed property (no class name needed, the static type already
  says `TBitmap`) streams `[Int32 size][raw bitmap bytes]`, so the `BM` magic
  sits at **offset 4**, not offset 0. The decoder's magic-byte fallback only
  checks offset 0, so it never finds it. See "Vacuum findings" (grammar spec)
  for the write-up; not fixed in this session (out of scope for Task 9).

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
- **Corpus (post-fix):** 36 instances, `count_props OptionsImage.NumGlyphs`,
  `n_distribution 2:3;?:33` (3 instances declare `OptionsImage.NumGlyphs = 2`;
  33 don't stream it at all -- and `count_default` is empty because `TcxButton`
  isn't in either index, so there is no declared-default fallback),
  `inferred_distribution 2:3;1:1;?:32`, `disagreements 0`, `formats bmp:5;?:31`,
  `distinct_payloads 15`. Most of the 31 unresolved-format instances are SVG
  glyphs (see grammar-spec findings) -- `class_unit`/`runtime_refs` both empty
  (class not indexed).

---

## B. Per-button single glyphs, no count property

- **TcxButtonEdit** (8 instances) and **TcxDBButtonEdit** (4 instances): each
  streams up to 4 independent single glyphs, `Properties.Buttons[0..3].Glyph.Data`
  -- these are 4 SEPARATE single-glyph properties on one component, not one
  strip with a count. No `NumGlyphs`-style property applies. `formats` all `?`
  (unresolved -- SVG, per the grammar-spec findings). No G-rule needs an N here;
  each `Buttons[i].Glyph` is its own `single`.

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

## E. Single-glyph DevExpress bar/ribbon/misc controls, no count property

`TcxHintStyleController` (1, `HintStyle.Icon.Data`, ico:1), `TcxImage` (6,
`Picture.Data`, all unresolved format), `TcxMRUEdit` (2,
`Properties.ButtonGlyph.Data`, unresolved), `TdxBar` (4, `Glyph.Data`,
unresolved), `TdxBarButton` (337, `Glyph.Data`/`LargeGlyph.Data`, `formats
bmp:47;jpg:4;png:2;?:284` -- by far the largest single class in the corpus),
`TdxBarDBNavButton` (328, `Glyph.Data`, `bmp:10;?:318`), `TdxBarEdit` (1,
unresolved), `TdxBarImageCombo` (5, `bmp:4;?:1`), `TdxBarLargeButton` (77,
`Glyph.Data`/`HotGlyph.Data`/`LargeGlyph.Data`, `bmp:2;?:75`),
`TdxBarLookupCombo` (3, `bmp:3`), `TdxBarManager` (2, `HelpButtonGlyph.Data`,
`bmp:2`), `TdxBarSubItem` (4, `Glyph.Data`/`LargeGlyph.Data`, unresolved),
`TdxLayoutImageItem` (2, `Image.Data`, unresolved), `TdxPDFViewer` (3, three
`OptionsNavigationPane.*.Glyph.Data` properties, unresolved), `TdxRibbon` (12,
`ApplicationButton.Glyph.Data`/`BackgroundImage.Data`, unresolved),
`TdxScreenTip` (4, `Description.Glyph.Data`, unresolved), `TOvcNumberEdit` (3,
`ButtonGlyph.Data`, unresolved), `TRzMenuButton` (2, `Glyph.Data`, unresolved).

None of these declare a count property; every instance is `kind = single` or
`kind = strip` purely from inferred geometry (width/height), never from a
declared N. **Every "unresolved format" above is very likely the SVG-glyph gap**
(see grammar-spec findings) -- confirmed by hand-decoding two representative
payloads (`TcxButton.OptionsImage.Glyph.Data` in `CMMGetDataMultiplyer.dfm` and
`TdxBarButton.Glyph.Data` in `Blueprint4 - Copy.dfm`): both begin
`3C3F786D6C2076657273696F6E...` = `<?xml version=...`, i.e. a `TdxSmartGlyph`
SVG document, not a raster image at all.

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
  of `TOvcSimpleField.RangeLow` instances sniffs as `format = emf` -- this is a
  **false-positive magic-byte collision**: the payload is only 10 bytes and an
  EMF signature needs ~40 bytes plus the `" EMF"` marker, so `SniffImageFormat`'s
  EMF check is under-specified (matches on too little of the header). See
  grammar-spec findings, item (c).
- **TQuery** (3 instances): `Data` is the query's own binary blob (parameter
  set or similar), 1374-1962 bytes, not an image.
- **TcxTreeList** (4 instances): `Data` is the tree's saved layout/state blob,
  485-587 bytes, not an image.
- **TdxComponentPrinter** (2 instances): `PreviewOptions.PreviewBoundsRect` is
  a 16-byte `TRect` (4 x Int32), not an image.

---

## Gallery review (step 2, no browser opened per instructions)

`agree` is `Y` for exactly 23 of 1016 rows and `N` for **zero** rows in this
corpus (993 rows have no `agree` value at all -- either no count property or no
inferred N to compare against). The 23 `Y` rows are the 20 `TabcToggleBtn`
instances (declared 4, inferred 4) plus 3 of the 36 `TcxButton` instances
(declared 2, inferred 2). **There is no class in this run with `agree = N`**,
so there is nothing to report for "what the separators show for every class
with agree = N" -- the corpus currently contains zero declared/inferred
disagreements once the dotted-count fix is applied. (Before the fix, `TcxButton`
would have shown as all-`?`/no-agree rather than a real disagreement, since its
count property was never being read at all -- not the same thing as a genuine
`N`.)
