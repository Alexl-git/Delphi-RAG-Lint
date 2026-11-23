unit DRagLint.FieldRepo.Kinds;

{ drag-lint 1.53 -- lane FR-MODEL: field kinds of the repository model v2 and the calc-body macro
  parser (design 2026-11-22-field-repository-v2-design.md sections 4.1 and 4.3).
  Pure functions: no repository connection, no I/O. }

interface

uses
  System.SysUtils;

type
  /// <summary>Raised for an unknown FIELD_KIND code or a malformed calc-body macro.</summary>
  EFrKindError = class(Exception);

  /// <summary>The kind of a DL_FIELDS_INFO row (spec 4.1).</summary>
  /// <remarks>Codes: data 1 (NULL reads as data), calc 2, lookup 3, internal-calc 4, aggregate 5,
  /// graphical 10 (a grid column drawn by events; no data field).</remarks>
  TFrFieldKind = (frkData, frkCalc, frkLookup, frkInternalCalc, frkAggregate, frkGraphical);

  /// <summary>One `{{FIELD}}` macro found in a calc body.</summary>
  TFrMacro = record
    /// <summary>The identifier between the braces, as written.</summary>
    Name: string;
    /// <summary>1-based offset of the opening `{{` in the body.</summary>
    Offset: Integer;
    /// <summary>Length of the whole macro text including both brace pairs.</summary>
    Len: Integer;
  end;

/// <summary>Maps a FIELD_KIND column value to its kind.</summary>
/// <param name="pCode">The column value: Null or Unassigned (a legacy row) or an integer code.</param>
/// <returns>frkData for Null / Unassigned / 1; the kind of codes 2, 3, 4, 5, 10.</returns>
/// <exception cref="EFrKindError">The code is none of the above.</exception>
function FrKindFromCode(const pCode: Variant): TFrFieldKind;

/// <summary>Tests whether a FIELD_KIND code is known, without raising.</summary>
/// <param name="pCode">The column value (see FrKindFromCode).</param>
/// <returns>True for Null, Unassigned, 1, 2, 3, 4, 5 and 10.</returns>
function FrKindCodeKnown(const pCode: Variant): Boolean;

/// <summary>The FIELD_KIND code a kind is stored with.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>1, 2, 3, 4, 5 or 10.</returns>
function FrKindToCode(pKind: TFrFieldKind): Integer;

/// <summary>Short lower-case name of a kind: data, calc, lookup, internal-calc, aggregate, graphical.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>The name used in `repo check` output.</returns>
function FrKindName(pKind: TFrFieldKind): string;

/// <summary>True for the kinds whose CALC_BODY names other fields: calc, internal-calc, aggregate.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>True when the kind carries a body with dependencies.</returns>
function FrKindHasBody(pKind: TFrFieldKind): Boolean;

/// <summary>Finds every `{{FIELD}}` macro of a calc body (grammar of spec 4.3).</summary>
/// <param name="pBody">The CALC_BODY text; '' or Pascal text without macros gives an empty array.</param>
/// <returns>The macros in order of appearance.</returns>
/// <exception cref="EFrKindError">`{{` without a closing `}}` (message names the 1-based offset), an
/// empty or malformed identifier, or `{{TABLE.FIELD}}` (reserved, an error in 1.53).</exception>
/// <remarks>Grammar: `{{` identifier `}}`, identifier = [A-Za-z_][A-Za-z0-9_$]*. There are no escapes:
/// `{{{{` is an error, a literal `{{` in a string has to be rewritten.</remarks>
function ParseMacros(const pBody: string): TArray<TFrMacro>;  // dl:ok unused-public-symbol@0107 -- REVIEWED 2026-11-23: public API of the calc-body grammar: tests/fieldrepo/ModelTests.dpr K2 asserts its errors directly; outside this project index

/// <summary>The fields a calc body depends on.</summary>
/// <param name="pBody">The CALC_BODY text.</param>
/// <param name="pSelf">The field that owns the body; a macro of that name directly followed by `:=`
/// is its own assignment target and is not a dependency.</param>
/// <returns>Distinct field names (compared case-insensitively) in order of first appearance, as written.</returns>
/// <exception cref="EFrKindError">As ParseMacros.</exception>
/// <remarks>CalcDependencies('{{TOTAL}} := {{QTY}} * {{PRICE}};', 'TOTAL') = [QTY, PRICE]. A right-hand
/// side use of pSelf stays a dependency, so `repo check` reports it as a cycle TOTAL -> TOTAL.</remarks>
function CalcDependencies(const pBody, pSelf: string): TArray<string>;

implementation

uses
  System.Variants;

const
  CODE_DATA = 1;
  CODE_CALC = 2;
  CODE_LOOKUP = 3;
  CODE_INTERNAL_CALC = 4;
  CODE_AGGREGATE = 5;
  CODE_GRAPHICAL = 10;
  MACRO_OPEN = '{{';
  MACRO_CLOSE = '}}';
  MACRO_OPEN_LEN = 2;
  MACRO_CLOSE_LEN = 2;
  ASSIGN_OP = ':=';

