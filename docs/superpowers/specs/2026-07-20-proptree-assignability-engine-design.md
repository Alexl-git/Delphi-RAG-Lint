# Design: proptree assignability engine (writability + visibility + concrete type + fields)

- Date: 2026-07-20
- Status: Approved (design confirmed by user; ready for implementation plan)
- Source handoff: `docs/lint/2026-07-20-proptree-assignability-engine-handoff.md`
  (and `C:\Projects\Delphi-RAG-lint-converter\docs\converter\...` in the editor repo)
- Engine repo: `C:\Projects\Delphi-RAG-lint` (main). Editor consumer: converter repo (parallel team).

## Motivation

The ConvRulesEditor maps a source (From) property to a target (To) property;
`convert-apply` then generates `dst.<ToPath> := <cast>(src.<FromPath>)`. Today the
To-side candidate pool includes leaves that are NOT valid assignment targets, so a
user (or `convert-scaffold`) can build rules that cannot compile or are wrong.
Three failure classes:

1. **Read-only targets** (`.Handle`, many `.Count`) -> `x.Handle := ...` fails
   `E2129 Cannot assign to a read-only property`.
2. **Non-published / internal deep leaves** -- DevExpress owned internals
   (`LookAndFeel`/`Painter`/`ViewInfo`, ~4539 leaves on `TcxButton`) are noise, not
   part of the convertible published surface a DFM migration cares about.
3. **Polymorphic `Properties` cross-type mismatch** -- `Tcx*` controls expose
   `Properties`, but its concrete type is control-specific (`TcxCheckBoxProperties`
   vs `TcxButtonEditProperties` vs `TcxTextEditProperties`). A `TcxCheckBox`-specific
   `Properties.*` leaf must NEVER be offered as a target on a different class.

The editor cannot derive assignability from the index itself -- it must come from
the `proptree` verb. This is engine work.

## Evidence (verified this session via the index, `library-Win64.sqlite`)

| Signal | In index today? | Detail (measured) |
|---|---|---|
| **read/write accessors (writability)** | **NO** | property `signature` is TYPE-ONLY: `': TCaption'`, `'string'`, `'THandle'`, `''` -- zero `read`/`write` tokens across 841 `Caption` + 521 `Handle` rows. -> needs re-index (R1). |
| **visibility** | **YES** | every property row carries `modifiers`: `published`/`public`/`protected`. `Visible` = published/public/protected; `Handle` = protected/public. -> no re-index (R2). |
| **concrete polymorphic type** | **YES** | `cxCheckBox.TcxCheckBox.Properties -> TcxCheckBoxProperties`; `cxButtonEdit.TcxButtonEdit.Properties -> TcxButtonEditProperties`; `cxTextEdit.TcxTextEdit.Properties -> TcxTextEditProperties`. -> no re-index (R3). |
| **library public fields** | **YES** | 157,665 field symbols in library-Win64, **71,047 public** with `modifiers` + signature (e.g. `TFIBBase.OnDatabaseConnecting :: TNotifyEvent [public]`). -> R4 needs NO re-index (resolves the handoff's open R4 question). |

**Net:** only **writability (R1)** genuinely needs a re-index. Visibility (R2),
concrete-type (R3), and public fields (R4) are proptree/CLI plumbing + verification.

## Scope (user decision)

**All four work items (R1+R2+R3+R4) in ONE increment, including the re-index.**
The `proptree/2` schema ships complete; the editor codes against the final shape
once.

## Design per work item

### R2 -- visibility -> conversion-mode-aware target surface (no re-index)
- Carry the property's **effective** visibility (most-derived declaration wins; a
  published redeclaration of a protected/public ancestor is published) onto
  `TPropNode`. proptree already picks most-derived for `DeclaredIn`; extend the same
  resolution to visibility, including the ancestor walk for empty-`modifiers`
  (bare-redeclaration / inherited) rows so they resolve to an effective visibility
  rather than being dropped.
