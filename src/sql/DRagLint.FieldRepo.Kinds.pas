unit DRagLint.FieldRepo.Kinds;

{ drag-lint 1.53 -- lane FR-MODEL: field kinds of the repository model v2 and the calc-body macro
  parser (design 2026-11-22-field-repository-v2-design.md sections 4.1 and 4.3).
  1.54 (rulings 2026-11-23, R2 / R3): the event columns of a field row, and macros that name the field component.
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

  /// <summary>An event whose code is a column of the field row (ruling R2).</summary>
  TFrEventColumn = record
    /// <summary>Event property, e.g. OnGetText.</summary>
    Event: string;
    /// <summary>DL_FIELDS_INFO column, e.g. ONGETTEXT_BODY.</summary>
    Column: string;
    /// <summary>Parameter names stored code uses, in the order of the event type, comma-separated.</summary>
    Params: string;
    /// <summary>True for a column event of a DBTable grid view, False for a TField event.</summary>
    IsGrid: Boolean;
  end;

const
  /// <summary>The event columns of DL_FIELDS_INFO, in column order.</summary>
  FR_EVENT_COLUMNS: array[0..5] of TFrEventColumn = (
    (Event: 'OnGetText'; Column: 'ONGETTEXT_BODY'; Params: 'Sender,Text,DisplayText'; IsGrid: False),
    (Event: 'OnSetText'; Column: 'ONSETTEXT_BODY'; Params: 'Sender,Text'; IsGrid: False),
    (Event: 'OnValidate'; Column: 'ONVALIDATE_BODY'; Params: 'Sender'; IsGrid: False),
    (Event: 'OnChange'; Column: 'ONCHANGE_BODY'; Params: 'Sender'; IsGrid: False),
    (Event: 'OnGetDisplayText'; Column: 'GRID_DISPLAYTEXT_BODY'; Params: 'Sender,ARecord,AText'; IsGrid: True),
    (Event: 'OnCustomDrawCell'; Column: 'GRID_DRAWCELL_BODY'; Params: 'Sender,ACanvas,AViewInfo,ADone'; IsGrid: True));

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
function ParseMacros(const pBody: string): TArray<TFrMacro>;

/// <summary>The fields a calc body depends on.</summary>
/// <param name="pBody">The CALC_BODY text.</param>
/// <param name="pSelf">The field that owns the body; a macro of that name that is written (`:=`, `.Member :=` or
/// `.Clear` follows) is not a dependency, and neither is a read of it behind the end of a statement that writes it.</param>
/// <returns>Distinct field names (compared case-insensitively) in order of first appearance, as written.</returns>
/// <exception cref="EFrKindError">As ParseMacros.</exception>
/// <remarks>CalcDependencies('{{TOTAL}}.AsFloat := {{QTY}}.AsInteger * {{PRICE}}.AsFloat;', 'TOTAL') = [QTY, PRICE]. A
/// use of pSelf in its own assignment or before one stays a dependency: `repo check` reports it as a cycle
/// TOTAL -> TOTAL.</remarks>
function CalcDependencies(const pBody, pSelf: string): TArray<string>;

implementation

uses
  System.StrUtils,
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
  MEMBER_CLEAR = 'Clear';
  QUOTE = '''';

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

function SkipBlanks(const pText: string; pPos: Integer): Integer;
begin
  Result := pPos;
  while (Result <= Length(pText)) and CharInSet(pText[Result], [' ', #9, #13, #10]) do
    Inc(Result);
end;

{ True when the macro is written: ':=', '.Member :=' or '.Clear' follows, blanks skipped. }
function IsWriteTarget(const pBody: string; const pMacro: TFrMacro): Boolean;
var
  VPos, VFirst: Integer;
begin
  VPos := SkipBlanks(pBody, pMacro.Offset + pMacro.Len);
  Result := False;
  if Copy(pBody, VPos, 1) = '.' then
  begin
    VFirst := SkipBlanks(pBody, VPos + 1);
    VPos := VFirst;
    while (VPos <= Length(pBody)) and IsIdentChar(pBody[VPos]) do
      Inc(VPos);
    Result := SameText(Copy(pBody, VFirst, VPos - VFirst), MEMBER_CLEAR);
    VPos := SkipBlanks(pBody, VPos);
  end;
  Result := Result or (Copy(pBody, VPos, Length(ASSIGN_OP)) = ASSIGN_OP);
end;

{ Offset behind a string or comment that starts at pPos; pPos itself when none does. }
function SkipTrivia(const pText: string; pPos: Integer): Integer;

  function Behind(const pClose: string; pOpenLen: Integer): Integer;
  begin
    Result := Pos(pClose, pText, pPos + pOpenLen);
    Result := if Result = 0 then Length(pText) + 1 else Result + Length(pClose);
  end;

begin
  Result := pPos;
  if pText[pPos] = QUOTE then
    Result := Behind(QUOTE, 1)
  else if (pText[pPos] = '{') and (Copy(pText, pPos, MACRO_OPEN_LEN) <> MACRO_OPEN) then
    Result := Behind('}', 1)
  else if Copy(pText, pPos, 2) = '(*' then
    Result := Behind('*)', 2)
  else if Copy(pText, pPos, 2) = '//' then
    Result := Behind(#10, 2);
end;

{ True when a statement ends between two offsets: a semicolon outside strings and comments. }
function StatementEnds(const pBody: string; pFirst, pLast: Integer): Boolean;
var
  VPos, VNext: Integer;
begin
  VPos := pFirst;
  while VPos < pLast do
  begin
    if pBody[VPos] = ';' then
      Exit(True);
    VNext := SkipTrivia(pBody, VPos);
    VPos := if VNext > VPos then VNext else VPos + 1;
  end;
  Result := False;
end;

function CalcDependencies(const pBody, pSelf: string): TArray<string>;
var
  VMacro: TFrMacro;
  VWritten: Integer; // behind the first write of pSelf, 0 = none yet
begin
  Result := nil;
  VWritten := 0;
  for VMacro in ParseMacros(pBody) do
  begin
    if SameText(VMacro.Name, pSelf) then
    begin
      if IsWriteTarget(pBody, VMacro) then
      begin
        if VWritten = 0 then
          VWritten := VMacro.Offset + VMacro.Len;
        Continue;
      end;
      if (VWritten > 0) and StatementEnds(pBody, VWritten, VMacro.Offset) then
        Continue;
    end;
    if not MatchText(VMacro.Name, Result) then
      Result := Result + [VMacro.Name];
  end;
end;

end.
