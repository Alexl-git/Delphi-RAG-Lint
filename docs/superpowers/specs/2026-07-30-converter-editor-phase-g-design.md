# Converter editor -- Phase G design

Spec. WHAT, not HOW; the plan is the companion document. Written 2026-07-30.

Six independent deliverables. Each section is self-contained and could be split into
its own spec later; they share one document because they share one implementation
window and one review.

## Standing constraints (apply to every section)

- **NOT published.** Nothing goes to GitHub until the converter engine and this editor
  are complete, match each other, and have both been run against several real project
  forms. `main` stays local and ahead of `origin`. This is a deliberate decision, not
  an oversight.
- Delphi 13 (Studio 37.0). `.pas`/`.dfm` strict 7-bit ASCII, CRLF.
- DocInsight spec-comments on every public declaration; a failing test before the
  implementation. The doc-comment and the test must agree.
- The editor is `src\tools\convrules-editor`, built by
  `build\_build_convrules_editor_local.bat`, tested by `ConvRulesModelTests.dpr`.
  Pure units carry the logic so it is testable without VCL; forms stay thin.
- **Deploy the editor and `drag-lint.exe` as a PAIR** (see BACKLOG-editor-features.md).
- Build from `main`, never from a feature branch.

---

## G1 -- Theme (follow the IDE, else Light/Dark)

**Why.** The editor is the only tool in this workflow that ignores the IDE's theme.

**What.** A `View > Theme` menu with **Follow IDE** (default), **Light**, **Dark**,
persisted in `HKCU\Software\DragLint\ConvRulesEditor`. The IDE's own setting is read
from `HKCU\Software\Embarcadero\BDS\<ver>\Theme`, value `Theme` (observed values
include `Dark`; `Enabled` gates whether theming is on at all). `<ver>` is discovered by
enumerating the `BDS` subkeys and taking the highest, never hard-coded.

New pure unit `ConvRules.Theme.pas`: theme-name -> mode mapping and the derived Examine
row colour. No VCL, no registry, no I/O in the pure part -- the form passes values in.

**The real work is the grid.** `FGrid.DefaultDrawing` is `False` and `GridDrawCell` hand
-paints every cell, so a VCL style does NOT reach it. Its five colours
(`clWindow`, `clBtnFace`, `clHighlight`, `clWindowText`, `clHighlightText`) must go
through `StyleServices.GetSystemColor`, and the hard-coded Examine green `$00D8F5D8`
must be derived from the active window colour instead.

**Acceptance criteria**

- THE editor SHALL apply a VCL style at startup.
- WHERE the preference is Follow IDE THE editor SHALL select the dark style WHEN the
  IDE `Theme` value is `Dark`.
- IF the IDE theme key is absent or unreadable THEN the editor SHALL fall back to the
  light style.
- THE Examine row highlight SHALL remain distinguishable from the unmarked row
  background under every offered style.
- WHILE a grid cell is selected THE grid SHALL paint the style's highlight colour
  rather than the Examine green.
- THE chosen preference SHALL survive a restart.

---

## G2 -- Toolbar

**Why.** `ConvRules.MainForm` creates **22** `TButton`s today and G4 adds more. Build
this BEFORE G4 so new buttons land in their final home once.

**What.** A top-aligned toolbar hosting the actions currently scattered across the form.
Grouped by function (file/working set, mapping, examine, unit rules), with the existing
hints preserved. Buttons that act on a selection stay disabled until it exists -- today
several are always enabled and report an error only when pressed.

Purely a relocation: no action changes behaviour, and every existing keyboard path and
handler keeps working.

**Acceptance criteria**

- THE toolbar SHALL expose every action currently reachable from a main-form button.
- WHEN an action requires a selection THE toolbar SHALL disable it until one exists.
- THE relocation SHALL NOT change any action's behaviour.
- THE toolbar SHALL remain usable at the minimum supported window width.

---

## G3 -- Go to definition (+ enum members)

**Why.** Choosing a target for `Style: TabcButtonStyle` requires knowing what that type
IS. Today that means leaving the editor.

**What.** Right-click a grid cell or pool row -> "Go to definition of `<Type>`", enabled
only when `TypeOfCell` yields a type. The engine resolves it
(`drag-lint query --name <T> --json` -> file + line) and the editor asks the running IDE
to open it over the existing named pipe `\\.\pipe\drag-lint-open-source`.

The client is **vendored** from the graph repo (`DragLint.Graph.OpenSourceClient.pas`)
into the editor under its own name, with a header comment naming the origin and the
contract doc. Rationale: the wire contract is frozen and documented; a search path into
a sibling checkout would make the build depend on an absolute path that CI lacks.