- Add proptree option `--min-visibility published|public` (default: emit all, so
  proptree/1 callers are unaffected). Editor passes `published` for a DFM rule,
  `public` for a PAS rule. Emit the raw per-leaf `visibility` too so the editor can
  tag public leaves "PAS-only" without a second query.

### R3 -- polymorphic concrete type, CLASS-ACCURATE (no re-index)
- **Requirement (user-emphasized):** the target surface for a class must be
  class-accurate -- `TcxButton`'s pool must NEVER contain `TcxCheckBoxProperties.*`
  leaves. When `BuildPropTree` enumerates a specific class, its `Properties` node
  must resolve to that class's MOST-DERIVED concrete type and recurse into THAT, not
  a base type. Because each concrete control redeclares `Properties` with its
  specific type (data already correct), the fix is resolution logic:
  - `CollectProps` already dedups "most-derived declaration wins"; ensure the winning
    declaration's **type token** (not just `DeclaredIn`) is used.
  - Guard the empty-signature redeclaration case: a most-derived visibility-only
    (empty signature) redeclaration must NOT collapse to the base and lose
    covariance -- prefer the nearest **concrete** (own-class) non-empty signature.
    This composes with the existing unknown-type bridge/down-propagation
    (`DRagLint.Convert.PropTree.pas`).
- **Consequence:** cross-type `Properties.*` leaves never appear on the wrong class,
  so the editor's `IsCastable` and `convert-scaffold`'s auto-`#link` "figure out the
  matching automatically" correctly -- no separate matching algorithm needed.

### R4 -- public fields as targets (no re-index; verified indexed)
- `skField` is modeled but `BuildPropTree`/`CollectProps` filter to property-kind.
  Include `skField` members whose effective visibility is public (or published),
  emitted as leaves with `member_kind="field"`.
- Fields are writable by nature -> `is_writable=true`, EXCEPT a typed class constant
  (`const X: T = ...`) which is read-only (`is_writable=false`).
- Fields are PAS-only targets (not DFM-streamable): appear under `--min-visibility
  public`, NOT under `--min-visibility published` (published fields are rare; still
  emit their real visibility).

### R1 -- writability (EXTRACT + RE-INDEX) [hide read-only]
- Capture the `read`/`write` accessor clause during property extraction (today only
  the type token is kept).
- **New symbol column `prop_access TEXT`** = `ro` | `rw` | `wo` (read-only /
  read-write / write-only), populated during extraction. (Rejected alternative:
  retain full accessor text in `signature` -- breaks the type-only assumption many
  call sites rely on.)
- **Inheritance:** a bare redeclaration (`property Caption;`) inherits the ancestor's
  accessors -- resolve `prop_access` the same way `type` is resolved (own decl, else
  nearest ancestor with a non-empty accessor clause). A redeclaration adding `write`
  becomes `rw`.
- **Re-index:** libraries (`library-Win32/Win64`, Win64 ~1.8 GB) + project DBs.
  Investigate a properties-only incremental pass; PLAN FOR a full `drag-lint index
  --all` per the manifest as the safe path.
- `is_writable` per leaf = `prop_access <> 'ro'` (rw/wo writable; ro not). Write-only
  (`wo`) is a valid TARGET, invalid as a SOURCE -- the emitted field lets the editor
  handle direction; proptree just reports it.

## Consumer contract: `proptree/1 -> proptree/2` (additive)

Per leaf, ADD (keep all proptree/1 fields):
- `is_writable` : bool -- a valid TARGET requires `true` (editor hides read-only).
- `visibility`  : `"published"|"public"|"protected"|"private"|""`.
- `member_kind` : `"property"|"field"`.
- `type` : already present; R3 makes it the concrete per-class type.

Bump `schema` to `proptree/2`. **Back-compat is load-bearing:** consumers read the
new fields with safe defaults -- `is_writable` **defaults TRUE when absent**,
`visibility` defaults `""`, `member_kind` defaults `"property"` -- so an editor run
against an OLD exe / un-re-indexed DB degrades to today's "show everything" instead
of hiding every target.

## convert-scaffold consumption (engine, beyond the handoff)

