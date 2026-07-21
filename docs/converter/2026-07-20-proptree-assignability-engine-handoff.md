# Engine handoff: proptree assignability (writability + visibility + concrete type)

**From:** converter-editor work (branch `feat/converter-editor`, worktree
`C:\Projects\Delphi-RAG-lint-converter`).
**To:** engine team (working `main`, `C:\Projects\Delphi-RAG-lint`).
**Date:** 2026-07-20. **Status:** design / not started.
**Why engine owns this:** the ConvRulesEditor cannot derive assignability from the
index -- it must come from the `proptree` verb / the index. The converter branch
deliberately does NOT touch the parser / index schema / proptree / CLI so the two
work streams don't collide in the same files.

---

## 1. Problem

The editor maps a source (From) property to a target (To) property; `convert-apply`
then generates assignment code of the form `dst.<ToPath> := <cast>(src.<FromPath>)`.
Today the To-side "pool" of candidate targets includes leaves that are **not valid
assignment targets**, so the user can build rules that cannot compile or are
semantically wrong. Three failure classes:

1. **Read-only targets** -- e.g. `.Handle`, many `.Count`. Generated code
   `x.Handle := ...` fails to compile (`E2129 Cannot assign to a read-only property`).
2. **Non-published / internal deep leaves** -- the deep OWNED DevExpress internals
   (`LookAndFeel` / `Painter` / `ViewInfo`, ~4539 leaves on `TcxButton`) are noise:
   not part of the convertible published surface a DFM migration cares about.
3. **Polymorphic `Properties` cross-type mismatch** -- many `Tcx*` controls expose
   `Properties`, but its concrete type is control-specific
   (`TcxCheckBoxProperties` vs `TcxButtonEditProperties` vs `TcxTextEditProperties`).
   A `TcxCheckBox`-specific `Properties.*` leaf must not be offered as a target on a
   `TcxButton` (different concrete `Properties`).

## 2. Evidence (measured against `C:\Projects\.drag-lint\library-Win64.sqlite` via `drag-lint.exe query --json`)

| Signal | Present in index today? | Detail |
|---|---|---|
| **read/write accessors** | **NO** | A property Symbol's `signature` is TYPE-ONLY. Across 841 `Caption` rows and every `Handle` row: **zero** `read`/`write` tokens. Examples: `Handle` -> `"signature": "HWND"` / `"THandle"` / `""`; `Caption` -> `": string"`, `": TCaption"`, `""`. |
| **visibility** | **YES** | Property rows carry `modifiers`. `Visible`: **905 published / 669 public / 37 protected / 180 empty**. `Handle` (TabcBDEFilterObject) -> `"modifiers": "protected"`. |
| **concrete polymorphic type** | **YES** | Each concrete control redeclares `Properties` with its specific type and the index captures it: `cxCheckBox.TcxCheckBox.Properties -> TcxCheckBoxProperties`; `cxButtonEdit.TcxButtonEdit.Properties -> TcxButtonEditProperties`; `cxTextEdit.TcxTextEdit.Properties -> TcxTextEditProperties`. Base classes carry base types (`TcxCustomTextEdit.Properties -> TcxCustomTextEditProperties`). |

**Net:** only **writability** is genuinely missing and needs a re-index. Visibility
and concrete-type are already indexed -- those two are proptree/CLI plumbing +
verification, **no re-index**.

## 3. Work items (ordered by cost -- do the cheap two first)

### R2. Visibility -> conversion-mode-aware target surface  (NO re-index; plumbing)
The valid target surface depends on the CONVERSION MODE the rule feeds:
- **DFM conversion** (`convert-apply` rewriting a `.dfm`): only **published**
  properties are streamable/assignable targets.
- **PAS conversion** (rewriting code, `obj.X := ...`): **published + public**
  properties AND public fields (see R4) are valid targets.

So visibility is not a single cut -- the editor picks the surface per mode, and must
be able to MARK a target as "PAS-only" (public, valid in code but not DFM-streamable).
- Data is in `modifiers`. Carry the property's effective visibility onto `TPropNode`
  and emit it (`published`/`public`/`protected`/`private`). Use the most-derived
  declaration's visibility (a published redeclaration of a protected/public ancestor
  is published) -- proptree already picks most-derived for `DeclaredIn`; extend to
  visibility.