**When the resolved symbol is an enumeration, list its members.** That is the
information actually wanted, and G4 consumes it.

**Acceptance criteria**

- WHEN the user invokes Go to definition on a cell with a known type THE editor SHALL
  resolve that type to a file and line via the engine.
- WHERE the IDE pipe is unavailable THE editor SHALL display the resolved file and line
  and copy it to the clipboard.
- IF the type does not resolve THEN the editor SHALL report it and change nothing.
- WHERE the resolved symbol is an enumeration THE editor SHALL list its members.
- THE resolution SHALL NOT block the UI beyond `ENGINE_TIMEOUT_MS`.

---

## G4 -- Mapping library: conditional enum -> property rules

**Why.** A `#link` maps one From leaf to one To leaf through a cast. Real conversions
also need "this enum VALUE means these several target properties take these values" --
and that mapping must be defined once and reused across a vendor's whole control family.

**Scope: EDITOR ONLY.** The engine cannot apply these rules yet. See G6.

### DSL

Named, globally reusable, one node per line (no nesting -- the model is flat and stays
flat). The declaration narrows the mapping to a specific source enum and target class(es),
so it validates once on its own terms instead of per applying block:

```
#mapping XYZButtonStyle from XYZ.TXYZButtonStyle to cxButtons.TcxButton, cxButtons.TcxBigButton
#mapping XYZButtonStyle #when Style = stOK     -> Default = True, ModalResult = mrOk
#mapping XYZButtonStyle #when Style = stCancel -> Cancel  = True, ModalResult = mrCancel
#mapping XYZButtonStyle #else                  -> ModalResult = mrNone

#convert XYZ.TXYZToggleButton -> cxButtons.TcxButton
  #apply XYZButtonStyle
#convert XYZ.TXYZFunnyButton  -> cxButtons.TcxButton
  #apply XYZButtonStyle
```

`#apply`, NOT `#use` -- `#use` already means "add a unit to the uses clause"
(`rkUse`/`rkUseSwap`/`rkUnuse`). Target paths may be multi-level (`A.B.C = V`); the path
model already supports that. Values are entered as strings.

Mappings live in any file of the working set; `ConvRules.WorkingSet` already folds a set
with order as precedence, so the convention is a shared library file placed first.

### Editor

