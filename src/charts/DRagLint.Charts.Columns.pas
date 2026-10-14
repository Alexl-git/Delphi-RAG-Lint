unit DRagLint.Charts.Columns;

(* THE column state: whether COL is a column of table T, and on what evidence, decided in
  ONE place so consumers, feeds-from and lands-where cannot disagree. Each routine is a port
  of the named function in charts\src\Emit-Common.ps1 (line numbers of 2026-10-13); the
  PowerShell output is the reference (spec P3/P4), so every label is reproduced verbatim.

  States, in precedence order: yes (extracted from the NEWEST declaration), quoted (a quoted
  identifier in the newest declaration's FRESH source), older (extracted only from an older
  declaration), server-sql (the caller's own SQL for T names it), stale (the script differs
  from the indexed copy, so the quoted scan was not run: NOT known), no. *)

interface

uses
  DRagLint.Charts.Sql;

type
  /// <summary>Where the caller's own server SQL for T names the column (the PS -ServerSqlHit).</summary>
  TServerSqlHit = record
    /// <summary>False for the PS $null (no hit).</summary>
    Present: Boolean;
    /// <summary>The file of the SQL text.</summary>
    Path   : string;
    /// <summary>Its line.</summary>
    Line   : Integer;
    /// <summary>The routine that holds it.</summary>
    Routine: string;
    /// <summary>No hit.</summary>
    /// <returns>A record with Present False.</returns>
    class function None: TServerSqlHit; static;
    /// <summary>A hit.</summary>
    /// <param name="pPath">File.</param>
    /// <param name="pLine">Line.</param>
    /// <param name="pRoutine">Routine.</param>
    /// <returns>A record with Present True.</returns>
    class function Make(const pPath: string; pLine: Integer; const pRoutine: string): TServerSqlHit; static;
  end;

  /// <summary>A quoted identifier opening a line of a table's newest declaration. Port of the
  /// Find-QuotedColumn result.</summary>
  TQuotedColumn = record
    /// <summary>False for the PS $null (scanned, nothing found).</summary>
    Found: Boolean;
    /// <summary>The script differs from the indexed copy; NOT scanned.</summary>
    Stale: Boolean;
    /// <summary>1-based line of the hit; 0 otherwise.</summary>
    Line : Integer;
    /// <summary>The stripped line, PS-trimmed; '' otherwise.</summary>
    Text : string;
  end;

  /// <summary>THE column state. Port of the Get-SqlColumnState result.</summary>
  TSqlColumnState = record
    /// <summary>The table's name as declared.</summary>
    Table     : string;
    /// <summary>The column, upper case.</summary>
    Column    : string;
    /// <summary>yes | quoted | older | server-sql | stale | no.</summary>
    State     : string;
    /// <summary>True for yes, quoted, older and server-sql.</summary>
    IsColumn  : Boolean;
    /// <summary>The anchor's file.</summary>
    Path      : string;
    /// <summary>The anchor's line.</summary>
    Line      : Integer;
    /// <summary>The quoted source line (quoted state only).</summary>
    Text      : string;
    /// <summary>The grade and evidence every verb prints (the PS Label).</summary>
    Caption   : string;
    /// <summary>An older declaration that extracts it; '' when none (the PS $null).</summary>
    OlderPath : string;
    /// <summary>That declaration's column line; 0 when none.</summary>
    OlderLine : Integer;
    /// <summary>'hit' | 'none' | 'stale' | '' when the scan was not needed.</summary>
    QuotedScan: string;
  end;

/// <summary>A QUOTED identifier "COL" opening a line of a table's newest declaration, from fresh source.</summary>
/// <param name="pCatalog">The SQL catalogue (index, reader, stripped lines).</param>
/// <param name="pTable">The table.</param>
/// <param name="pCol">The column (upper case).</param>
/// <returns>Found with the line and text; Stale when the script is not the indexed copy.</returns>
/// <remarks>Port of Find-QuotedColumn (Emit-Common.ps1:1137): scans from the line after the
/// declaration to its ';' terminator (or 400 lines), regex ^\s*"COL"\s, case-insensitive.</remarks>
function FindQuotedColumn(pCatalog: TSqlCatalog; pTable: TSqlTable; const pCol: string): TQuotedColumn;

