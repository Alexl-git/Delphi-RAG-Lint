# Enum-Helper pattern investigation (ORM3 MSCTYPES.PAS) + testing plan

**Date:** 2026-07-07. **Purpose:** ground-truth for the "Create helper class" enum-helper
generator feature (next drag-lint milestone). The user pointed at MSCLIST; the enum + helper
declarations actually live in the companion **`C:\Projects\DB\ORM3\COMMON\MSCTYPES.PAS`**
(MSCLIST *uses* them, e.g. `fFTRCLASS.ToByte`, `TCharClass.FromByte(...)`).

## The convention (verified from MSCTYPES.PAS)

An enum type and a `record helper` for it, declared adjacent in the `type` section:

```pascal
TSpecType = (
  SpecType_Undefined = 0,
  SpecType_Double = 1,
  SpecType_SingleUpper = 2,
  SpecType_SingleLower = 3);

TSpecTypeHelper = record helper for TSpecType
  public
    class function FromInteger(const AST: integer): TSpecType; static;
    class function FromByte(const AST: Byte)      : TSpecType; static;
    function ToDescription: string;
    function ToInteger: integer;
    function ToByte   : Byte;
end;
```

Helper naming: `T<Enum>Helper` for `T<Enum>` (e.g. `TSpecTypeHelper`, `TSpecNotationHelper`,
`TAcReButtonHelper`, `TCodeLetterHelper`, `TInspIDHelper`). ~45 enums in this one file, most
with a matching helper -- exactly the repetitive, mechanical work to automate.

### Implementation bodies (the exact shapes the generator must emit)

```pascal
class function TSpecTypeHelper.FromInteger(const AST: integer): TSpecType;
var BST: integer;
begin
  BST:= AST;
  if (BST < ord(low(TSpecType))) or (BST = 0) then BST:= ord(low(TSpecType))
  else if (BST > ord(high(TSpecType))) then BST:= ord(high(TSpecType));
  result:= TSpecType(BST);
end;

class function TSpecTypeHelper.FromByte(const AST: Byte): TSpecType;
begin
  case AST of
    ord(SpecType_Undefined  ): result:= SpecType_Undefined;
    ord(SpecType_Double     ): result:= SpecType_Double;
    ord(SpecType_SingleUpper): result:= SpecType_SingleUpper;
    ord(SpecType_SingleLower): result:= SpecType_SingleLower;
    else result:= SpecType_Undefined;   // first / *_Undefined member as the fallback
  end;
end;

function TSpecTypeHelper.ToInteger: integer; begin result:= ord(self); end;
function TSpecTypeHelper.ToByte   : Byte;    begin result:= ord(self); end;
function TSpecTypeHelper.ToDescription: string; begin result:= SpecTypeDescriptions[self]; end;
```

### What is mechanically derivable (from the enum member list alone)

- `ToInteger` / `ToByte` = `ord(self)` -- constant boilerplate.
- `FromInteger` = clamp to `[ord(low)..ord(high)]` (+ the observed `or (BST = 0)` guard when the
  first member is a `*_Undefined = 0`) then cast. NOTE: the clamp uses the ENUM's own low/high;
  the `= 0` special-case is a MSCTYPES idiom (undefined sentinel) -- make it a template option.
- `FromByte` = a `case` over `ord(<member>): result := <member>` for every member + an `else` to
  the fallback (the `*_Undefined`/first member).
- `ToString` / `FromString` (user asked for these; MSCTYPES uses `ToDescription` + a parallel
  `<Enum>Descriptions` const array instead): two viable generations --
  (a) RTTI: `ToString := GetEnumName(TypeInfo(TX), ord(self))`; `FromString := TX(GetEnumValue(TypeInfo(TX), s))` (member-identifier strings), OR
  (b) case-based like FromByte, mapping each member to a chosen display string (needs a source of
  the strings -- a comment, a `ToDescription` array, or a stripped-prefix member name).
  DECISION FOR THE SPEC: default to RTTI GetEnumName/GetEnumValue for ToString/FromString (no
  external string source needed), and OPTIONALLY detect + reuse an existing `<Enum>Descriptions`
  array for a ToDescription. The user's list (ToByte/FromByte/ToInteger/FromInteger/ToString/
  FromString) is the required set; ToDescription is a bonus when a descriptions array exists.

### Enum-declaration corner cases the parser/generator must handle (seen in MSCTYPES)

- Explicit ordinals, incl. NEGATIVE and gaps: `TEST = (Elem1 = -2, Elem2 = 0, Elem3, Elem4);`
  `TSpecType_Undefined = -1` (commented variant). FromByte over a Byte can't hold negatives ->
  the generator must WARN/skip FromByte (or use FromInteger only) when any member ordinal < 0 or > 255.
- `{$REGION 'Documentation'}` / `///` doc-comment blocks INTERLEAVED between members (TSpecType).
  The member-list parse must skip directive/comment noise (the preprocessor from v0.92 helps).
