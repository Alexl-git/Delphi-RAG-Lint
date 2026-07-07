# Enum-Helper Generator + first-class helper indexing -- design

**Date:** 2026-07-07
**Status:** DESIGN APPROVED (brainstorm complete). Next: writing-plans -> subagent-driven-development.
**Prior art / ground truth:**
- `docs/lint/DESIGN-enum-helper-generator.md` (pre-brainstorm scoping; superseded by this doc)
- `docs/lint/INVESTIGATION-enum-helper-pattern.md` (ORM3 MSCTYPES.PAS ground truth + testing plan)
- `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md` (addendum 2026-07-07:
  the structural-index wishlist this milestone starts delivering, item S1.1)

Sibling features to mirror: AutoDocument (`src/doc/`, `document --qname` verb, IDE "Document it"
menu), Extract Method / Rename (`src/refactor/`, `TTextEditApplier`).

---

## 1. Goal

Automate generation of the standard enum `record helper` that ORM3's `COMMON/MSCTYPES.PAS`
hand-writes ~45 times: the `ToByte`/`FromByte`/`ToInteger`/`FromInteger`/`ToString`/`FromString`
family. Entry points: a CLI verb and an IDE right-click ("Create helper class") on an enum member
or the enum type. Create-only-if-missing; never overwrite an existing helper.

This milestone ships THREE coupled deliverables:
- **(A)** the enum-helper generator (a Track-4 refactoring / code-gen action);
- **(B)** first-class HELPER indexing -- the indexer stores a `record helper for T` / `class helper
  for T` target as a resolved edge, so no consumer parses the heritage string (wishlist item S1.1);
- **(C)** an `enum-helper-separate-units` lint rule (ON by default) that flags a helper declared in a
  different unit than its target enum.

## 2. Non-goals / guards

- Do NOT overwrite an existing helper (create-only-if-missing; idempotent -- a 2nd run is a
  byte-identical no-op).
- Do NOT generate dummy `0..255` filler enum members. Padding an enum so every byte value maps to a
  member is the user's / TableTools' concern; the generator only ever references REAL named members.
- Do NOT fabricate strings. RTTI enum-member names are ground truth; the case-based ToString variant
  emits member-identifier literals; a `ToDescription` is only offered when a real `<Enum>Descriptions`
  array exists in the same unit.