- Add a proptree option `--min-visibility published|public`: the editor passes
  `published` for a DFM rule, `public` for a PAS rule. Emitting the raw per-leaf
  `visibility` too lets the editor tag public leaves "PAS-only" without a 2nd query.
- Verify empty-`modifiers` rows (redeclarations / inherited) resolve to an effective
  visibility via the ancestor walk rather than being dropped.

### R3. Polymorphic concrete type  (NO re-index; verify + likely small fix)
- The raw data is already correct (concrete redeclarations captured). Requirement:
  when `BuildPropTree` enumerates a specific class (`TcxCheckBox`), the `Properties`
  node must resolve to the MOST-DERIVED concrete type (`TcxCheckBoxProperties`) and
  recurse into THAT, not the base `TcxCustomEditProperties`.
- `CollectProps` already dedups "most-derived declaration wins"; confirm the winning
  declaration's **type token** (not just `DeclaredIn`) is the one used. The concrete
  redeclaration's signature is non-empty (`TcxCheckBoxProperties`), so most-derived
  non-empty should win.
- Guard the empty-signature redeclaration case: if a most-derived redeclaration is
  visibility-only (empty signature), `ResolveInheritedType` must not collapse it to
  the base and lose covariance -- prefer the nearest **concrete** (own-class)
  non-empty signature.
- This makes the editor's existing leaf-type cast check (`IsCastable`) do the right
  thing automatically: cross-type `Properties.*` leaves won't castable-match. (The
  editor-side polish -- warn when From/To `Properties` concrete types differ -- is
  converter-team work, once proptree is correct.)

### R4. Include public FIELDS as targets (PAS conversion)  (proptree scope; re-index only if libraries don't index fields)
- `skField` IS a modeled kind (`'field'`), but `BuildPropTree`/`CollectProps` filter
  to property-kind, so fields are never emitted. For PAS conversion, PUBLIC fields
  (`obj.FThing := x`) are valid targets and must appear.
- Change: proptree includes `skField` members whose visibility is public (or
  published) when the surface is PAS, emitted as leaves with `member_kind='field'`.
- Fields are WRITABLE by nature (no accessor) -> `is_writable=true`, EXCEPT a typed
  class constant (`const X: T = ...;`), which is read-only.
- **VERIFY (engine):** confirm public fields are actually indexed for the LIBRARY DBs
  with visibility in `modifiers`. My probe `query find --kind field` returned empty --
  inconclusive (could be query semantics, or library field extraction is thin). If
  library field extraction is incomplete, capturing public fields joins the extract
  scope and needs a re-index -- fold into R1's pass.

### R1. Writability (read/write) -> the big one (EXTRACT + RE-INDEX)  [hide read-only]
- Today the extractor keeps only the type token; the `read`/`write` accessor clause
  is discarded. Capture it.
- **Recommended:** add a new symbol column `prop_access TEXT` with `ro` | `rw` | `wo`
  (read-only / read-write / write-only), populated during property extraction.
  (Alternative: retain the full accessor text in `signature`; rejected -- it breaks
  the current type-only assumption that many call sites rely on.)
- **Inheritance:** a bare redeclaration (`property Caption;`) inherits the ancestor's
  accessors -- resolve `prop_access` the same way type is resolved (own decl, else
  ancestor with a non-empty accessor clause). A redeclaration that adds `write`
  becomes `rw`.
- **Re-index:** all library DBs (`library-Win32/Win64`, Win64 ~1.8 GB) + project DBs.
  This is the expensive step -- assess whether a properties-only incremental pass is
  viable, else a full `drag-lint index --all` per the manifest.

## 4. Consumer contract: proptree JSON schema bump  (proptree/1 -> proptree/2, additive)

Per leaf, ADD (keep all proptree/1 fields):
- `is_writable` : bool  -- from R1; a valid TARGET requires `true` (hide read-only).
- `visibility`  : `"published"|"public"|"protected"|"private"|""` -- from R2 (editor
  maps published -> DFM+PAS, public -> PAS-only).
- `member_kind` : `"property"|"field"` -- from R4 (public fields are PAS-only targets).
- (`type` already present; R3 makes it the concrete per-class type.)

