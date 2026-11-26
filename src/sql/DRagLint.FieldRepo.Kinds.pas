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

  /// <summary>Raised when a body names `{{ALIAS.FIELD}}` with an alias its field does not declare in DL_FIELD_INPUTS
  /// (design 2026-11-26-cross-table-fields-design.md 2.1).</summary>
  EFrAliasError = class(EFrKindError);

  /// <summary>One input of a body: an own field (Alias '') or a field of another table reached through a declared
  /// input alias.</summary>
  TFrInput = record
    /// <summary>'' for an own field, else the alias as written.</summary>
    Alias: string;
    /// <summary>The field name as written.</summary>
    Field: string;
  end;

  /// <summary>The kind of a DL_FIELDS_INFO row (spec 4.1).</summary>
  /// <remarks>Codes: data 1 (NULL reads as data), calc 2, lookup 3, internal-calc 4, aggregate 5,
  /// graphical 10 (a grid column drawn by events; no data field).</remarks>
  TFrFieldKind = (frkData, frkCalc, frkLookup, frkInternalCalc, frkAggregate, frkGraphical);

  /// <summary>One `{{FIELD}}` macro found in a calc body.</summary>
  TFrMacro = record
    /// <summary>The identifier between the braces, as written; for `{{ALIAS.FIELD}}` the FIELD part.</summary>
    Name: string;
    /// <summary>'' for `{{FIELD}}`; the ALIAS part of `{{ALIAS.FIELD}}` (ParseMacrosWithAliases only).</summary>
    Alias: string;
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

/// <summary>Finds every `{{FIELD}}` macro of a calc body (grammar of spec 4.3); one in a string or a comment is text.</summary>
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
/// `.Clear` follows) is not a dependency, and neither is a read of it behind a statement that has written it on every
/// path: a write in some branches only, in a loop body or in an anonymous method does not count.</param>
/// <returns>Distinct field names (compared case-insensitively) in order of first appearance, as written.</returns>
/// <exception cref="EFrKindError">As ParseMacros.</exception>
/// <remarks>CalcDependencies('{{TOTAL}}.AsFloat := {{QTY}}.AsInteger * {{PRICE}}.AsFloat;', 'TOTAL') = [QTY, PRICE]. A
/// use of pSelf in its own assignment or before one stays a dependency: `repo check` reports it as a cycle
/// TOTAL -> TOTAL.</remarks>
function CalcDependencies(const pBody, pSelf: string): TArray<string>;

/// <summary>As ParseMacros, but `{{ALIAS.FIELD}}` is legal when ALIAS is one of pAliases (design 2.1, ruling R3 as
/// amended 2026-11-26).</summary>
/// <param name="pBody">A CALC_BODY or event-column body.</param>
/// <param name="pAliases">The input aliases the field declares (its default binding); compared case-insensitively.</param>
/// <returns>The macros in order; Alias is '' for an own field, else the alias as written.</returns>
/// <exception cref="EFrAliasError">ALIAS is not in pAliases.</exception>
/// <exception cref="EFrKindError">As ParseMacros, and for a second dot or an empty alias / field part.</exception>
function ParseMacrosWithAliases(const pBody: string; const pAliases: array of string): TArray<TFrMacro>;  // dl:ok unused-public-symbol@4edc -- REVIEWED 2026-11-26 XTABLE: public API of the X1 rule unit, called by tests\fieldrepo\CrossTableTests.dpr (outside this index) and by later slices (X3 read-dfm, the 1.56 dialog)

/// <summary>The inputs of a body: own fields as CalcDependencies finds them, plus every `{{ALIAS.FIELD}}`.</summary>
/// <param name="pBody">The body text.</param>
/// <param name="pSelf">The field that owns the body (same rule as CalcDependencies; an aliased macro is never it).</param>
/// <param name="pAliases">The declared input aliases of the field.</param>
/// <returns>Distinct (alias, field) pairs, compared case-insensitively, in order of first appearance, as written.</returns>
/// <exception cref="EFrAliasError">As ParseMacrosWithAliases.</exception>
/// <exception cref="EFrKindError">As ParseMacrosWithAliases.</exception>
function CalcInputs(const pBody, pSelf: string; const pAliases: array of string): TArray<TFrInput>;

implementation