- Inline `// comment` after a member (`SpecType_Double = 1, // Bilateral`).
- Members with `ord(...)` expressions: `AcReButton = (AcDown = 65 {ord('A')}, ...)` (commented).
- Multi-line enum bodies with a member per line (TSpecType, TFtrType, TCharClass, ...).
- A `record helper` MAY ALREADY EXIST -> the feature must DETECT it and offer to
  create-only-if-missing (per the user: "create helper class (if it does not yet exist)").

## TESTING PLAN (do LATER -- when the feature is built)

Suite `tests/refactor/run_enum_helper.ps1` (model on the autodoc/refactor harnesses), fixtures
under `tests/refactor/fixtures/enumhelper/`:

1. **simple.pas** -- `TColor = (clRed, clGreen, clBlue);` no explicit ordinals. Assert the generated
   helper compiles + `FromByte`/`ToByte`/`FromInteger`/`ToInteger`/`ToString`/`FromString` round-trip
   (clRed.ToByte=0, TColor.FromByte(2)=clBlue, clGreen.ToString='clGreen',
   TColor.FromString('clBlue')=clBlue).
2. **explicit_ordinals.pas** -- `TSpec = (sp_Undefined = 0, sp_Double = 1, sp_Upper = 2);` assert
   FromByte case maps ord->member exactly + else=first member; ToInteger=ord.
3. **negative_ordinal.pas** -- `TEST = (Elem1 = -2, Elem2 = 0, Elem3);` assert FromByte is SKIPPED
   or warned (Byte can't hold -2), FromInteger still generated + clamps.
4. **already_has_helper.pas** -- enum + an existing `TXHelper record helper` -> assert the feature
   REFUSES / reports "helper already exists" (create-only-if-missing), makes NO edit.
5. **doc_interleaved.pas** -- enum with `{$REGION}`/`///` between members -> assert the member list
   is parsed correctly (noise skipped), helper members match the real enum members.
6. **idempotency** -- running "create helper" twice: 2nd run is a no-op (helper now exists) ->
   byte-identical file (ties to case 4).
7. **descriptions_reuse.pas** -- enum + a `const XDescriptions: array[TX] of string = (...)` ->
   assert a `ToDescription` is generated reusing that array (bonus path).
8. **round-trip build test** -- ALL generated helpers must COMPILE (a fixture unit that USES the
   generated helper's 6 methods + a DUnitX/console assert of the round-trips). This is the real gate:
   generated Object Pascal that compiles + round-trips, not just text-matches.
9. **placement** -- assert the helper is inserted immediately AFTER the enum type decl, in the same
   `type` section + unit, with the impl bodies in the `implementation` section (or an inline helper
   if the enum is in an interface-only unit -- decide in the spec).
10. **CLI + IDE parity** -- the CLI verb (`create-enum-helper --qname TX` or similar) and the IDE
    "Create helper class" menu produce the SAME edit.

Oracle for the generation: the MSCTYPES.PAS helpers are the hand-written reference -- a fixture that
mirrors `TSpecType` should generate a helper structurally equivalent to `TSpecTypeHelper` (the exact
whitespace need not match, but the method set + bodies' logic must).

## Feature entry points (for the spec/plan)

- **IDE trigger:** right-click on (a) an ENUM MEMBER identifier, OR (b) the enum TYPE/class-definition
  node -> context menu item "Create helper class" -- ENABLED only when the symbol under the cursor
  resolves to an enum type that has NO existing `record helper`. (Mirror the AutoDocument "Document
  it"/"Document unit" menu wiring in `DragLint.Plugin.StructureForm.pas`; the enablement predicate
  queries the index for the enum + a pre-existing helper.)
- **CLI verb:** the IDE menu spawns a CLI verb (e.g. `create-enum-helper --qname <TEnum> [--apply]
  [--methods tobyte,frombyte,tointeger,frominteger,tostring,fromstring] [--db PATH]`) that emits a
  TTextEdit inserting the helper decl + impl. Reuses the TTextEditApplier substrate.
- **Index needs -- ALREADY SATISFIED (verified, de-risks the feature):** the indexer emits `skEnum`
  for the type AND a `skEnumValue` child per member (parser `TryWalkEnum`,
  `src/parser/DRagLint.Parser.Delphi13.pas:525-536`, over `declEnumValue` nodes). It captures each
  member's NAME + parent + order, but NOT the explicit ordinal literal (`= -2`, `= 65`). **That is
  fine: the generator emits `ord(<MemberName>)` in the FromByte/ToString case and Delphi computes the
  ordinal itself -- drag-lint never needs the literal value.** Member ORDER + NAMES (both captured)
  are sufficient to generate the entire helper. So NO parser/index prerequisite -- the feature can
  query `FindAllChildSymbols(enumSymbolId)` filtered to `skEnumValue` (in declaration order) and
  generate directly. (The negative-ordinal FromByte-skip decision -- case corner #1 -- can't read the
  literal from the index; either detect it by reading the source line of the enum decl, or make
  FromByte always-generated-with-an-else-fallback and accept that a negative member just won't be
  reachable via a Byte, which is inherent anyway. Simplest: always generate FromByte over `ord(member)`;
  a member whose ordinal is out of Byte range is simply never matched -- correct + no literal needed.)