A dedicated mapping editor: left, every member of the source enum (from G3's lookup);
right, one or more `ToPath = Value` assignments per member, added and removed freely.
Validation where it is cheap and honest: the To path must exist and be writable in the
To tree (the editor already has that check), and an enum literal is checked against the
target's members when the target type resolves. Otherwise the value is accepted as typed
-- the editor warns, it does not block.

In the mapping grid a conditional row renders as `<conditional: N cases>`; Auto-Match
skips such rows.

**Acceptance criteria**

- THE `#mapping` declaration SHALL name one source enum type and one or more target
  classes.
- WHERE a `#apply` names a mapping THE rules SHALL behave as if that mapping's `#when`
  lines were written in the block.
- IF a `#apply` names an undefined mapping THEN validation SHALL reject it.
- IF an applying block's To type is not among the mapping's declared targets THEN
  validation SHALL reject that block, naming both the mapping and the block.
- WHEN a `#when` names a From path THE editor SHALL treat that From leaf as assigned.
- IF a target path is absent from the To tree or is not writable THEN the editor SHALL
  report it.
- IF a literal is not a member of the target enum, and that enum resolved, THEN the
  editor SHALL warn.
- IF some source enum members have neither a `#when` nor an `#else` THEN the editor
  SHALL warn, not error.
- THE round-trip SHALL preserve an unedited `#mapping` line byte-for-byte.
- THE same mapping SHALL be applicable to any number of blocks without redefinition.

**Deliberately excluded** (recorded, not forgotten): conditions other than equality;
conditions reading more than one From property; enum -> enum casting (see G6).

---

## G5 -- Examine fills the unit-rule FROM list

**Why.** Unit conversion already works -- `#useswap Old -> New1[, New2 ...]` exists in
both parsers and has a Unit Rules tab with authoring and derive/check. What is missing is
discovery: the user must know which units the examined forms actually use.

**What.** Extend the Examine scan to harvest `uses`-clause unit names from the selected
`.pas` files, and prefill the Unit Rules FROM column with them. The user deletes the ones
that need no conversion and fills in the TO side, which may be several units for one
source unit.

This is INDEPENDENT of the unit-add that a `#convert` performs for the To type's
declaring unit. Both may name the same unit; neither owns the other.

**Acceptance criteria**

- WHEN Examine runs over a set of `.pas` files THE editor SHALL list the distinct units
  named in their `uses` clauses.
- THE harvested list SHALL cover both the interface and implementation `uses` clauses.
- THE user SHALL be able to remove a harvested unit from the list.
- THE user SHALL be able to map one source unit to two or more replacement units.
- THE harvested list SHALL NOT alter units added by a `#convert`.
- WHERE a unit already has a rule THE editor SHALL NOT duplicate it.

---

## G6 -- Deferred, recorded so nobody files them as bugs

1. **The engine cannot apply `#mapping`.** G4 authors and validates; `convert-apply`
   will ignore these rules until the engine gains them. The engine has its own parser
   (`DRagLint.Convert.Rules.pas`) and applies `#default` at `DfmReemit.pas:700`.
   Conditional application is genuinely new: it must read EACH instance's own source
   value from the `.dfm` and select the matching case. Unconditional `#default` is the
   same for every instance; this is not.
2. **`enum <Name> ... end` in `.castlib` is unimplemented.** `rbkEnum` exists only in
   the block splitter (`ConvRules.BlockFile.pas:48`), so curation can move such a block
   as opaque text. `ConvRules.CastLib.pas:120` parses `cast` and nothing else, and the
   shipped `casts.castlib` contains zero enum blocks. Enum -> enum casting does not
   exist.
3. **The engine never reads `.castlib` at all** -- no reference anywhere outside the
   editor, and its rules parser does not even capture the `: CastName` suffix on
   `#link`. `ConvRules.CastLib.pas`'s header claim that "the ENGINE convert-apply
   consumes" the realization hints is a doc contract the code does not deliver. Correct
   the comment or build the consumer; do not leave it asserting both.
4. **No castlib field editor.** `CurationForm` handles `.castlib` at block level only.
5. **The grid search boxes have no tests**, though `GridRowMatchesFilter` was made pure
   and forward-declared for exactly that.

---

## G7 -- Borrow the ReFind BDE->FireDAC corpus

**Why.** Our DSL is a reFind superset. Embarcadero ships the migration rule files and
complete before/after demo projects; we should not invent test material we already own.

**Source** (RAD Studio 37.0 samples, also present for 23.0):
`C:\Users\Public\Documents\Embarcadero\Studio\37.0\Samples\Object Pascal\Database\FireDAC\Tool\reFind\`

- `BDE2FDMigration\FireDAC_Migrate_BDE.txt` -- the BDE rules.
- `AD2FDMigration\FireDAC_Rename_Units.txt` -- 9 KB of unit renames, directly useful to
  G5's `#useswap` work.
- `ADO2FDMigration\`, `DBX2FDMigration\`, `IBX2FDMigration\` -- same shape, other stacks.
- `BDE2FDMigration\Demo\` -- the complete BDE **mastapp** project (`DataMod`, `EDOrders`,
  `Main`, ...) with real `.pas`/`.dfm`, plus `migrate.bat` showing the reference
  invocation.

**The adaptation is smaller than it sounds.** `FireDAC_Migrate_BDE.txt` already uses
`#unuse`, `#remove`, `#remove DFM:` and `#migrate X -> Y, <unit>` -- every one is an
existing node kind in BOTH parsers. Plain `<pcre> -> <pcre>` lines map to `rnkPcre`.

**Acceptance criteria**

- THE editor SHALL load `FireDAC_Migrate_BDE.txt` without producing `rnkUnknown` for any
  line that uses a directive the DSL claims to support.
- THE round-trip SHALL preserve the borrowed files byte-for-byte when nothing is edited.
- THE test suite SHALL include at least one borrowed rule file as a fixture.
- THE test suite SHALL use at least one `Demo` form as a real-world scan fixture.
- WHERE a borrowed line uses a construct the DSL does not support THE editor SHALL keep
  it verbatim rather than dropping it.

**Licensing:** these are Embarcadero sample files shipped with the product. Because
nothing here is published (see standing constraints), vendoring them into the test
corpus is an internal-use decision only. Revisit before any public release.

---

## G8 -- Documentation deliverable (after the editor lands)

Two audiences, written once the editor exists so they describe what IS:

1. **A design message for the drag-lint engine team** -- the complete DSL definition
   (every directive, its grammar, its semantics) and the converter requirements,
   including the per-instance evaluation G6.1 needs.
2. **A human manual** -- definitions and worked examples: what a conversion is, what a
   cast is, what a mapping is, and how the working set composes.