/// <summary>Whether pCol is a column of pTable, and on what evidence.</summary>
/// <param name="pCatalog">The SQL catalogue (its index answers the sql_column line lookups).</param>
/// <param name="pSet">The table set to judge against (the catalogue's, or a doctored copy).</param>
/// <param name="pTable">A table of pSet (any case).</param>
/// <param name="pCol">The column (any case).</param>
/// <param name="pServerHit">The caller's server SQL naming it, or TServerSqlHit.None.</param>
/// <param name="pSqlSearched">What SQL the caller searched; '' when it names none.</param>
/// <returns>The state; see the unit header for the precedence.</returns>
/// <exception cref="EChartsIndex">pTable is not in pSet.</exception>
/// <remarks>Port of Get-SqlColumnState (Emit-Common.ps1:1165).</remarks>
function SqlColumnState(pCatalog: TSqlCatalog; pSet: TSqlTableSet; const pTable, pCol: string;
  const pServerHit: TServerSqlHit; const pSqlSearched: string): TSqlColumnState;

/// <summary>The names in pCols that table pTable does NOT hold, by THE column test.</summary>
/// <param name="pCatalog">The SQL catalogue.</param>
/// <param name="pSet">The table set.</param>
/// <param name="pTable">A table of pSet.</param>
/// <param name="pCols">Candidate column names.</param>
/// <returns>The names not held, in input order; a stale (unknown) column is not held.</returns>
/// <remarks>Port of Get-ColumnsNotHeld (Emit-Common.ps1:1129): the cheap test first, the source
/// scan only for a name it rejects.</remarks>
function ColumnsNotHeld(pCatalog: TSqlCatalog; pSet: TSqlTableSet; const pTable: string;
  const pCols: TArray<string>): TArray<string>;

/// <summary>feeds-from's column-hop label: a quoted column keeps its quotes.</summary>
/// <param name="pState">A column state.</param>
/// <returns>'column "COL"' for the quoted state, else 'column COL'.</returns>
/// <remarks>Port of Get-ColumnHopLabel (Emit-Common.ps1:1091).</remarks>
function ColumnHopLabel(const pState: TSqlColumnState): string;

/// <summary>The name a chart PRINTS for a column state.</summary>
/// <param name="pState">yes | older | no | stale | anything else.</param>
/// <returns>column | older-only | not-a-column | [stale source] | pState unchanged.</returns>
/// <remarks>Port of Get-ColumnStateName (Emit-Common.ps1:1155). PS trap closed: `switch` on a
/// string is case-insensitive.</remarks>
function ColumnStateName(const pState: string): string;

/// <summary>lands-where's row for a property the SQL index does not extract (state no).</summary>
/// <param name="pProp">The property.</param>
/// <param name="pTable">The table.</param>
/// <param name="pCaption">The column state's label.</param>
/// <param name="pServerSearched">The DataService class searched; '' when none was.</param>
/// <returns>The sentence; "computed or UI-only" only when the server's SQL was searched.</returns>
/// <remarks>Port of Format-NotAColumnNote (Emit-Common.ps1:1233).</remarks>
function FormatNotAColumnNote(const pProp, pTable, pCaption, pServerSearched: string): string;

implementation

uses
  System.SysUtils
  , System.RegularExpressions
  , DRagLint.Charts.Index
  , DRagLint.Charts.Source
  , DRagLint.Charts.Text
  ;

