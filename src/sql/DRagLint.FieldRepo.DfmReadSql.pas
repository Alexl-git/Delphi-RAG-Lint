unit DRagLint.FieldRepo.DfmReadSql;

{ drag-lint 1.54 -- lane TT-DFMREAD: which tables and columns a dataset's SELECT names, as FACTS only (design
  2026-11-22-field-repository-v2-design.md section 9; plan 2026-11-23-fr-dfmread.md). Everything the reader does not
  understand gives a reason, never a guess: UNION, CTE, derived table, macro table name, a computed item, an
  unqualified column of a join. Handles Firebird and BDE local SQL ("ToolFldr.DB".WarnFlag). Pure. }

interface

type
  /// <summary>One item of the select list.</summary>
  TDfmrSqlItem = record
    /// <summary>The name the dataset's field gets: the alias, else the column; '' when the item has none.</summary>
    OutName: string;
    /// <summary>True for a plain column (optionally qualified), False for an expression.</summary>
    Plain: Boolean;
    /// <summary>True for `*` or `alias.*`.</summary>
    Star: Boolean;
    /// <summary>Qualifier (alias or table) as written; '' when unqualified.</summary>
    Qualifier: string;
    /// <summary>Column name of a plain item.</summary>
    Column: string;
  end;

  /// <summary>A table of the FROM clause.</summary>
  TDfmrSqlTable = record
    /// <summary>Clean upper-case table name (CleanTableName).</summary>
    Name: string;
    /// <summary>Alias; '' when none.</summary>
    Alias: string;
  end;

  /// <summary>One equality `A.X = B.Y` between two different entries of the FROM clause: a JOIN's ON condition, or a
  /// WHERE equality (design 2026-11-26-cross-table-fields-design.md 3.2 rule 2).</summary>
  TDfmrSqlJoin = record
    /// <summary>Clean table name, the qualifier as written (alias or table) and the upper-case column of the left side.</summary>
    LeftTable: string;
    LeftAlias: string;
    LeftColumn: string;
    /// <summary>The same for the right side.</summary>
    RightTable: string;
    RightAlias: string;
    RightColumn: string;
    /// <summary>True when the equality is in the WHERE clause, False for an ON condition.</summary>
    InWhere: Boolean;
  end;

  /// <summary>What a SELECT reads.</summary>
  TDfmrSqlSource = record
    /// <summary>Tables of the FROM clause in order; empty when Reason is set.</summary>
    Tables: TArray<TDfmrSqlTable>;
    /// <summary>Select list.</summary>
    Items: TArray<TDfmrSqlItem>;
    /// <summary>The column equalities between FROM tables, in text order. Only an ON / WHERE condition that is a
    /// conjunction (AND at its top level, no OR) gives equalities; each must be `qualifier.column = qualifier.column`
    /// with two different FROM entries.</summary>
    Joins: TArray<TDfmrSqlJoin>;
    /// <summary>'' = understood; otherwise why the SQL says nothing.</summary>
    Reason: string;
  end;

/// <summary>Reads the FROM clause and the select list of a SELECT.</summary>
/// <param name="pSql">SQL text.</param>
/// <returns>The source; Reason is set for an empty text, a non-SELECT, UNION, WITH, a derived table, a macro in front of
/// the WHERE clause. A column repeated without an alias names the field `NAME_1`, `NAME_2`, ... in list order (OutName),
/// as BDE and FireDAC name it.</returns>
function ReadSelectSource(const pSql: string): TDfmrSqlSource;

type
  /// <summary>Asks the schema facts whether a table has a column.</summary>
  /// <param name="pTable">Clean upper-case table name.</param>
  /// <param name="pColumn">Upper-case column name.</param>
  /// <param name="pKnown">Receives False when there are no schema facts for the table at all.</param>
  /// <returns>True when the facts list the column.</returns>
  TDfmrColumnCheck = reference to function(const pTable, pColumn: string; out pKnown: Boolean): Boolean;

/// <summary>Finds the table column a dataset field comes from, without schema facts.</summary>
/// <param name="pSource">The SELECT (Reason '').</param>
/// <param name="pField">The dataset field name.</param>
/// <param name="pOrigin">The persistent field's Origin property (`"Tool.DB".Name`), '' = none.</param>
/// <param name="pTable">Receives the table.</param>
/// <param name="pColumn">Receives the column, upper case.</param>
/// <param name="pReason">Receives why the field has no column ('' when found).</param>
/// <returns>As the overload with a nil column check.</returns>
function SqlFieldColumn(const pSource: TDfmrSqlSource; const pField, pOrigin: string;
  out pTable, pColumn, pReason: string): Boolean; overload;

