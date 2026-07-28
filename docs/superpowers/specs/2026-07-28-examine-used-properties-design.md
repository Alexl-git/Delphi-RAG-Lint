# Examine: mark the properties a conversion actually uses (spec F)

- Date: 2026-07-28
- Branch: `feat/converter-editor` (worktree `C:\Projects\Delphi-RAG-lint-converter`)
- Status: DRAFT -- awaiting user approval
- Follows: spec E (rule-book curation), implemented and merged.

## 1. Problem

A conversion's From class exposes far more properties than any real form uses.
`Abcbtn.TabcToggleBtn` returns **3905** proptree leaves; the actual `TabcToggleBtn` in
`ORM3\CLIENT\VARINSP.dfm` assigns **nine**: `Left`, `Top`, `Width`, `Height`, `GroupIndex`,
`Caption`, `Images`, `Layout`, `Picture.Data`.

So the mapping grid presents a haystack. The user has no way to tell which rows matter for
their codebase, and a property that is never assigned in a `.dfm` and never touched in a `.pas`
does not need a mapping at all. Mapping effort is being spent uniformly across rows whose real
importance is wildly uneven.

## 2. Scope

In scope:

- An `Examine...` command that takes a user-selected set of `.dfm` and/or `.pas` files.
- Determining which properties of the currently selected **From** class those files use.
- Colouring the matching From/To grid rows green.
- Reporting used properties that have no grid row.

Out of scope:

- Examining the **To** class. The question being answered is "which of my source properties
  must survive the conversion", which is a From-side question.
- Any engine change. This reads files directly; see section 4.
- Any change to the `.rules` file format. Examination results are transient view state, not
  persisted.

## 3. Decisions taken (user rulings, 2026-07-28)

1. **"Used" is the UNION of DFM and PAS, shown as ONE green.** A property is used if it is
   assigned in any selected `.dfm` OR referenced in any selected `.pas`. No distinction is drawn
   between the two in the colouring.
2. **PAS detection is a loose match: any `.<PropName>` occurrence counts**, regardless of which
   object it belongs to. The user chose this over instance-name-driven matching, accepting that
   another component's `.Caption` in the same file will mark `Caption` used. The gain is that
   `with btn do ...` blocks and typed local variables are caught, which precise matching misses.
3. **Used properties with no grid row are reported**, not silently dropped.

## 4. Architecture: read the files, do not ask the index

The scanner reads the selected files directly, in a new pure unit. Two reasons this is not an
engine feature:

- The project index contains **no DFM text at all** -- `query --text --source dfm` against
  `C:\Projects\DB\ORM3\drag-lint.sqlite` returns 0 matches for both `Caption` and `object`. An
  index-based answer is impossible today regardless of engine work.
- The user selects arbitrary files, which may not be in any index.

This follows the pure-core / thin-VCL split already used by `ConvRules.BlockFile`,
`ConvRules.BlockOps` and `ConvRules.WorkingSet`: the logic is headless and unit-tested against
inline fixtures; the form only picks files and paints cells.

### 4.1 `ConvRules.Usage.pas` (new, pure)

```
TUsageSet = record
  Names   : TArray<string>;   // normalised, de-duplicated, case-insensitive
  Missing : TArray<string>;   // used names with no counterpart in the From tree
  DfmCount: Integer;          // files scanned
  PasCount: Integer;
end;
```

Public surface:

- `function ScanDfmText(const AText, AFromClass: string): TArray<string>;`
- `function ScanPasText(const AText: string; const ACandidates: TArray<string>): TArray<string>;`
- `function MergeUsage(const AParts: TArray<TArray<string>>): TArray<string>;`
- `function IsRowUsed(const AFromPath: string; const AUsed: TArray<string>): Boolean;`
- `function CandidatesFor(const AFromPaths: TArray<string>): TArray<string>;` -- section 7
- `function ComputeUsage(const ADfmTexts, APasTexts: TArray<string>; const AFromClass: string; const AFromPaths: TArray<string>): TUsageSet;`

`ComputeUsage` is the single call the form makes: it runs `ScanDfmText` over each DFM text,
derives candidates from the From-tree paths, runs `ScanPasText` over each PAS text, merges, and
fills `Missing`/`DfmCount`/`PasCount`. The other five are exposed because each is independently
testable and `IsRowUsed` is called per cell during painting.

No file system, no VCL. The form reads the files and passes text in.

### 4.2 `ConvRules.MainForm.pas` (modified)

An `Examine...` button beside the new grid filter boxes; a multi-select `TOpenDialog`; the
scan; `FUsedProps: TArray<string>` held as view state; an `OnDrawCell` handler that paints a
green background for used rows; a `Clear` that empties `FUsedProps` and repaints.

## 5. DFM grammar

A depth-tracked line scan, not a full parser.

- A component block opens on a line whose first token is `object`, `inherited` or `inline` and
  which matches `<keyword> <Ident>: <ClassName>`. Depth increments.
- `end` at any depth closes the innermost block.
- A block whose `<ClassName>` equals the From class (case-insensitive) is a TARGET block.
- Inside a TARGET block, and only at its immediate level, a line of the form `<Name> = <value>`
  records a property assignment. `<Name>` may be dotted (`Picture.Data`).
