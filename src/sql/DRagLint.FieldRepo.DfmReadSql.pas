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

  /// <summary>What a SELECT reads.</summary>
  TDfmrSqlSource = record
    /// <summary>Tables of the FROM clause in order; empty when Reason is set.</summary>
    Tables: TArray<TDfmrSqlTable>;
    /// <summary>Select list.</summary>
    Items: TArray<TDfmrSqlItem>;
    /// <summary>'' = understood; otherwise why the SQL says nothing.</summary>
    Reason: string;
  end;

/// <summary>Reads the FROM clause and the select list of a SELECT.</summary>
/// <param name="pSql">SQL text.</param>
/// <returns>The source; Reason is set for an empty text, a non-SELECT, UNION, WITH, a derived table, a macro in front of
/// the WHERE clause.</returns>
function ReadSelectSource(const pSql: string): TDfmrSqlSource;

/// <summary>Finds the table column a dataset field comes from.</summary>
/// <param name="pSource">The SELECT (Reason '').</param>
/// <param name="pField">The dataset field name.</param>
/// <param name="pOrigin">The persistent field's Origin property (`"Tool.DB".Name`), '' = none.</param>
/// <param name="pTable">Receives the table.</param>
/// <param name="pColumn">Receives the column, upper case.</param>
/// <param name="pReason">Receives why the field has no column ('' when found).</param>
/// <returns>True when the SQL (or an Origin naming a table of the same FROM) states the column.</returns>
function SqlFieldColumn(const pSource: TDfmrSqlSource; const pField, pOrigin: string;
  out pTable, pColumn, pReason: string): Boolean;

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
  { Words that are values, or start an expression, where a column may stand. }
  VALUE_WORDS: array[0..11] of string = ('NULL', 'NOT', 'TRUE', 'FALSE', 'USER', 'CURRENT_DATE', 'CURRENT_TIME', 'CURRENT_TIMESTAMP',
    'CURRENT_USER', 'CURRENT_ROLE', 'LOCALTIME', 'LOCALTIMESTAMP');
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

{ The FROM clause: pieces between depth-0 commas and JOIN words. }
function ReadFrom(const pTokens: TSqlTokens; var pSource: TDfmrSqlSource): Boolean;
var
  VItem: TSqlTokens;
  VStart, VNext: Integer;
  VTable: TDfmrSqlTable;
begin
  for VItem in SplitItems(pTokens) do
  begin
    VStart := 0;
    while VStart <= Length(VItem) do
    begin
      VNext := FindAtDepthZero(VItem, VStart, JOIN_WORDS);  // dl:ok index-possibly-out-of-range@3e33 -- REVIEWED 2026-11-23 TT-DFMREAD: VNext is tested against Length(VItem) in the same condition
      if not ReadTable(Copy(VItem, VStart, VNext - VStart), VTable, pSource.Reason) then
        Exit(False);
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

function ReadSelectSource(const pSql: string): TDfmrSqlSource;
var
  VTokens, VItem: TSqlTokens;
  VFirst, VFrom, VEnd: Integer;
begin
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
  if ReadFrom(Copy(VTokens, VFrom + 1, VEnd - VFrom - 1), Result) and HasMacro(VTokens, VEnd) then
    Result.Reason := 'the SQL has a macro';
  if Result.Reason <> '' then
  begin
    Result.Tables := nil;
    Exit;
  end;
  for VItem in SplitItems(Copy(VTokens, VFirst, VFrom - VFirst)) do
    Result.Items := Result.Items + [ReadItem(VItem)];
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

{ An Origin property that names a table of the FROM clause and a column. }
function OriginColumn(const pSource: TDfmrSqlSource; const pOrigin: string; out pTable, pColumn: string): Boolean;
var
  VTokens: TSqlTokens;
  VCount: Integer;
begin
  pTable := '';
  pColumn := '';
  VTokens := Tokenize(pOrigin);
  VCount := Length(VTokens);
  if (VCount < QUALIFIED_TOKENS) or (not IsName(VTokens[VCount - 1])) or (not IsSymbol(VTokens[VCount - 2], DOT)) then
    Exit(False);
  pColumn := UpperCase(VTokens[VCount - 1].Text);
  pTable := TableOfQualifier(pSource, VTokens[VCount - QUALIFIED_TOKENS].Text);
  Result := pTable <> '';
end;

function SqlFieldColumn(const pSource: TDfmrSqlSource; const pField, pOrigin: string;
  out pTable, pColumn, pReason: string): Boolean;
var
  VItem: TDfmrSqlItem;
  VStar: Boolean;
begin
  pTable := '';
  pColumn := '';
  pReason := '';
  VStar := False;
  for VItem in pSource.Items do
  begin
    VStar := VStar or VItem.Star;
    if VItem.Star or (not SameText(VItem.OutName, pField)) then
      Continue;
    if not VItem.Plain then
    begin
      pReason := 'computed by the SQL';
      Exit(False);
    end;
    pTable := TableOfQualifier(pSource, VItem.Qualifier);
    pColumn := UpperCase(VItem.Column);
    if pTable <> '' then
      Exit(True);
  end;
  if VStar and (Length(pSource.Tables) = 1) then
  begin
    pTable := pSource.Tables[0].Name;
    pColumn := UpperCase(pField);
    Exit(True);
  end;
  Result := OriginColumn(pSource, pOrigin, pTable, pColumn);
  if not Result then
    pReason := 'the SQL does not say which table it comes from';
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