Bump `schema` to `proptree/2`. **Back-compat is load-bearing:** the editor's
`ParseProptreeJson` will read the new fields with safe defaults --
`is_writable` **defaults TRUE when absent** and `visibility` defaults `""` -- so an
editor run against an OLD exe / un-re-indexed DB degrades gracefully to today's
"show everything" behavior instead of hiding every target.

## 5. Editor-side consumption (converter team; here so the contract is unambiguous)
- A per-rule (or global) **conversion MODE: DFM | PAS** selects the target surface --
  DFM = published only; PAS = published + public (+ public fields).
- `ConvRules.Engine.TPropLeaf` gains `IsWritable: Boolean`, `Visibility: string`,
  `MemberKind: string`; `ParseProptreeJson` reads `is_writable` (default True),
  `visibility` (default ''), `member_kind` (default 'property').
- `ConvRules.MainForm.RefreshPool` excludes To leaves that are not `IsWritable`
  (hide read-only), excludes leaves below the mode's min-visibility, and **tags
  public leaves "PAS-only"** in the pool (so the user sees a target that won't land
  in a DFM).
- `DoAssign` guards: block + explain a non-writable target; warn when a PAS-only
  (public) target is assigned in a DFM rule.
- All gated so a proptree/1 response = current behavior (show everything).

## 6. Test plan (TDD, engine side)
- **Extract unit test:** a class with `property RO: Integer read FRO;`,
  `property RW: Integer read FRW write FRW;`, `property WO: Integer write FWO;`
  -> `prop_access` = `ro` / `rw` / `wo` respectively; a bare redeclaration inherits.
- **proptree writable fixture:** enumerate a control; `Handle` leaf -> `is_writable=false`,
  `Caption` leaf -> `true`.
- **proptree visibility:** `--min-visibility published` yields only published leaves
  (deep `LookAndFeel/Painter/ViewInfo` internals drop out); `--min-visibility public`
  additionally yields public leaves, each carrying `visibility="public"` so the
  editor can tag them PAS-only.
- **proptree fields (PAS):** with `--min-visibility public`, public fields appear as
  leaves with `member_kind="field"`, `is_writable=true`; with `--min-visibility
  published` they do NOT appear.
- **proptree polymorphic:** `TcxCheckBox.Properties` recurses into
  `TcxCheckBoxProperties` (asserts a checkbox-specific leaf present, a button-edit-
  specific leaf absent); `TcxButtonEdit.Properties` -> `TcxButtonEditProperties`.
- **Back-compat:** existing proptree/1 consumers unaffected; editor with old exe still works.

## 7. Files (engine, `C:\Projects\Delphi-RAG-lint`)
- Parser / extract: `src/parser/DRagLint.Parser.Delphi13.pas` (property_declaration ->
  capture accessors + confirm visibility capture).
- Schema / migration: `src/storage/DRagLint.Storage.SQLite.pas` (`prop_access` column).
- proptree: `src/report/DRagLint.Convert.PropTree.pas` (`TPropNode` fields; visibility
  + writability resolution; concrete-type verification; `--min-visibility` option).
- CLI: `src/cli/DRagLint.CLI.pas` (`DoPropTree` JSON: `is_writable`, `visibility`;
  `--min-visibility` flag; `schema` -> `proptree/2`).
- Re-index: manifest build (`drag-lint index --all`).

## 8. Open questions for the engine team
1. `prop_access` column vs retaining full accessor text in `signature`? (recommend column)
2. ~~`--min-visibility` default?~~ **RESOLVED by requester:** surface is mode-
   dependent -- DFM = published; PAS = published + public + public fields. Public
   targets are tagged "PAS-only" in the editor. (Library FIELD indexing coverage
   still to verify -- see R4.)
3. Incremental (properties-only) vs full re-index for R1 (+ fields if R4 needs it)?
4. Write-only (`wo`) leaves: valid as TARGETS, invalid as SOURCES -- confirm the
   editor should treat direction accordingly.
5. Sequencing: ship R2 + R3 (no re-index) first for immediate value, then R4/R1?
6. Typed-class-constant fields (`const X: T = ...`) -- mark `is_writable=false`?

---
*Converter-side status + this handoff are cross-referenced in
`docs/converter/STATUS.md` (item 2, BLOCKED).*