- **Nested `object` blocks inside a target block are OTHER components, not properties.** Their
  assignments are not attributed to the From class. The scan still descends into them, because
  another instance of the From class may be nested there.
- **Binary data blocks are skipped.** `Picture.Data = {` opens a hex blob that continues until a
  line containing `}`. Its lines must not be parsed as assignments. The same applies to
  `<...>` collection items and `(...)` multi-line values: on an unterminated opener, skip to the
  matching terminator.

For a dotted assignment `A.B.C`, the scanner records BOTH `A.B.C` and `A` -- the root property is
genuinely used, and recording it lets a grid row for `A` go green even when only a sub-field was
set in the DFM.

## 6. PAS matching

For each candidate name (see 7), a case-insensitive search of the raw file text for a `.` then
the name, with the following character not being a letter, digit or underscore. Any hit marks
the name used.

Deliberately not excluded: comments, string literals, and other classes' members. This is the
loose match decision from section 3.2 and its cost is over-reporting, never under-reporting.

## 7. Candidates and row matching

Candidates are the distinct LAST segments of every From-tree leaf path, plus the distinct full
paths. `Font.Size` contributes `Size` and `Font.Size`.

A grid row is green when, case-insensitively, its From path is in the used set OR the From
path's last segment is in the used set.

`Missing` is every used name matching no From-tree leaf by either rule. With the From side of
the current conversion returning its full inherited surface, this list is expected to be empty
or near-empty; when it is not, it is direct evidence for the engine team, so it is shown rather
than dropped.

## 8. UI

- `Examine...` opens `TOpenDialog` with `ofAllowMultiSelect`, filter
  `Delphi form and source (*.dfm;*.pas)|*.dfm;*.pas|Form files (*.dfm)|*.dfm|Source (*.pas)|*.pas`.
- After the scan the status bar reads
  `Examined 3 file(s): 9 of 3905 From properties used.`
- Used rows are painted with a green background by `OnDrawCell`, leaving the selected-cell
  highlight intact so selection stays visible on a green row.
- The examined file list is retained for the session, so switching `#convert` blocks re-applies
  the same examination to the new block's rows without re-picking files.
- `Clear examination` empties the set and repaints.
- When `Missing` is non-empty, a modal report lists those names.

## 9. Error handling

An unreadable or malformed file is reported by name in the status bar and skipped; the remaining
files are still scanned. A DFM whose blocks never close is not an error -- the scan simply ends
at EOF with whatever it collected. No file is ever written: Examine is strictly read-only.

## 10. Acceptance criteria (EARS)

Each becomes exactly one test in `ConvRulesModelTests.dpr`.

1. WHEN a DFM contains an `object N: <FromClass>` block THE scanner SHALL record every
   `Name = value` assignment at that block's immediate level.
2. WHEN a DFM assigns a dotted property `A.B` THE scanner SHALL record both `A.B` and `A`.
3. WHEN a DFM property value is a `{ ... }` binary blob THE scanner SHALL NOT record any of the
   blob's lines as assignments.
4. WHERE a component block is nested inside a target block THE scanner SHALL NOT attribute that
   nested component's assignments to the From class.
5. WHERE a nested block is itself an instance of the From class THE scanner SHALL record its
   assignments.
6. WHEN a DFM contains no block of the From class THE scanner SHALL return an empty set.
7. WHEN a PAS file contains `.PropName` followed by a non-identifier character THE scanner SHALL
   mark `PropName` used.
8. IF a PAS file contains `.PropNameExtra` THEN the scanner SHALL NOT mark `PropName` used.
9. THE row test SHALL return True when the From path's last segment is used, and for the full
   dotted path.
10. THE merge SHALL de-duplicate case-insensitively across files.
11. THE scanner SHALL report as Missing every used name that matches no From-tree leaf.
12. WHILE no examination has been run THE grid SHALL paint no row green.

## 11. Testing

Headless tests against inline fixtures, matching how the curation units are tested. Criterion 1
is additionally tested against the real block from `ORM3\CLIENT\VARINSP.dfm` (an ABC5
`TabcToggleBtn` with `Picture.Data` hex), copied into the test as a fixture constant so the suite
does not depend on a path outside the repo. The `OnDrawCell` colouring is VCL and is verified by
a clean build plus manual check, consistent with the ruling recorded for the curation form.

## 12. Encoding

All `.pas` files strict 7-bit ASCII, CRLF. The scanner must tolerate reading `.dfm`/`.pas` files
in any encoding it is handed without raising; it operates on the text as read.

## 13. Known limitations, stated up front

- **Over-reporting by design.** Any `.Caption` in a scanned `.pas` marks `Caption` used, even if
  it belongs to a different component. Section 3.2.
- **Text DFMs only.** A binary `.dfm` will yield nothing; the scan reports zero matches rather
  than failing.
- **The To side is unaffected.** Green marks a From property that matters. Whether it can be
  mapped depends on the To pool, which is currently truncated for VCL/DevExpress targets --
  see `docs/INBOX-proptree-ancestor-climb-stops-early.md`.