function IsIdentStart(pC: Char): Boolean;
begin
  Result := CharInSet(pC, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(pC: Char): Boolean;
begin
  Result := IsIdentStart(pC) or CharInSet(pC, ['0'..'9', '$']);
end;

function FrKindCodeKnown(const pCode: Variant): Boolean;
begin
  if VarIsNull(pCode) or VarIsEmpty(pCode) then
    Exit(True);
  Result := Integer(pCode) in [CODE_DATA, CODE_CALC, CODE_LOOKUP, CODE_INTERNAL_CALC, CODE_AGGREGATE, CODE_GRAPHICAL];
end;

function FrKindFromCode(const pCode: Variant): TFrFieldKind;
begin
  if VarIsNull(pCode) or VarIsEmpty(pCode) then
    Exit(frkData);
  case Integer(pCode) of
    CODE_DATA: Result := frkData;
    CODE_CALC: Result := frkCalc;
    CODE_LOOKUP: Result := frkLookup;
    CODE_INTERNAL_CALC: Result := frkInternalCalc;
    CODE_AGGREGATE: Result := frkAggregate;
    CODE_GRAPHICAL: Result := frkGraphical;
  else
    raise EFrKindError.CreateFmt('unknown FIELD_KIND code %d', [Integer(pCode)]);
  end;
end;

function FrKindToCode(pKind: TFrFieldKind): Integer;
begin
  case pKind of
    frkCalc: Result := CODE_CALC;
    frkLookup: Result := CODE_LOOKUP;
    frkInternalCalc: Result := CODE_INTERNAL_CALC;
    frkAggregate: Result := CODE_AGGREGATE;
    frkGraphical: Result := CODE_GRAPHICAL;
  else
    Result := CODE_DATA;
  end;
end;

function FrKindName(pKind: TFrFieldKind): string;
begin
  case pKind of
    frkCalc: Result := 'calc';
    frkLookup: Result := 'lookup';
    frkInternalCalc: Result := 'internal-calc';
    frkAggregate: Result := 'aggregate';
    frkGraphical: Result := 'graphical';
  else
    Result := 'data';
  end;
end;

function FrKindHasBody(pKind: TFrFieldKind): Boolean;
begin
  Result := pKind in [frkCalc, frkInternalCalc, frkAggregate];
end;

function ParseMacros(const pBody: string): TArray<TFrMacro>;
var
  VPos, VClose, VI: Integer;
  VInner: string;
  VMacro: TFrMacro;
begin
  Result := nil;
  VPos := Pos(MACRO_OPEN, pBody);
  while VPos > 0 do
  begin
    VClose := Pos(MACRO_CLOSE, pBody, VPos + MACRO_OPEN_LEN);
    if VClose = 0 then
      raise EFrKindError.CreateFmt('unterminated {{ at offset %d', [VPos]);
    VInner := Copy(pBody, VPos + MACRO_OPEN_LEN, VClose - VPos - MACRO_OPEN_LEN);
    if VInner = '' then
      raise EFrKindError.CreateFmt('empty macro {{}} at offset %d', [VPos]);
    if VInner.Contains('.') then
      raise EFrKindError.CreateFmt('{{TABLE.FIELD}} is not supported (reserved) at offset %d: {{%s}}', [VPos, VInner]);
    if not IsIdentStart(VInner[1]) then
      raise EFrKindError.CreateFmt('invalid macro identifier at offset %d: {{%s}}', [VPos, VInner]);
    for VI := 2 to Length(VInner) do
      if not IsIdentChar(VInner[VI]) then
        raise EFrKindError.CreateFmt('invalid macro identifier at offset %d: {{%s}}', [VPos, VInner]);
    VMacro.Name := VInner;
    VMacro.Offset := VPos;
    VMacro.Len := VClose + MACRO_CLOSE_LEN - VPos;
    Result := Result + [VMacro];
    VPos := Pos(MACRO_OPEN, pBody, VClose + MACRO_CLOSE_LEN);
  end;
end;

{ True when the text after the macro, blanks skipped, starts with ':='. }
function IsAssignTarget(const pBody: string; const pMacro: TFrMacro): Boolean;
var
  VPos: Integer;
begin
  VPos := pMacro.Offset + pMacro.Len;
  while (VPos <= Length(pBody)) and CharInSet(pBody[VPos], [' ', #9, #13, #10]) do
    Inc(VPos);
  Result := Copy(pBody, VPos, Length(ASSIGN_OP)) = ASSIGN_OP;
end;

function CalcDependencies(const pBody, pSelf: string): TArray<string>;
var
  VMacro: TFrMacro;
  VName: string;
  VSeen: Boolean;
begin
  Result := nil;
  for VMacro in ParseMacros(pBody) do
  begin
    if SameText(VMacro.Name, pSelf) and IsAssignTarget(pBody, VMacro) then
      Continue;
    VSeen := False;
    for VName in Result do
      if SameText(VName, VMacro.Name) then
        VSeen := True;
    if not VSeen then
      Result := Result + [VMacro.Name];
  end;
end;

end.