/// <summary>Finds the table column a dataset field comes from (design 2026-11-26-join-field-origin section 2.1):
/// the select list by the field's name, then a star, then the Origin (`"X.DB".COL`, `ALIAS."X.DB".COL`, `X.DB.COL`,
/// bare `COL`).</summary>
/// <param name="pSource">The SELECT (Reason '').</param>
/// <param name="pField">The dataset field name.</param>
/// <param name="pOrigin">The persistent field's Origin property, '' = none.</param>
/// <param name="pColumns">Schema facts for an unqualified column, a star over several tables and a bare Origin; nil =
/// none (such a field of a join is unresolved).</param>
/// <param name="pTable">Receives the table.</param>
/// <param name="pColumn">Receives the column, upper case.</param>
/// <param name="pReason">Receives why the field has no column ('' when found).</param>
/// <returns>True when exactly one table column is stated. False with `conflict: ...` when the select list and the
/// Origin name different columns, with `... is in N tables of the FROM` when an unqualified name is in several tables:
/// never a pick.</returns>
function SqlFieldColumn(const pSource: TDfmrSqlSource; const pField, pOrigin: string; const pColumns: TDfmrColumnCheck;
  out pTable, pColumn, pReason: string): Boolean; overload;

/// <summary>Upper-case table name without quotes, BDE alias, folder and Paradox / dBase extension.</summary>
/// <param name="pName">`TOOLS.DB`, `:MIC:Tools.db`, `"Tools"`, `C:\data\Tools.DB`.</param>
/// <returns>`TOOLS`.</returns>
function CleanTableName(const pName: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections;

type
  TSqlTokenKind = (stkWord, stkQuoted, stkText, stkSymbol);

  TSqlToken = record
    Kind: TSqlTokenKind;
    Text: string;
  end;

  TSqlTokens = TArray<TSqlToken>;

const
  DOT = '.';
  COMMA = ',';
  STAR = '*';
  OPEN_PAREN = '(';
  CLOSE_PAREN = ')';
  QUALIFIED_TOKENS = 3; // qualifier, dot, column
  TABLE_EXTENSIONS: array[0..1] of string = ('DB', 'DBF');
  FROM_END_WORDS: array[0..9] of string = ('WHERE', 'GROUP', 'ORDER', 'HAVING', 'PLAN', 'FETCH', 'ROWS', 'OFFSET', 'FOR',
    'WINDOW');
  WHERE_END_WORDS: array[0..8] of string = ('GROUP', 'ORDER', 'HAVING', 'PLAN', 'FETCH', 'ROWS', 'OFFSET', 'FOR', 'WINDOW');
  { Words that are values, or start an expression, where a column may stand. }
  VALUE_WORDS: array[0..11] of string = ('NULL', 'NOT', 'TRUE', 'FALSE', 'USER', 'CURRENT_DATE', 'CURRENT_TIME', 'CURRENT_TIMESTAMP',
    'CURRENT_USER', 'CURRENT_ROLE', 'LOCALTIME', 'LOCALTIMESTAMP');
  NO_TABLE_SAID = 'the SQL does not say which table it comes from';
  JOIN_WORDS: array[0..7] of string = ('JOIN', 'INNER', 'LEFT', 'RIGHT', 'FULL', 'OUTER', 'CROSS', 'NATURAL');

function IsWordChar(pC: Char): Boolean;
begin
  Result := CharInSet(pC, ['A'..'Z', 'a'..'z', '0'..'9', '_', '$', '#']) or (Ord(pC) > Ord(#127));
end;

{ End of the comment that starts at pPos, or pPos when none starts there. }
function SkipComment(const pSql: string; pPos: Integer): Integer;
var
  VEnd: Integer;
begin
  Result := pPos;
  if SameText(Copy(pSql, pPos, 2), '--') then
    VEnd := PosEx(#10, pSql, pPos)
  else if Copy(pSql, pPos, 2) = '/*' then
  begin
    VEnd := PosEx('*/', pSql, pPos + 1);
    if VEnd > 0 then
      Inc(VEnd);
  end
  else
    Exit;
  Result := if VEnd = 0 then Length(pSql) + 1 else VEnd + 1;
end;

function ReadQuoted(const pSql: string; var pPos: Integer): string;
var
  VQuote: string;
  VStart: Integer;
begin
  VQuote := Copy(pSql, pPos, 1);
  VStart := pPos + 1;
  Inc(pPos);
  while (pPos <= Length(pSql)) and ((Copy(pSql, pPos, 1) <> VQuote) or (Copy(pSql, pPos + 1, 1) = VQuote)) do
    Inc(pPos, if Copy(pSql, pPos, 1) = VQuote then 2 else 1);
  Result := Copy(pSql, VStart, pPos - VStart).Replace(VQuote + VQuote, VQuote);
  Inc(pPos);
end;

function ReadWord(const pSql: string; var pPos: Integer): string;
var
  VStart: Integer;
begin
  VStart := pPos;
  while (pPos <= Length(pSql)) and IsWordChar(pSql[pPos]) do
    Inc(pPos);
  Result := Copy(pSql, VStart, pPos - VStart);
end;

function Tokenize(const pSql: string): TSqlTokens;
var
  VList: TList<TSqlToken>;
  VToken: TSqlToken;
  VPos, VNext: Integer;
begin
  VList := TList<TSqlToken>.Create;
  try
    VPos := 1;
    while VPos <= Length(pSql) do
    begin
      VNext := SkipComment(pSql, VPos);
      if VNext <> VPos then
      begin
        VPos := VNext;
        Continue;
      end;
      if pSql[VPos] <= ' ' then
      begin
        Inc(VPos);
        Continue;
      end;
      if CharInSet(pSql[VPos], ['"', '''']) then
      begin
        VToken.Kind := if pSql[VPos] = '"' then stkQuoted else stkText;
        VToken.Text := ReadQuoted(pSql, VPos);
      end
      else if IsWordChar(pSql[VPos]) then
      begin
        VToken.Kind := stkWord;
        VToken.Text := ReadWord(pSql, VPos);
      end
      else
      begin
        VToken.Kind := stkSymbol;
        VToken.Text := pSql[VPos];
        Inc(VPos);
      end;
      VList.Add(VToken);
    end;
    Result := VList.ToArray;
  finally
    VList.Free;
  end;
end;

function IsSymbol(const pToken: TSqlToken; const pText: string): Boolean;
begin
  Result := (pToken.Kind = stkSymbol) and (pToken.Text = pText);
end;

function IsKeyword(const pToken: TSqlToken; const pWords: array of string): Boolean;
begin
  Result := (pToken.Kind = stkWord) and MatchText(pToken.Text, pWords);
end;

{ A quoted name, or a word that is not a number. }
function IsName(const pToken: TSqlToken): Boolean;
begin
  Result := (pToken.Kind = stkQuoted) or ((pToken.Kind = stkWord) and (not CharInSet(pToken.Text[1], ['0'..'9'])));
end;

{ Index of the first token at parenthesis depth 0 that is one of pWords, from pFrom; Length when none. }
function FindAtDepthZero(const pTokens: TSqlTokens; pFrom: Integer; const pWords: array of string): Integer;
var
  VDepth: Integer;
begin
  VDepth := 0;
  Result := pFrom;
  while Result < Length(pTokens) do
  begin
    if IsSymbol(pTokens[Result], OPEN_PAREN) then
      Inc(VDepth)
    else if IsSymbol(pTokens[Result], CLOSE_PAREN) then
      Dec(VDepth)
    else if (VDepth = 0) and IsKeyword(pTokens[Result], pWords) then
      Exit;
    Inc(Result);
  end;
end;

{ Splits a token run at depth-0 commas. }
function SplitItems(const pTokens: TSqlTokens): TArray<TSqlTokens>;
var
  VDepth, VStart, VI: Integer;
begin
  Result := nil;
  VDepth := 0;
  VStart := 0;
  for VI := 0 to High(pTokens) do
    if IsSymbol(pTokens[VI], OPEN_PAREN) then
      Inc(VDepth)
    else if IsSymbol(pTokens[VI], CLOSE_PAREN) then
      Dec(VDepth)
    else if (VDepth = 0) and IsSymbol(pTokens[VI], COMMA) then
    begin
      Result := Result + [Copy(pTokens, VStart, VI - VStart)];
      VStart := VI + 1;
    end;
  Result := Result + [Copy(pTokens, VStart, Length(pTokens) - VStart)];
end;

{ Reads `name` or `qualifier.name` (or `qualifier.*`) at the start of pItem; returns the tokens used, 0 = neither. }
function ReadColumnRef(const pItem: TSqlTokens; var pOut: TDfmrSqlItem): Integer;
var
  VQualified: Boolean;
begin
  Result := 0;
  if Length(pItem) = 0 then
    Exit;
  VQualified := (Length(pItem) >= QUALIFIED_TOKENS) and IsName(pItem[0]) and IsSymbol(pItem[1], DOT);
  if VQualified then
  begin
    pOut.Qualifier := pItem[0].Text;
    Result := 2;
  end;
  pOut.Star := IsSymbol(pItem[Result], STAR);
  if pOut.Star or (IsName(pItem[Result]) and (VQualified or (not IsKeyword(pItem[Result], VALUE_WORDS)))) then
  begin
    pOut.Column := pItem[Result].Text;
    Inc(Result);
  end
  else
    Result := 0;
end;

function ReadItem(const pItem: TSqlTokens): TDfmrSqlItem;
var
  VUsed, VLast: Integer;
  VTail: TSqlTokens;
begin
  Result := Default(TDfmrSqlItem);
  VUsed := ReadColumnRef(pItem, Result);
  VTail := Copy(pItem, VUsed, Length(pItem) - VUsed);
  if (Length(VTail) > 0) and IsKeyword(VTail[0], ['AS']) then
    VTail := Copy(VTail, 1, Length(VTail) - 1);
  if (VUsed > 0) and (Length(VTail) = 0) then
  begin
    Result.Plain := not Result.Star;
    Result.OutName := Result.Column;
    Exit;
  end;
  if (VUsed > 0) and (Length(VTail) = 1) and IsName(VTail[0]) and (not Result.Star) then
  begin
    Result.Plain := True;
    Result.OutName := VTail[0].Text;
    Exit;
  end;
  { an expression: only a trailing name after a complete operand is its alias }
  Result := Default(TDfmrSqlItem);
  VLast := High(pItem);
  if (VLast > 0) and IsName(pItem[VLast]) and ((pItem[VLast - 1].Kind <> stkSymbol) or IsSymbol(pItem[VLast - 1], CLOSE_PAREN)) then
    Result.OutName := pItem[VLast].Text;
end;

{ Reads one table of the FROM clause: name [DOT extension] [[AS] alias]. }
function ReadTable(const pTokens: TSqlTokens; out pTable: TDfmrSqlTable; out pReason: string): Boolean;
var
  VPos: Integer;
begin
  pTable := Default(TDfmrSqlTable);
  pReason := '';
  if (Length(pTokens) > 0) and IsSymbol(pTokens[0], OPEN_PAREN) then
    pReason := 'the SQL reads a derived table'
  else if (Length(pTokens) = 0) or (not IsName(pTokens[0])) then
    pReason := 'the SQL names its table by a macro or an expression';
  if pReason <> '' then
    Exit(False);
  pTable.Name := CleanTableName(pTokens[0].Text);
  VPos := 1;
  if (Length(pTokens) > 2) and IsSymbol(pTokens[1], DOT) and IsKeyword(pTokens[2], TABLE_EXTENSIONS) then
    Inc(VPos, 2);
  if (VPos < Length(pTokens)) and IsSymbol(pTokens[VPos], DOT) then
  begin
    pReason := 'the SQL qualifies its table name';
    Exit(False);
  end;
  if (VPos < Length(pTokens)) and IsKeyword(pTokens[VPos], ['AS']) then
    Inc(VPos);
  if (VPos < Length(pTokens)) and IsName(pTokens[VPos]) and (not IsKeyword(pTokens[VPos], ['ON', 'USING'])) then
    pTable.Alias := pTokens[VPos].Text
  else if (VPos < Length(pTokens)) and IsSymbol(pTokens[VPos], OPEN_PAREN) then
    pReason := 'the SQL selects from a stored procedure';
  Result := pReason = '';
end;

{ The FROM clause: pieces between depth-0 commas and JOIN words. pConditions receives the token run of every ON. }
function ReadFrom(const pTokens: TSqlTokens; var pSource: TDfmrSqlSource; var pConditions: TArray<TSqlTokens>): Boolean;
var
  VItem, VPiece: TSqlTokens;
  VStart, VNext, VOn: Integer;
  VTable: TDfmrSqlTable;
begin
  for VItem in SplitItems(pTokens) do
  begin
    VStart := 0;
    while VStart <= Length(VItem) do
    begin
      VNext := FindAtDepthZero(VItem, VStart, JOIN_WORDS);  // dl:ok index-possibly-out-of-range@3e33 -- REVIEWED 2026-11-23 TT-DFMREAD: VNext is tested against Length(VItem) in the same condition
      VPiece := Copy(VItem, VStart, VNext - VStart);
      if not ReadTable(VPiece, VTable, pSource.Reason) then
        Exit(False);
      VOn := FindAtDepthZero(VPiece, 0, ['ON']);
      if VOn < Length(VPiece) then
        pConditions := pConditions + [Copy(VPiece, VOn + 1, Length(VPiece) - VOn - 1)];
      pSource.Tables := pSource.Tables + [VTable];
      while (VNext < Length(VItem)) and IsKeyword(VItem[VNext], JOIN_WORDS) do
        Inc(VNext);
      if VNext >= Length(VItem) then
        Break;
      VStart := VNext;
    end;
  end;
  Result := True;
end;

{ Number of tokens of the value after FIRST / SKIP: n, ?, :param or a parenthesised expression. }
function RowCountTokens(const pTokens: TSqlTokens; pFrom: Integer): Integer;
var
  VDepth: Integer;
begin
  Result := 1;
  if pFrom >= Length(pTokens) then
    Exit;
  if IsSymbol(pTokens[pFrom], ':') then
    Exit(2);
  if not IsSymbol(pTokens[pFrom], OPEN_PAREN) then
    Exit;
  VDepth := 1;
  while (VDepth > 0) and (pFrom + Result < Length(pTokens)) do
  begin
    if IsSymbol(pTokens[pFrom + Result], OPEN_PAREN) then
      Inc(VDepth)
    else if IsSymbol(pTokens[pFrom + Result], CLOSE_PAREN) then
      Dec(VDepth);
    Inc(Result);
  end;
end;

{ First token after SELECT that belongs to the select list: DISTINCT / ALL / FIRST n / SKIP n are skipped. }
function SelectListStart(const pTokens: TSqlTokens): Integer;
begin
  Result := 1;
  while Result < Length(pTokens) do
    if IsKeyword(pTokens[Result], ['DISTINCT', 'ALL']) then
      Inc(Result)
    else if IsKeyword(pTokens[Result], ['FIRST', 'SKIP']) then
      Inc(Result, 1 + RowCountTokens(pTokens, Result + 1))
    else
      Break;
end;

{ A macro (&NAME, !NAME) among the first pCount tokens: the list or the tables are not all in the text. }
function HasMacro(const pTokens: TSqlTokens; pCount: Integer): Boolean;
var
  VI: Integer;
begin
  Result := False;
  for VI := 0 to pCount - 2 do
    if (IsSymbol(pTokens[VI], '&') or IsSymbol(pTokens[VI], '!')) and IsName(pTokens[VI + 1]) then
      Exit(True);
end;

{ A column name that repeats without an alias names a field `NAME_1`, `NAME_2`, ... in list order (BDE and FireDAC
  both name the second `P0` of `Po.P0, Pt.P0` P0_1). }
procedure NameRepeats(var pItems: TArray<TDfmrSqlItem>);
var
  VI, VJ, VSeen: Integer;
  VBare: TArray<Boolean>;
begin
  SetLength(VBare, Length(pItems));
  for VI := 0 to High(pItems) do
    VBare[VI] := (not pItems[VI].Star) and (pItems[VI].OutName <> '') and SameText(pItems[VI].OutName, pItems[VI].Column);
  for VI := 1 to High(pItems) do
  begin
    if not VBare[VI] then
      Continue;
    VSeen := 0;
    for VJ := 0 to VI - 1 do
      if VBare[VJ] and SameText(pItems[VJ].Column, pItems[VI].Column) then
        Inc(VSeen);
    if VSeen > 0 then
      pItems[VI].OutName := pItems[VI].OutName + '_' + IntToStr(VSeen);
  end;
end;

{ Index of the FROM entry a qualifier names: its alias, else the table name of an entry without an alias; -1 = none or
  more than one. }
function FromEntry(const pSource: TDfmrSqlSource; const pQualifier: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pSource.Tables) do
    if SameText(pSource.Tables[VI].Alias, pQualifier) then
      Exit(VI);
  for VI := 0 to High(pSource.Tables) do
    if (pSource.Tables[VI].Alias = '') and SameText(pSource.Tables[VI].Name, CleanTableName(pQualifier)) then
    begin
      if Result >= 0 then
        Exit(-1);
      Result := VI;
    end;
end;

{ pTokens without the parentheses that enclose all of it. }
function Unwrapped(const pTokens: TSqlTokens): TSqlTokens;
var
  VDepth, VI: Integer;
  VWhole: Boolean;
begin
  Result := pTokens;
  while (Length(Result) >= 2) and IsSymbol(Result[0], OPEN_PAREN) and IsSymbol(Result[High(Result)], CLOSE_PAREN) do
  begin
    VDepth := 0;
    VWhole := True;
    for VI := 0 to High(Result) - 1 do
    begin
      if IsSymbol(Result[VI], OPEN_PAREN) then
        Inc(VDepth)
      else if IsSymbol(Result[VI], CLOSE_PAREN) then
        Dec(VDepth);
      if VDepth = 0 then
      begin
        VWhole := False;
        Break;
      end;
    end;
    if not VWhole then
      Exit;
    Result := Copy(Result, 1, Length(Result) - 2);
  end;
end;

{ Splits a condition at its depth-0 AND words; nil when it has a depth-0 OR (a conjunct of `A AND B OR C` is not true
  on every row). }
function Conjuncts(const pTokens: TSqlTokens): TArray<TSqlTokens>;
var
  VDepth, VStart, VI: Integer;
begin
  Result := nil;
  VDepth := 0;
  VStart := 0;
  for VI := 0 to High(pTokens) do
    if IsSymbol(pTokens[VI], OPEN_PAREN) then
      Inc(VDepth)
    else if IsSymbol(pTokens[VI], CLOSE_PAREN) then
      Dec(VDepth)
    else if (VDepth = 0) and IsKeyword(pTokens[VI], ['OR']) then
      Exit(nil)
    else if (VDepth = 0) and IsKeyword(pTokens[VI], ['AND']) then
    begin
      Result := Result + [Copy(pTokens, VStart, VI - VStart)];
      VStart := VI + 1;
    end;
  Result := Result + [Copy(pTokens, VStart, Length(pTokens) - VStart)];
end;

{ Adds every `q1.c1 = q2.c2` conjunct of a condition between two different FROM entries. }
procedure AddEqualities(var pSource: TDfmrSqlSource; const pCondition: TSqlTokens; pWhere: Boolean);
const
  EQUALITY_TOKENS = 7; // q . c = q . c
  EQUALS_AT = 3;
  RIGHT_AT = 4;
var
  VConjunct, VPart: TSqlTokens;
  VJoin: TDfmrSqlJoin;
  VLeft, VRight: Integer;
begin
  for VConjunct in Conjuncts(Unwrapped(pCondition)) do
  begin
    VPart := Unwrapped(VConjunct);
    if (Length(VPart) <> EQUALITY_TOKENS) or (not IsName(VPart[0])) or (not IsSymbol(VPart[1], DOT)) or (not IsName(VPart[2]))
      or (not IsSymbol(VPart[EQUALS_AT], '=')) or (not IsName(VPart[RIGHT_AT])) or (not IsSymbol(VPart[RIGHT_AT + 1], DOT))
      or (not IsName(VPart[RIGHT_AT + 2])) then
      Continue;
    VLeft := FromEntry(pSource, VPart[0].Text);
    VRight := FromEntry(pSource, VPart[RIGHT_AT].Text);
    if (VLeft < 0) or (VRight < 0) or (VLeft = VRight) then
      Continue;
    VJoin.LeftTable := pSource.Tables[VLeft].Name;
    VJoin.LeftAlias := VPart[0].Text;
    VJoin.LeftColumn := UpperCase(VPart[2].Text);
    VJoin.RightTable := pSource.Tables[VRight].Name;
    VJoin.RightAlias := VPart[RIGHT_AT].Text;
    VJoin.RightColumn := UpperCase(VPart[RIGHT_AT + 2].Text);
    VJoin.InWhere := pWhere;
    pSource.Joins := pSource.Joins + [VJoin];
  end;
end;

function ReadSelectSource(const pSql: string): TDfmrSqlSource;
var
  VTokens, VItem: TSqlTokens;
  VConditions: TArray<TSqlTokens>;
  VFirst, VFrom, VEnd, VWhereEnd: Integer;
begin
  VConditions := nil;
  Result := Default(TDfmrSqlSource);
  VTokens := Tokenize(pSql);
  if Length(VTokens) = 0 then
    Result.Reason := 'the SQL is empty in the DFM'
  else if not IsKeyword(VTokens[0], ['SELECT']) then
    Result.Reason := 'the SQL is not a plain SELECT'
  else if FindAtDepthZero(VTokens, 0, ['UNION']) < Length(VTokens) then
    Result.Reason := 'the SQL is a UNION';
  if Result.Reason <> '' then
    Exit;
  VFirst := SelectListStart(VTokens);
  VFrom := FindAtDepthZero(VTokens, VFirst, ['FROM']);
  if VFrom >= Length(VTokens) then
  begin
    Result.Reason := 'the SQL has no FROM';
    Exit;
  end;
  VEnd := FindAtDepthZero(VTokens, VFrom + 1, FROM_END_WORDS);
  while (VEnd > VFrom) and (VEnd = Length(VTokens)) and IsSymbol(VTokens[VEnd - 1], ';') do
  begin
    SetLength(VTokens, Length(VTokens) - 1);
    Dec(VEnd);
  end;
  if ReadFrom(Copy(VTokens, VFrom + 1, VEnd - VFrom - 1), Result, VConditions) and HasMacro(VTokens, VEnd) then
    Result.Reason := 'the SQL has a macro';
  if Result.Reason <> '' then
  begin
    Result.Tables := nil;
    Exit;
  end;
  for VItem in VConditions do
    AddEqualities(Result, VItem, False);
  if (VEnd < Length(VTokens)) and IsKeyword(VTokens[VEnd], ['WHERE']) then  // dl:ok index-possibly-out-of-range@6f1a -- REVIEWED 2026-11-26 XTABLE X3: VEnd is tested against Length(VTokens) in the same condition
  begin
    VWhereEnd := FindAtDepthZero(VTokens, VEnd + 1, WHERE_END_WORDS);
    AddEqualities(Result, Copy(VTokens, VEnd + 1, VWhereEnd - VEnd - 1), True);
  end;
  for VItem in SplitItems(Copy(VTokens, VFirst, VFrom - VFirst)) do
    Result.Items := Result.Items + [ReadItem(VItem)];
  NameRepeats(Result.Items);
end;

function TableOfQualifier(const pSource: TDfmrSqlSource; const pQualifier: string): string;
var
  VTable: TDfmrSqlTable;
begin
  Result := '';
  if (pQualifier = '') and (Length(pSource.Tables) = 1) then
    Exit(pSource.Tables[0].Name);
  if pQualifier = '' then
    Exit;
  for VTable in pSource.Tables do
    if SameText(VTable.Alias, pQualifier) or SameText(VTable.Name, CleanTableName(pQualifier)) then
      Exit(VTable.Name);
end;

{ An Origin property that names a table of the FROM clause and a column: `"X.DB".COL`, `ALIAS."X.DB".COL`, and the
  unquoted `X.DB.COL` (the extension is part of the table name). pBare receives the column of a bare `COL`. }
function OriginColumn(const pSource: TDfmrSqlSource; const pOrigin: string; out pTable, pColumn, pBare: string): Boolean;
var
  VTokens: TSqlTokens;
  VCount, VQualifier: Integer;
  VName: string;
begin
  pTable := '';
  pColumn := '';
  pBare := '';
  VTokens := Tokenize(pOrigin);
  VCount := Length(VTokens);
  if (VCount = 1) and IsName(VTokens[0]) then
    pBare := UpperCase(VTokens[0].Text);
  if (VCount < QUALIFIED_TOKENS) or (not IsName(VTokens[VCount - 1])) or (not IsSymbol(VTokens[VCount - 2], DOT)) then
    Exit(False);
  pColumn := UpperCase(VTokens[VCount - 1].Text);
  VQualifier := VCount - QUALIFIED_TOKENS;
  VName := VTokens[VQualifier].Text;
  if (VQualifier >= 2) and IsKeyword(VTokens[VQualifier], TABLE_EXTENSIONS) and IsSymbol(VTokens[VQualifier - 1], DOT)
    and IsName(VTokens[VQualifier - 2]) then
    VName := VTokens[VQualifier - 2].Text + DOT + VName;
  pTable := TableOfQualifier(pSource, VName);
  Result := pTable <> '';
end;

{ Distinct names, in order. }
function AddTable(const pList: TArray<string>; const pName: string): TArray<string>;
begin
  Result := pList;
  if (pName <> '') and (not MatchText(pName, pList)) then
    Result := Result + [pName];
end;

{ The one table of pTables whose schema facts have pColumn; pReason says why there is none. }
function UniqueHolder(const pTables: TArray<string>; const pColumn: string; const pColumns: TDfmrColumnCheck;
  out pTable, pReason: string): Boolean;
var
  VTable: string;
  VHolders, VUnknown: TArray<string>;
  VKnown: Boolean;
begin
  pTable := '';
  pReason := '';
  VHolders := nil;
  VUnknown := nil;
  for VTable in pTables do
  begin
    VKnown := False;
    if Assigned(pColumns) and pColumns(VTable, pColumn, VKnown) then
      VHolders := VHolders + [VTable];
    if not VKnown then
      VUnknown := VUnknown + [VTable];
  end;
  if not Assigned(pColumns) then
    pReason := NO_TABLE_SAID
  else if Length(VHolders) > 1 then
    pReason := Format('%s is in %d tables of the FROM: %s', [pColumn, Length(VHolders), string.Join(' ', VHolders)])
  else if Length(VUnknown) > 0 then
    pReason := 'not qualified and the repository has no schema facts for ' + string.Join(' ', VUnknown)
  else if Length(VHolders) = 0 then
    pReason := Format('%s is in no table of the FROM', [pColumn]);
  Result := pReason = '';
  if Result then
    pTable := VHolders[0];
end;

function FromTables(const pSource: TDfmrSqlSource): TArray<string>;
var
  VTable: TDfmrSqlTable;
begin
  Result := nil;
  for VTable in pSource.Tables do
    Result := AddTable(Result, VTable.Name);
end;

function SqlFieldColumn(const pSource: TDfmrSqlSource; const pField, pOrigin: string;
  out pTable, pColumn, pReason: string): Boolean;
begin
  Result := SqlFieldColumn(pSource, pField, pOrigin, nil, pTable, pColumn, pReason);
end;

function SqlFieldColumn(const pSource: TDfmrSqlSource; const pField, pOrigin: string; const pColumns: TDfmrColumnCheck;
  out pTable, pColumn, pReason: string): Boolean;
var
  VItem: TDfmrSqlItem;
  VStars: TArray<string>;
  VHasOrigin: Boolean;
  VOriginTable, VOriginColumn, VBare: string;
begin
  pTable := '';
  pColumn := '';
  pReason := '';
  VStars := nil;
  VHasOrigin := OriginColumn(pSource, pOrigin, VOriginTable, VOriginColumn, VBare);
  for VItem in pSource.Items do
  begin
    if VItem.Star then
    begin
      VStars := if VItem.Qualifier = '' then FromTables(pSource) else AddTable(VStars, TableOfQualifier(pSource, VItem.Qualifier));
      Continue;
    end;
    if not SameText(VItem.OutName, pField) then
      Continue;
    if not VItem.Plain then
    begin
      pReason := 'computed by the SQL';
      Exit(False);
    end;
    pColumn := UpperCase(VItem.Column);
    pTable := TableOfQualifier(pSource, VItem.Qualifier);
    if (pTable = '') and (VItem.Qualifier = '') and VHasOrigin then
      pTable := VOriginTable
    else if (pTable = '') and (VItem.Qualifier = '') and (not UniqueHolder(FromTables(pSource), pColumn, pColumns, pTable, pReason)) then
      Exit(False);
    if pTable = '' then
      Continue;
    if VHasOrigin and ((not SameText(pTable, VOriginTable)) or (not SameText(pColumn, VOriginColumn))) then
    begin
      pReason := Format('conflict: the select list says %s.%s, Origin says %s.%s', [pTable, pColumn, VOriginTable, VOriginColumn]);
      pTable := '';
      pColumn := '';
      Exit(False);
    end;
    Exit(True);
  end;
  pTable := '';
  pColumn := '';
  if VHasOrigin and ((Length(VStars) = 0) or MatchText(VOriginTable, VStars)) then
  begin
    pTable := VOriginTable;
    pColumn := VOriginColumn;
  end
  else if VHasOrigin then
    pReason := Format('conflict: the star reads %s, Origin says %s.%s', [string.Join(' ', VStars), VOriginTable, VOriginColumn])
  else
  begin
    pColumn := UpperCase(if VBare <> '' then VBare else pField);
    if Length(VStars) = 1 then
      pTable := VStars[0]
    else if Length(VStars) > 1 then
      UniqueHolder(VStars, pColumn, pColumns, pTable, pReason)
    else if VBare <> '' then
      UniqueHolder(FromTables(pSource), pColumn, pColumns, pTable, pReason);
  end;
  Result := pTable <> '';
  if Result then
    Exit;
  pColumn := '';
  if pReason = '' then
    pReason := NO_TABLE_SAID;
end;

function CleanTableName(const pName: string): string;
var
  VDot: Integer;
begin
  Result := Trim(pName).DeQuotedString('"').Replace('/', '\');
  Result := Result.Substring(Result.LastIndexOfAny(['\', ':']) + 1);
  VDot := Result.LastIndexOf(DOT);
  if (VDot > 0) and MatchText(Result.Substring(VDot + 1), TABLE_EXTENSIONS) then
    Result := Result.Substring(0, VDot);
  Result := UpperCase(Trim(Result));
end;

end.