const
  STATE_YES = 'yes';
  STATE_QUOTED = 'quoted';
  STATE_OLDER = 'older';
  STATE_SERVER = 'server-sql';
  STATE_STALE = 'stale';
  STATE_NO = 'no';
  SCAN_HIT = 'hit';
  SCAN_NONE = 'none';
  SCAN_STALE = 'stale';
  { the PS window when the declaration's ';' is not found }
  QUOTED_SCAN_LINES = 400;
  { .NET \s over Latin-1 text (see DRagLint.Charts.Sql) }
  PS_WS = '[\s\x{85}\x{A0}]';

class function TServerSqlHit.None: TServerSqlHit;
begin
  Result:= Default(TServerSqlHit);
end;

class function TServerSqlHit.Make(const pPath: string; pLine: Integer; const pRoutine: string): TServerSqlHit;
begin
  Result.Present:= True;
  Result.Path:= pPath;
  Result.Line:= pLine;
  Result.Routine:= pRoutine;
end;

function FindQuotedColumn(pCatalog: TSqlCatalog; pTable: TSqlTable; const pCol: string): TQuotedColumn;
begin
  Result:= Default(TQuotedColumn);
  if not pCatalog.Reader.SourceFresh(pTable.Path) then
  begin
    Result.Stale:= True;
    Exit;
  end;
  var Lines:= pCatalog.StrippedSqlLines(pCatalog.Reader.ReadPath(pTable.Path));
  var E:= FindSqlBodyEnd(Lines, pTable.Line, ';', False);
  var Last:= E.EndLine;
  if not E.Found then
  begin
    Last:= pTable.Line + QUOTED_SCAN_LINES;
    if Length(Lines) < Last then
      Last:= Length(Lines);
  end;
  var Rx:= TRegEx.Create('^' + PS_WS + '*"' + TRegEx.Escape(pCol) + '"' + PS_WS, [roIgnoreCase]);
  for var I:= pTable.Line + 1 to Last do
    if Rx.IsMatch(Lines[I - 1]) then
    begin
      Result.Found:= True;
      Result.Line:= I;
      Result.Text:= PsTrim(Lines[I - 1]);
      Exit;
    end;
end;

{ The sql_column line of pCol under the declaration pDeclId; 0 when the query has no row. }
function ColumnLine(pCatalog: TSqlCatalog; pDeclId: Integer; const pCol: string): Integer;
begin
  Result:= 0;
  var Rows:= pCatalog.Index.Query(Format('SELECT start_line AS line FROM symbols WHERE kind = ''sql_column'' ' +
    'AND parent_id = %d AND UPPER(name) = UPPER(''%s'')', [pDeclId, TChartsIndex.SqlText(pCol)]));
  try
    if Rows.Count > 0 then
      Result:= Rows[0].I('line');
  finally
    Rows.Free;
  end;
end;

{ The older declaration that extracts the column, with its own column line (THE KNOWN GAP). }
procedure ApplyOlder(pCatalog: TSqlCatalog; pTable: TSqlTable; const pCol, pColUpper: string; var pState: TSqlColumnState);
var
  Older: TOlderColumn;
begin
  if not pTable.TryOlder(pColUpper, Older) then
    Exit;
  pState.OlderPath:= Older.Path;
  pState.OlderLine:= Older.Line;
  for var D in pTable.Declarations do
    if SameText(D.Path, Older.Path) and (D.Line = Older.Line) then
    begin
      var L:= ColumnLine(pCatalog, D.Id, pCol);
      if L <> 0 then
        pState.OlderLine:= L;
      Break;
    end;
end;

function SqlColumnState(pCatalog: TSqlCatalog; pSet: TSqlTableSet; const pTable, pCol: string;
  const pServerHit: TServerSqlHit; const pSqlSearched: string): TSqlColumnState;
begin
  var Tbl:= pSet.Table(pTable);
  if Tbl = nil then
    raise EChartsIndex.CreateFmt('Get-SqlColumnState: no table %s in the SQL index -- the caller checks the table first', [pTable]);
  var Cu:= pCol.ToUpperInvariant;
  var Nf:= FileNameOf(Tbl.Path);
  var Decls:= Length(Tbl.Declarations);
  var Newest:= Format('%d columns extracted from the newest of %d declaration(s), %s:%d', [Length(Tbl.ColumnNames), Decls, Nf, Tbl.Line]);
  Result:= Default(TSqlColumnState);
  Result.Table:= Tbl.Name;
  Result.Column:= Cu;
  Result.Path:= Tbl.Path;
  Result.Line:= Tbl.Line;
  if Tbl.HasColumn(pCol) then
  begin
    var L:= ColumnLine(pCatalog, Tbl.Id, pCol);
    if L <> 0 then
      Result.Line:= L;
    Result.State:= STATE_YES;
    Result.IsColumn:= True;
    Result.Caption:= Format('[certain] a column of the newest of %d declaration(s), %s', [Decls, Nf]);
    Exit;
  end;
  ApplyOlder(pCatalog, Tbl, pCol, Cu, Result);
  var Q:= FindQuotedColumn(pCatalog, Tbl, Cu);
  Result.QuotedScan:= if Q.Stale then SCAN_STALE else if Q.Found then SCAN_HIT else SCAN_NONE;
  var OlderNote:= '';
  if Result.OlderPath <> '' then
    OlderNote:= Format('an older declaration (%s:%d) extracts it unquoted', [FileNameOf(Result.OlderPath), Result.OlderLine]);
  if Result.QuotedScan = SCAN_HIT then
  begin
    Result.State:= STATE_QUOTED;
    Result.IsColumn:= True;
    Result.Line:= Q.Line;
    Result.Text:= Q.Text;
    Result.Caption:= Format('[inferred -- source scan] a QUOTED identifier in the newest declaration (%s:%d) ' +
      'that the SQL index did not extract as a column', [Nf, Q.Line]) + (if OlderNote <> '' then '; ' + OlderNote else '');
    Exit;
  end;
  var QuotedPart:= if Result.QuotedScan = SCAN_STALE then
    Nf + ' differs from the indexed copy, so it was not scanned for a quoted identifier [stale source]'
  else 'nor a quoted identifier in that declaration';
  if Result.OlderPath <> '' then
  begin
    Result.State:= STATE_OLDER;
    Result.IsColumn:= True;
    Result.Path:= Result.OlderPath;
    Result.Line:= Result.OlderLine;
    Result.Caption:= Format('column extracted ONLY from an older declaration (%s:%d); not extracted from the newest (%s); %s',
      [FileNameOf(Result.OlderPath), Result.OlderLine, Newest, QuotedPart]);
    Exit;
  end;
  if pServerHit.Present then
  begin
    Result.State:= STATE_SERVER;
    Result.IsColumn:= True;
    Result.Path:= pServerHit.Path;
    Result.Line:= pServerHit.Line;
    Result.Caption:= Format('[inferred] not extracted as a column by the SQL index (%s); %s -- but the SQL for %s ' +
      'in %s names it: the scripts lag the schema', [Newest, QuotedPart, Tbl.Name, pServerHit.Routine]);
    Exit;
  end;
  if Result.QuotedScan = SCAN_STALE then
  begin
    Result.State:= STATE_STALE;
    Result.Caption:= Format('[stale source] not extracted as a column by the SQL index (%s); %s differs from the indexed copy, ' +
      'so it was not scanned for a quoted identifier -- whether %s is a column of %s is NOT known', [Newest, Nf, Cu, Tbl.Name]);
    Exit;
  end;
  Result.State:= STATE_NO;
  Result.Caption:= Format('not extracted as a column by the SQL index (%s); %s', [Newest, QuotedPart]) +
    (if pSqlSearched <> '' then Format('; no SQL for %s in %s names it', [Tbl.Name, pSqlSearched]) else '');
end;

function ColumnsNotHeld(pCatalog: TSqlCatalog; pSet: TSqlTableSet; const pTable: string;
  const pCols: TArray<string>): TArray<string>;
begin
  Result:= [];
  var Tbl:= pSet.Table(pTable);
  for var C in pCols do
    if not Tbl.IsColumn(C) and not SqlColumnState(pCatalog, pSet, pTable, C, TServerSqlHit.None, '').IsColumn then
      Result:= Result + [C];
end;

function ColumnHopLabel(const pState: TSqlColumnState): string;
begin
  Result:= if SameText(pState.State, STATE_QUOTED) then Format('column "%s"', [pState.Column]) else 'column ' + pState.Column;
end;

function ColumnStateName(const pState: string): string;
begin
  if SameText(pState, STATE_YES) then
    Exit('column');
  if SameText(pState, STATE_OLDER) then
    Exit('older-only');
  if SameText(pState, STATE_NO) then
    Exit('not-a-column');
  if SameText(pState, STATE_STALE) then
    Exit('[stale source]');
  Result:= pState;
end;

function FormatNotAColumnNote(const pProp, pTable, pCaption, pServerSearched: string): string;
begin
  if pServerSearched <> '' then
    Exit(Format('%s is not a column of %s -- computed or UI-only: %s; the database side is empty', [pProp, pTable, pCaption]));
  Result:= Format('%s is not extracted as a column of %s: %s; no DataService was searched (no TDataService_%s_SERVER in the ' +
    'SERVER index), so whether it is computed, UI-only or written by server SQL is NOT known', [pProp, pTable, pCaption, pTable]);
end;

end.