uses
  System.StrUtils,
  System.Variants,
  System.RegularExpressions;

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
  { what the walk over the statements of a body looks at }
  PAT_BODY_TOKEN = '\{\{[^}]*\}\}|\.\s*&?[A-Za-z_]\w*|&?[A-Za-z_]\w*|:=|[;:]';
  WORD_BEGIN = 'begin';
  WORD_DO = 'do';
  WORD_ELSE = 'else';
  WORD_END = 'end';
  WORD_EXCEPT = 'except';
  WORD_FINALLY = 'finally';
  WORD_IF = 'if';
  WORD_OF = 'of';
  WORD_THEN = 'then';
  WORD_UNTIL = 'until';
  STATEMENT_END = ';';
  LABEL_END = ':';
  STATEMENT_STOPS: array[0..5] of string = (STATEMENT_END, WORD_END, WORD_ELSE, WORD_UNTIL, WORD_FINALLY, WORD_EXCEPT);
  ASSIGN_OP = ':=';
  MEMBER_CLEAR = 'Clear';
  { a string over several lines, a string, a comment, or the two braces that open a macro }
  PAT_MACRO_TOKEN = '(?s)(''''''(?:'''')*)(?=[ \t]*\r?\n).*?\n[ \t]*\1(?!'')|''(?:''''|[^''\r\n])*''?|//[^\r\n]*' +
    '|\(\*.*?(?:\*\)|\z)|\{\{|\{.*?(?:\}|\z)';

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

{ The text with every string and comment blanked, offsets and line breaks kept; a macro is copied as it is. }
function BlankStringsAndComments(const pBody: string): string;
var
  VPos, VI: Integer;
  VToken: TMatch;
begin
  Result := pBody;
  VPos := 1;
  while VPos <= Length(pBody) do
  begin
    VToken := TRegEx.Match(Copy(pBody, VPos), PAT_MACRO_TOKEN);
    if not VToken.Success then
      Break;
    Inc(VPos, VToken.Index - 1);
    if VToken.Value = MACRO_OPEN then
    begin
      VPos := Pos(MACRO_CLOSE, pBody, VPos + MACRO_OPEN_LEN);
      if VPos = 0 then
        Break;
      Inc(VPos, MACRO_CLOSE_LEN);
      Continue;
    end;
    for VI := VPos to VPos + VToken.Length - 1 do
      if not CharInSet(Result[VI], [#13, #10]) then
        Result[VI] := ' ';
    Inc(VPos, VToken.Length);
  end;
end;

function IsIdent(const pText: string): Boolean;
var
  VI: Integer;
begin
  Result := (pText <> '') and IsIdentStart(pText[1]);
  for VI := 2 to Length(pText) do
    Result := Result and IsIdentChar(pText[VI]);
end;

// The macros of a body; pAllowAliases False = an ALIAS.FIELD macro is the reserved error of 1.53, True = legal when
// ALIAS is in pAliases.
function ScanMacros(const pBody: string; pAllowAliases: Boolean; const pAliases: array of string): TArray<TFrMacro>;
var
  VPos, VClose, VDot: Integer;
  VCode, VInner: string;
  VMacro: TFrMacro;
begin
  Result := nil;
  VCode := BlankStringsAndComments(pBody);
  VPos := Pos(MACRO_OPEN, VCode);
  while VPos > 0 do
  begin
    VClose := Pos(MACRO_CLOSE, VCode, VPos + MACRO_OPEN_LEN);
    if VClose = 0 then
      raise EFrKindError.CreateFmt('unterminated {{ at offset %d', [VPos]);
    VInner := Copy(VCode, VPos + MACRO_OPEN_LEN, VClose - VPos - MACRO_OPEN_LEN);
    if VInner = '' then
      raise EFrKindError.CreateFmt('empty macro {{}} at offset %d', [VPos]);
    VMacro.Alias := '';
    VMacro.Name := VInner;
    VDot := Pos('.', VInner);
    if (VDot > 0) and not pAllowAliases then
      raise EFrKindError.CreateFmt('{{TABLE.FIELD}} is not supported (reserved) at offset %d: {{%s}}', [VPos, VInner]);
    if VDot > 0 then
    begin
      VMacro.Alias := Copy(VInner, 1, VDot - 1);
      VMacro.Name := Copy(VInner, VDot + 1, MaxInt);
      if not (IsIdent(VMacro.Alias) and IsIdent(VMacro.Name)) then
        raise EFrKindError.CreateFmt('invalid macro {{ALIAS.FIELD}} at offset %d: {{%s}}', [VPos, VInner]);
      if not MatchText(VMacro.Alias, pAliases) then
        raise EFrAliasError.CreateFmt('macro {{%s}} at offset %d: %s is no declared input alias of this field',
          [VInner, VPos, VMacro.Alias]);
    end
    else if not IsIdent(VInner) then
      raise EFrKindError.CreateFmt('invalid macro identifier at offset %d: {{%s}}', [VPos, VInner]);
    VMacro.Offset := VPos;
    VMacro.Len := VClose + MACRO_CLOSE_LEN - VPos;
    Result := Result + [VMacro];
    VPos := Pos(MACRO_OPEN, VCode, VClose + MACRO_CLOSE_LEN);
  end;
end;

function ParseMacros(const pBody: string): TArray<TFrMacro>;
begin
  Result := ScanMacros(pBody, False, []);
end;

function SkipBlanks(const pText: string; pPos: Integer): Integer;
begin
  Result := pPos;
  while (Result <= Length(pText)) and CharInSet(pText[Result], [' ', #9, #13, #10]) do
    Inc(Result);
end;

{ True when the macro is written: ':=', '.Member :=' or '.Clear' follows, blanks skipped; pBody has no strings or
  comments. }
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

type
  TSelfUse = (suNone, suRead, suWrite);

  TBodyToken = record
    Text: string;
    Offset: Integer;
    Use: TSelfUse;
  end;

  { Walks the statements of a body and finds the first read of one field that no statement before it has written on
    every path. Exit and raise are plain statements: a write behind one counts. }
  TSelfWalk = record
  private
    FTokens: TArray<TBodyToken>;
    FPos: Integer;
    FWritten: Boolean;
    FFirstRead: Integer;
    function IsAt(const pWords: array of string): Boolean;
    procedure Skip;
    procedure SkipMethodHead;
    procedure Expression(const pStops: array of string);
    procedure Statement;
    procedure Statements(const pStops: array of string);
    procedure Branch;
    procedure IfStatement;
    procedure CaseStatement;
    procedure TryStatement;
    procedure RepeatStatement;
  public
    function FirstRead(const pCode, pSelf: string): Integer;
  end;

function SelfUse(const pCode, pSelf: string; const pToken: TBodyToken): TSelfUse;
var
  VMacro: TFrMacro;
begin
  if not SameText(pToken.Text, MACRO_OPEN + pSelf + MACRO_CLOSE) then
    Exit(suNone);
  VMacro.Offset := pToken.Offset;
  VMacro.Len := Length(pToken.Text);
  Result := if IsWriteTarget(pCode, VMacro) then suWrite else suRead;
end;

{ 1-based offset of that read, 0 = none. pCode has no strings or comments. }
function TSelfWalk.FirstRead(const pCode, pSelf: string): Integer;
var
  VMatch: TMatch;
  VToken: TBodyToken;
begin
  Self := Default(TSelfWalk);
  for VMatch in TRegEx.Matches(pCode, PAT_BODY_TOKEN) do
  begin
    VToken.Text := VMatch.Value;
    VToken.Offset := VMatch.Index;
    VToken.Use := SelfUse(pCode, pSelf, VToken);
    FTokens := FTokens + [VToken];
  end;
  Statements([]);
  Result := FFirstRead;
end;

function TSelfWalk.IsAt(const pWords: array of string): Boolean;
begin
  Result := (FPos < Length(FTokens)) and MatchText(FTokens[FPos].Text, pWords);
end;

procedure TSelfWalk.Skip;
begin
  if (FPos < Length(FTokens)) and (FTokens[FPos].Use = suRead) and (not FWritten) and (FFirstRead = 0) then
    FFirstRead := FTokens[FPos].Offset;
  Inc(FPos);
end;

{ To the begin of an anonymous method: its declarations hold semicolons. }
procedure TSelfWalk.SkipMethodHead;
begin
  while (FPos < Length(FTokens)) and not IsAt([WORD_BEGIN]) do
    Skip;
end;

{ Up to one of pStops; the then and else of a ternary belong to the expression. A field it writes is written at its end. }
procedure TSelfWalk.Expression(const pStops: array of string);
var
  VTernaries: Integer;
  VWrites: Boolean;
begin
  VTernaries := 0;
  VWrites := False;
  while (FPos < Length(FTokens)) and ((not IsAt(pStops)) or ((VTernaries > 0) and IsAt([WORD_THEN, WORD_ELSE]))) do
  begin
    if IsAt(['procedure', 'function']) then
      SkipMethodHead;
    if IsAt([WORD_BEGIN]) then
    begin
      Branch;
      Continue;
    end;
    if IsAt([WORD_IF]) then
      Inc(VTernaries)
    else if IsAt([WORD_ELSE]) then
      Dec(VTernaries);
    VWrites := VWrites or ((FPos < Length(FTokens)) and (FTokens[FPos].Use = suWrite));
    Skip;
  end;
  FWritten := FWritten or VWrites;
end;

{ A statement that may not run. }
procedure TSelfWalk.Branch;
var
  VBefore: Boolean;
begin
  VBefore := FWritten;
  Statement;
  FWritten := VBefore;
end;

procedure TSelfWalk.Statements(const pStops: array of string);
var
  VStart: Integer;
begin
  while (FPos < Length(FTokens)) and not IsAt(pStops) do
  begin
    VStart := FPos;
    Statement;
    if FPos = VStart then
      Skip;
  end;
end;

procedure TSelfWalk.Statement;
begin
  if IsAt([WORD_BEGIN]) then
  begin
    Skip;
    Statements([WORD_END]);
    Skip;
  end
  else if IsAt([WORD_IF]) then
    IfStatement
  else if IsAt(['case']) then
    CaseStatement
  else if IsAt(['try']) then
    TryStatement
  else if IsAt(['repeat']) then
    RepeatStatement
  else if IsAt(['while', 'for', 'on']) then
  begin
    Expression([WORD_DO]);
    Skip;
    Branch;
  end
  else if IsAt(['with']) then
  begin
    Expression([WORD_DO]);
    Skip;
    Statement;
  end
  else
    Expression(STATEMENT_STOPS);
end;

procedure TSelfWalk.IfStatement;
var
  VBefore, VThen: Boolean;
begin
  Skip;
  Expression([WORD_THEN]);
  Skip;
  VBefore := FWritten;
  Statement;
  VThen := FWritten;
  FWritten := VBefore;
  if not IsAt([WORD_ELSE]) then
    Exit;
  Skip;
  Statement;
  FWritten := FWritten and VThen;
end;

procedure TSelfWalk.CaseStatement;
var
  VBefore, VAll, VElse: Boolean;
begin
  Expression([WORD_OF]);
  Skip;
  VBefore := FWritten;
  VAll := True;
  while (FPos < Length(FTokens)) and not IsAt([WORD_END, WORD_ELSE]) do
  begin
    if IsAt([STATEMENT_END]) then
    begin
      Skip;
      Continue;
    end;
    Expression([LABEL_END, WORD_END, WORD_ELSE]);
    if IsAt([LABEL_END]) then
      Skip;
    FWritten := VBefore;
    Statement;
    VAll := VAll and FWritten;
  end;
  FWritten := VBefore;
  VElse := IsAt([WORD_ELSE]);
  if VElse then
    Skip;
  Statements([WORD_END]);
  Skip;
  FWritten := VBefore or (VElse and VAll and FWritten);
end;

procedure TSelfWalk.TryStatement;
var
  VBefore, VTry, VSelective: Boolean;
begin
  Skip;
  VBefore := FWritten;
  Statements([WORD_FINALLY, WORD_EXCEPT, WORD_END]);
  VTry := FWritten;
  FWritten := VBefore;
  if IsAt([WORD_FINALLY]) then
  begin
    Skip;
    Statements([WORD_END]);
    FWritten := FWritten or VTry;
  end
  else if IsAt([WORD_EXCEPT]) then
  begin
    Skip;
    VSelective := IsAt(['on']);
    Statements([WORD_END]);
    FWritten := if VSelective then VBefore else FWritten and VTry;
  end;
  Skip;
end;

{ Break may leave the loop before the write. }
procedure TSelfWalk.RepeatStatement;
var
  VBefore: Boolean;
begin
  VBefore := FWritten;
  Skip;
  Statements([WORD_UNTIL]);
  Skip;
  Expression(STATEMENT_STOPS);
  FWritten := VBefore;
end;

function CalcDependencies(const pBody, pSelf: string): TArray<string>;
var
  VMacro: TFrMacro;
  VWalk: TSelfWalk;
  VSelfRead: Integer;
begin
  Result := nil;
  VSelfRead := VWalk.FirstRead(BlankStringsAndComments(pBody), pSelf);
  for VMacro in ParseMacros(pBody) do
    if (not SameText(VMacro.Name, pSelf) or (VMacro.Offset = VSelfRead)) and not MatchText(VMacro.Name, Result) then
      Result := Result + [VMacro.Name];
end;

function ParseMacrosWithAliases(const pBody: string; const pAliases: array of string): TArray<TFrMacro>;
begin
  Result := ScanMacros(pBody, True, pAliases);
end;

function CalcInputs(const pBody, pSelf: string; const pAliases: array of string): TArray<TFrInput>;
var
  VMacro: TFrMacro;
  VWalk: TSelfWalk;
  VSelfRead: Integer;
  VInput: TFrInput;
  VSeen: TArray<string>;
  VKey: string;
begin
  Result := nil;
  VSeen := nil;
  VWalk := Default(TSelfWalk);
  VSelfRead := VWalk.FirstRead(BlankStringsAndComments(pBody), pSelf);
  for VMacro in ParseMacrosWithAliases(pBody, pAliases) do
  begin
    if (VMacro.Alias = '') and SameText(VMacro.Name, pSelf) and (VMacro.Offset <> VSelfRead) then
      Continue;
    VKey := VMacro.Alias + '.' + VMacro.Name;
    if MatchText(VKey, VSeen) then
      Continue;
    VSeen := VSeen + [VKey];
    VInput.Alias := VMacro.Alias;
    VInput.Field := VMacro.Name;
    Result := Result + [VInput];
  end;
end;

end.