- Generated Object Pascal MUST compile + round-trip -- the build+round-trip test (Section 9, case #8)
  is the acceptance gate, not text-matching.
- ANSI / CRLF / 7-bit ASCII output (project encoding rule) -- generated text uses no Unicode.

## 3. The one Byte-family template (decided in brainstorm)

**Key decision:** ALL enums are treated as Byte-based. There is ONE template family (Byte); no
ShortInt variant, no signed handling, no source-line ordinal reading. A negative ordinal (e.g.
`-1`) is simply the byte value `0xFF`; making that valid is the enum author's job (pad the enum),
not the generator's. This collapses the Byte-vs-ShortInt branch the investigation doc worried about.

**All `From*` converters use a `case` idiom** (NOT the clamp-to-low/high style seen in some
hand-written MSCTYPES helpers -- that style produced a real copy-paste bug, `TSpecNotationHelper`
referencing `TSpecType`'s low/high). The `case` maps each real named member; the `else` assigns the
FIRST declared member (= `low(TX)`; in MSCTYPES this is the `*_Undefined` sentinel). No range check
needed -- only legal values map.

### DECL (inserted immediately after the enum type declaration)
```pascal
T<Enum>Helper = record helper for T<Enum>
  public
    function ToByte: Byte;
    function ToInteger: Integer;
    function ToString: string;
    class function FromByte(const AValue: Byte): T<Enum>; static;
    class function FromInteger(const AValue: Integer): T<Enum>; static;
    class function FromString(const AValue: string): T<Enum>; static;
    // + function ToDescription: string;  ONLY if a <Enum>Descriptions array is detected
end;
```

### BODIES (inserted in the implementation section)
```pascal
{ T<Enum>Helper }

function T<Enum>Helper.ToByte: Byte;
begin
  Result := Ord(Self);
end;

function T<Enum>Helper.ToInteger: Integer;
begin
  Result := Ord(Self);
end;

class function T<Enum>Helper.FromByte(const AValue: Byte): T<Enum>;
begin
  case AValue of
    Ord(<Member0>): Result := <Member0>;
    Ord(<Member1>): Result := <Member1>;
    // ... one arm per real named member, in declaration order
  else
    Result := <FirstMember>;   // first declared member = low(T<Enum>)
  end;
end;

class function T<Enum>Helper.FromInteger(const AValue: Integer): T<Enum>;
begin
  case AValue of
    Ord(<Member0>): Result := <Member0>;
    // ... same case body as FromByte, typed Integer
  else
    Result := <FirstMember>;
  end;
end;

// ToString / FromString -- RTTI default (adds System.TypInfo to uses if absent):
function T<Enum>Helper.ToString: string;
begin
  Result := GetEnumName(TypeInfo(T<Enum>), Ord(Self));
end;

class function T<Enum>Helper.FromString(const AValue: string): T<Enum>;
begin
  Result := T<Enum>(GetEnumValue(TypeInfo(T<Enum>), AValue));
end;

// ToDescription -- ONLY when a `<Enum>Descriptions: array[...] of string` const exists:
function T<Enum>Helper.ToDescription: string;
begin
  Result := <Enum>Descriptions[Self];
end;
```

### Template options
- `--methods <list>` subsets the 6 (e.g. `--methods tobyte,frombyte`).
- `--tostring=rtti` (default) | `--tostring=case`. The `case` variant emits, per member,
  `Ord(member): Result := '<MemberIdentifier>';` in ToString and the inverse if-chain / case in
  FromString -- editable string literals, no `System.TypInfo` dependency.
- `ToDescription` is auto-included when the same-unit descriptions-array is detected; otherwise omitted.
- Note: `ToString` shadows `TObject.ToString`, but a record helper for an enum has no `TObject` in
  scope, so the name is safe and matches the user's requested set.

## 4. Architecture (approach A -- new refactor unit)

New unit **`src/refactor/DRagLint.Refactor.EnumHelper.pas`**, sibling to `DRagLint.Refactor.Rename`
and `...ExtractMethod`. Three-stage pipeline, emitting `TTextEdit`s consumed by the existing
`DRagLint.Refactor.TextEdit` applier. CLI verb and IDE menu both call into it.

```
CLI: create-enum-helper --qname TX          IDE: "Create helper class" (right-click)
                 |                                        |
                 +--------------------+-------------------+
                                      v
                    TEnumHelperRefactoring  (new unit)
        +-------------+----------------------+------------------+
        |   RESOLVE   |      GENERATE        |      PLACE       |
        | index ->    | one Byte template -> | 2 x TTextEdit    |
        | enum +      | helper source text   | (decl + bodies)  |
        | members +   | (real members only)  |                  |
        | helper?     |                      |                  |
        +-------------+----------------------+------------------+
                                      v
                          TTextEditApplier (existing)
```

### RESOLVE
- Input: `--qname TX` (CLI) OR the symbol under cursor (IDE). If the symbol is a `skEnumValue`, walk
  to its parent `skEnum`; if it's the `skEnum`, use directly. Both yield the same enum.
- Members: `FindAllChildSymbols(enumId)` filtered to `skEnumValue`, in declaration order. Index-only
  (names + order suffice; `Ord(member)` lets Delphi compute the literal -- no stored ordinal needed).
- Existing-helper guard: WHOLE-CODEBASE query via the new helper edge (deliverable B). Same-unit
  helper -> refuse ("helper already exists"); different-unit helper -> refuse + name the other unit
  (this pair also drives the lint rule, deliverable C).
- Descriptions-array detection: look for a same-unit `const <Enum>Descriptions: array[...] of string`
  (drives the optional `ToDescription`).

### GENERATE
- Build DECL + BODIES from the Byte template (Section 3) using the resolved member list. Deterministic,
  no LLM.

### PLACE (revised placement rule)
- **Decl edit:** insert the helper type decl immediately after the enum type declaration, same `type`
  section (the enum's decl span comes from the index; the exact insertion point is after the enum's
  `EndLine`/`EndCol`).
- **Bodies edit:** insert method bodies in the `implementation` section -- ALWAYS, populating an empty
  implementation section when necessary (right after the `implementation` keyword; or after existing
  routines when present). This keeps enum + helper together in ANY unit (including a previously
  interface-only unit) -- no forced migration to MSCTYPES.
- **Refuse ONLY** when the source has no `implementation` keyword at all (malformed/fragment). This is
  a safety guard, not a real workflow; a normal Delphi unit always has the keyword.
- Placement needs the `implementation`-keyword position. Sourced from deliverable B's section-anchor
  fact (item S1.2) if folded in this milestone; otherwise a bounded source scan over preprocessed
  (v0.92) text. Writing-plans decides which, on cost.

## 5. Deliverable B -- first-class helper indexing (schema bump 14 -> 15)

**Problem:** today a `record helper for T` is stored as `skRecord` with `T` buried in the `Heritage`
string (parser `DRagLint.Parser.Delphi13.pas:461`, `HeritageTextOf`). Consumers must string-parse
heritage to answer "does a helper for T exist / where". That is the exact fragility this milestone
removes.

**Change:** the indexer resolves a helper declaration's TARGET as an edge, mirroring `type_ancestors`.
Options for writing-plans to choose (cheaper wins):
- (a) a new `type_helpers(helper_symbol_id, target_name, target_symbol_id, target_file_id, helper_kind)`
  table + indexes on `helper_symbol_id` and `target_name`; OR
- (b) reuse `type_ancestors` with a discriminator marking the row as a helper-target edge.

Recommend (a) -- a helper-of relationship is semantically distinct from ancestry (a helper is not a
subtype), and a dedicated table keeps `type_ancestors` clean. `helper_kind` = `'record'|'class'`.

**Parser:** at the `skRecord`/`skClass` emit site (line 459-461), when the class/record node is a
helper (`... helper for X`), also emit a helper-target edge (target name = the `helper for`'s typeref).
The parser already reads this typeref today (it lands in heritage); this promotes it to a first-class edge.

**Queries exposed:** `helpers-of <T>` (does a helper exist? where?), `helper-target <THelper>`.
Consumed by the generator's guard and the lint rule -- NO heritage-string parsing anywhere.

**Migration + reindex:** SCHEMA_VERSION 14 -> 15 (`src/storage/DRagLint.Storage.Schema.pas:6`). Add
the migration retrofit (create the new table on an existing DB -- note the LATEST-13/v0.83.1 lesson:
new tables/columns must be created in the MIGRATION path, not only in `SCHEMA_DDL`, or pre-15 DBs die
on first query). Reindex the manifest DBs after the bump.

### (Optional this milestone) S1.2 section anchors
Store the line/col of `interface` / `implementation` / `initialization` / `finalization` keywords per
file as a queryable fact (`unit-anchors <file>`). The enum-helper PLACE stage needs the
`implementation` anchor regardless; if storing it costs little over computing it inline, fold it in.
Writing-plans decides.

## 6. Deliverable C -- `enum-helper-separate-units` lint rule (ON by default)

- **Fires when:** an enum `TX` has a `record helper for TX` (via the new helper edge) declared in a
  DIFFERENT unit than the enum's own unit.
- **Message:** "helper `TXHelper` (unit `<A>`) is separate from enum `TX` (unit `<B>`); consider
  co-locating."
- **Default state: ON** (diverges from the recent OFF-by-default convention for advisory rules --
  explicit user decision 2026-07-07).
- **RISK (must verify before release):** ON-by-default may surface findings on existing trees
  immediately. Sanity-check the false-positive count on this repo + ORM3 before release (as the
  AutoDocument milestone did with `missing-doc`); reserve the option to flip OFF if noisy. Record the
  observed count in the release checkpoint.
- Registered in the rule catalog + given a doc-comment; wired into both `DoLintAll` and `DoLintProject`
  paths (note the AutoDocument LATEST-19 lesson: a catalog-OFF rule can still fire at runtime through a
  DefDisabled gap -- ensure the default is honored in BOTH lint paths; add a regression test).

## 7. CLI verb

```
drag-lint create-enum-helper --qname <TEnum>
    [--apply]                 # write the edit (default: emit a TTextEdit preview)
    [--no-backup]             # standard companion to --apply
    [--json]                  # structured output for IDE / AI orchestration
    [--methods <list>]        # subset of tobyte,frombyte,tointeger,frominteger,tostring,fromstring
    [--tostring=rtti|case]    # default rtti
    [--db <path>]             # else manifest auto-select
```
- Mirrors AutoDocument's `document --qname`. Default = preview; `--apply` writes; `--json` for the IDE.
- Idempotent: helper exists -> no-op with a clear message (`action=exists` in JSON).
- Refuse cases (no impl keyword; helper exists) reported cleanly (stderr text + JSON status).

## 8. IDE menu

- "Create helper class" added to the Structure-tab / editor context menu in
  `DragLint.Plugin.StructureForm.pas`, modeled on AutoDocument's "Document it".
- **Enablement predicate:** the symbol under cursor is a `skEnum`, OR a `skEnumValue` whose parent is a
  `skEnum`, AND no helper edge exists for that enum (deliverable B query).
- On click: spawn the CLI verb via the shared `DragLintExe` resolver with `--apply`; reload the buffer
  (string-only ForceQueue reload, per the AutoFix/Extract-Method IDE pattern).
- IDE live smoke DEFERRED TO USER (as with every prior IDE feature -- source Approved + BPL built; user
  reopens RAD Studio to verify).

## 9. Testing

Suite `tests/refactor/run_enum_helper.ps1`, fixtures under `tests/refactor/fixtures/enumhelper/`
(model on the autodoc / refactor harnesses). Folds in the investigation doc's 10-case plan:

1. **simple.pas** -- `TColor = (clRed, clGreen, clBlue);` no explicit ordinals. Generated helper
   compiles + round-trips: `clRed.ToByte=0`, `TColor.FromByte(2)=clBlue`, `clGreen.ToString='clGreen'`,
   `TColor.FromString('clBlue')=clBlue`.
2. **explicit_ordinals.pas** -- `TSpec=(sp_Undefined=0, sp_Double=1, sp_Upper=2);` FromByte case maps
   Ord->member exactly; `else` = first member; ToInteger=Ord.
3. **negative_ordinal.pas** -- `TEST=(Elem1=-2, Elem2=0, Elem3);` per the one-Byte-template rule,
   FromByte/FromInteger case over real members; Elem1 falls to `else`; NO ShortInt variant emitted; no
   source ordinal read. (Asserts the collapsed-branch decision.)
4. **already_has_helper.pas** -- enum + existing `TXHelper record helper` in the SAME unit -> feature
   REFUSES ("helper already exists"), makes NO edit.
5. **doc_interleaved.pas** -- enum with `{$REGION}` / `///` between members -> member list parsed
   correctly (noise skipped via v0.92 preprocessor); helper members match the real enum members.
6. **idempotency** -- run twice: 2nd run is a byte-identical no-op (ties to case 4).
7. **descriptions_reuse.pas** -- enum + `const XDescriptions: array[TX] of string = (...)` -> a
   `ToDescription` is generated reusing that array (bonus path).
8. **round-trip build test (ACCEPTANCE GATE)** -- a fixture unit that USES the 6 generated methods +
   a DUnitX/console assert of the round-trips; MUST COMPILE. This is the real gate.
9. **placement** -- helper decl inserted immediately after the enum type decl; bodies in the
   implementation section. Includes an **interface-only-unit fixture** (empty implementation section)
   asserting the bodies populate it (revised rule) rather than refusing.
10. **CLI + IDE parity** -- the CLI verb and the IDE menu produce the SAME edit.

Plus:
- **helper-edge index tests** (deliverable B): parse a `record helper for TX`; assert a helper-target
  edge is stored; assert `helpers-of TX` finds it and a plain record with a `TX` field does NOT
  produce a false helper edge; assert migration from a v14 DB creates the table + a query succeeds.
- **separate-units rule tests** (deliverable C): enum + helper in different units -> rule fires with
  the right message; same unit -> no finding; rule ON by default in catalog AND at runtime (both lint
  paths); regression test for the DefDisabled-honored default.

Oracle: the MSCTYPES.PAS hand-written helpers (a `TSpecType`-mirroring fixture should generate a helper
structurally equivalent to `TSpecTypeHelper` -- method set + body logic, not exact whitespace).

## 10. Scope boundaries / follow-ups

- **In this milestone:** (A) generator + CLI + IDE, (B) first-class helper indexing (schema 15) + the
  `helpers-of` / `helper-target` queries [+ optional S1.2 section anchors], (C) separate-units lint rule.
- **Scheduled follow-up (its own milestone):** the broader "indexer awareness" brainstorm -- grep-
  elimination wishlist items S1.3 (uses-clause membership query), S2 (declaration-shape facts: explicit
  ordinals, const values, alias/set element targets), S3 (unit outline / file roster / stats overview).
  Captured in `docs/superpowers/specs/2026-06-29-grep-elimination-indexer-wishlist.md` (addendum
  2026-07-07). One deliberate schema bump, one reindex, when that milestone runs.

## 11. Key lessons carried in (from prior milestones)

- Migration retrofit: new tables/columns go in the MIGRATION path, not only `SCHEMA_DDL`
  (v0.83.1 hotfix lesson).
- OFF/ON-by-default must be honored in BOTH `DoLintAll` and `DoLintProject` (AutoDocument LATEST-19
  Critical: a catalog-OFF rule fired at runtime via a DefDisabled gap).
- Literal `{ }` inside a Pascal `{ }` comment breaks compilation; a real Delphi build is the gate, not
  self-lint (AutoFix Chunk 2 lesson).
- Reindex incrementally after a schema-changing build; kill any orphaned `drag-lint.exe` holding a DB
  lock before re-indexing.