`convert-scaffold` auto-`#link`s From->To by leaf-name + compatible type. Extend it
to restrict auto-matched TARGETS to `is_writable=true` and (for a DFM scaffold)
`visibility=published`, using the concrete per-class type from R3 for the
type-compatibility test. So generated rule drafts are assignability-correct by
construction -- serving the user's "figure out the matching automatically" intent on
the engine side, not only in the editor. A `--surface dfm|pas` (or reuse
`--min-visibility`) selects the target surface for the scaffold.

## Engine files

- Parser / extract: `src/parser/DRagLint.Parser.Delphi13.pas` (property_declaration ->
  capture `read`/`write` accessors; confirm field visibility capture).
- Schema / migration: `src/storage/DRagLint.Storage.SQLite.pas` (`prop_access` column
  + a schema version bump + migration).
- proptree: `src/report/DRagLint.Convert.PropTree.pas` (`TPropNode` gains
  visibility/is_writable/member_kind; visibility + writability resolution; concrete-
  type verification; field inclusion; `--min-visibility` honoring).
- CLI: `src/cli/DRagLint.CLI.pas` (`DoPropTree` JSON: `is_writable`, `visibility`,
  `member_kind`; `--min-visibility` flag; `schema` -> `proptree/2`). Also
  `convert-scaffold` consumption.
- Re-index: manifest build (`drag-lint index --all`).

## Testing (TDD, engine side)

- **Extract unit test:** a class with `property RO: Integer read FRO;`,
  `property RW: Integer read FRW write FRW;`, `property WO: Integer write FWO;` ->
  `prop_access` = `ro`/`rw`/`wo`; a bare redeclaration inherits the ancestor's.
- **proptree writable fixture:** `Handle` leaf -> `is_writable=false`, `Caption` ->
  `true`.
- **proptree visibility:** `--min-visibility published` yields only published leaves
  (deep `LookAndFeel/Painter/ViewInfo` drop out); `--min-visibility public`
  additionally yields public leaves, each carrying `visibility="public"`.
- **proptree fields (PAS):** with `--min-visibility public`, public fields appear as
  `member_kind="field"`, `is_writable=true`; with `published` they do NOT appear.
- **proptree polymorphic (class-accurate):** `TcxCheckBox.Properties` recurses into
  `TcxCheckBoxProperties` (a checkbox-specific leaf present, a button-edit-specific
  leaf ABSENT); `TcxButtonEdit.Properties` -> `TcxButtonEditProperties`. Assert a
  wrong-class concrete leaf never appears.
- **convert-scaffold:** a scaffold to a target with a read-only leaf does NOT emit an
  auto-`#link` to it; a DFM scaffold excludes public-only targets.
- **Back-compat:** existing proptree/1 consumers unaffected; editor with old exe
  still works (defaults applied).

## Open questions -- resolved

1. `prop_access` column vs signature text -> **column** (don't break type-only).
2. `--min-visibility` default -> mode-dependent (DFM=published; PAS=published+public+
   public fields); default emit-all for back-compat.
3. Incremental vs full re-index for R1 -> investigate properties-only; plan full.
4. Write-only (`wo`): valid TARGET, invalid SOURCE -> emit; editor handles direction.
5. Sequencing -> user chose ALL FOUR in one increment (not staged).
6. Typed-class-constant fields -> `is_writable=false`.

## Implementation ordering (for the plan)

Do the no-re-index parts first so they're testable without the expensive re-index,
then R1 last:
1. Schema/migration (`prop_access` column, nullable) + version bump.
2. proptree `TPropNode` fields + R2 visibility resolution + `--min-visibility` + CLI
   JSON + `schema` bump (is_writable defaults true until R1).
3. R3 concrete-type class-accuracy (verify + guard) with the polymorphic test.
4. R4 field inclusion.
5. convert-scaffold consumption of the new fields.
6. R1 extract (`read`/`write` -> `prop_access`) + inheritance resolution +
   `is_writable` wired from `prop_access`, THEN the library+project re-index.
7. Full-corpus verification after re-index (spot-check `.Handle` hidden, `.Caption`
   kept, cross-type Properties absent).
