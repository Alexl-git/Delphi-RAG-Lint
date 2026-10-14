unit DRagLint.Charts.Sql;

{ The SQL-index side of the chart emitters: the collapsed table set, procedure and
  trigger bodies read from the .SQL scripts (the index stores none), and the verb scan
  that names a table after an upper-case SQL verb. Each routine is a port of the named
  function in charts\src\Emit-Common.ps1 (line numbers of 2026-10-13); the PowerShell
  output is the reference (spec P3/P4).

  PS TRAPS CLOSED HERE, once for every routine below:
  * .NET `\s` also matches #$85 and #$A0 (both occur in Latin-1 text) and .NET `\b` / `\w`
    count Latin-1 letters as word characters; PCRE does neither without UCP, so the
    patterns spell those classes out (PS_WS, PS_WORD).
  * `-match` is case-insensitive; [regex]::Match and `-cmatch` are not.
  * PS hashtables, ordered dictionaries and HashSet(OrdinalIgnoreCase) are case-insensitive; every
    dictionary here uses TIStringComparer.Ordinal.
  * Sort-Object (and Sort-Object -Unique) order text case-insensitively and culture-aware:
    CompareGroupKeys. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Charts.Index
  , DRagLint.Charts.Source
  ;

const
  /// <summary>How far a body scan runs before it gives up (the PS -MaxLines default).</summary>
  SQL_BODY_MAX_LINES = 400;

type
  /// <summary>Where a SQL body ends. Port of the Find-SqlBodyEnd result.</summary>
  TSqlBodyEnd = record
    /// <summary>True when the terminator was found.</summary>
    Found  : Boolean;
    /// <summary>1-based terminator line; 0 when not found.</summary>
    EndLine: Integer;
    /// <summary>'' when found, else why not.</summary>
    Reason : string;
  end;

  /// <summary>A trigger or procedure body read from source. Port of the Get-SqlBodyText /
  /// Get-SqlProcBodyText result.</summary>
  TSqlBody = record
    /// <summary>The script differs from the indexed copy; nothing was read.</summary>
    Stale    : Boolean;
    /// <summary>The terminator was found.</summary>
    Found    : Boolean;
    /// <summary>The declaration line.</summary>
    StartLine: Integer;
    /// <summary>The terminator line; 0 when not found.</summary>
    EndLine  : Integer;
    /// <summary>The stripped body, LF-joined; '' when not found (the PS $null).</summary>
    Text     : string;
    /// <summary>The terminator in force (procedures only; '' for triggers and stale files).</summary>
    Term     : string;
    /// <summary>'' when found, else why not.</summary>
    Reason   : string;
  end;

  /// <summary>One table (or procedure) named right after an upper-case SQL verb.</summary>
  TSqlVerbHit = record
    /// <summary>The verb, whitespace collapsed ('DELETE FROM').</summary>
    Verb : string;
    /// <summary>The name as written.</summary>
    Name : string;
    /// <summary>'table' or 'procedure'.</summary>
    Kind : string;
    /// <summary>0-based character offset of the match (the .NET Match.Index).</summary>
    Index: Integer;
  end;

  /// <summary>One CREATE TABLE of a name (a member of a collapsed table).</summary>
  TSqlDeclaration = record
    /// <summary>symbols.id of the sql_table.</summary>
    Id     : Integer;
    /// <summary>The script.</summary>
    Path   : string;
    /// <summary>The declaration line.</summary>
    Line   : Integer;
    /// <summary>Columns the index extracted from this declaration.</summary>
    Columns: Integer;
  end;

  /// <summary>A column only a LOSING (older) declaration extracts.</summary>
  TOlderColumn = record
    /// <summary>The column as extracted.</summary>
    Column: string;
    /// <summary>The newest losing declaration's script that extracts it.</summary>
    Path  : string;
    /// <summary>That declaration's line.</summary>
    Line  : Integer;
  end;

  /// <summary>One table name of the SQL index, collapsed onto its newest declaration.</summary>
  /// <remarks>Port of a Tables entry of Get-SqlTableSet. Owned by its TSqlTableSet.</remarks>
  TSqlTable = class
  private
    FName        : string;
    FId          : Integer;
    FPath        : string;
    FLine        : Integer;
    FDeclarations: TArray<TSqlDeclaration>;
    FColumnNames : TArray<string>;
    FColumns     : TDictionary<string, Boolean>;
    FOlderKeys   : TList<string>;
    FOlder       : TDictionary<string, TOlderColumn>;
  public
    /// <summary>Creates an empty table; the set fills it.</summary>
    constructor Create;
    /// <summary>Frees the column sets.</summary>
    destructor Destroy; override;
    /// <summary>Whether the NEWEST declaration extracts pCol (case-insensitive).</summary>
    /// <param name="pCol">A column name.</param>
    /// <returns>True when extracted.</returns>
    function HasColumn(const pCol: string): Boolean;
    /// <summary>The older-only column keyed by upper-case name, if any.</summary>
    /// <param name="pColUpper">The column, upper-case.</param>
    /// <param name="pOlder">The older declaration that extracts it.</param>
    /// <returns>True when only an older declaration extracts it.</returns>
    function TryOlder(const pColUpper: string; out pOlder: TOlderColumn): Boolean;
    /// <summary>The older-only column keys (upper case) in insertion order.</summary>
    /// <returns>A copy.</returns>
    function OlderKeys: TArray<string>;
    /// <summary>The cheap column test, no source read: extracted from the newest declaration, or from an older one.</summary>
    /// <param name="pCol">A column name (any case).</param>
    /// <returns>True when either extracts it.</returns>
    /// <remarks>Port of Test-IsColumn (Emit-Common.ps1:1117).</remarks>
    function IsColumn(const pCol: string): Boolean;
    /// <summary>A copy of this table with pCol taken OUT of the newest declaration's columns.</summary>
    /// <param name="pCol">The column to remove (case-insensitive, as PS -ne).</param>
    /// <param name="pOlder">An older-only extraction to record for pCol.</param>
    /// <param name="pHasOlder">False: record none (the PS ).</param>
    /// <returns>A NEW table the caller owns.</returns>
    /// <remarks>Port of Copy-SqlTableWithout (Emit-Common.ps1:1077): the test hook that gives a
    /// column the 1.18 extractor's shape so the quoted state can be driven on a fresh script.</remarks>
    function CopyWithout(const pCol: string; const pOlder: TOlderColumn; pHasOlder: Boolean): TSqlTable;
    /// <summary>The winning declaration's name.</summary>
    property Name: string read FName;
    /// <summary>The winning declaration's symbols.id.</summary>
    property Id: Integer read FId;
    /// <summary>The winning declaration's script.</summary>
    property Path: string read FPath;
    /// <summary>The winning declaration's line.</summary>
    property Line: Integer read FLine;
    /// <summary>Every declaration, newest first (mtime, then line).</summary>
    property Declarations: TArray<TSqlDeclaration> read FDeclarations;
    /// <summary>The newest declaration's extracted columns in index order.</summary>
    property ColumnNames: TArray<string> read FColumnNames;
  end;

  /// <summary>Every table name of one SQL index, collapsed. Port of the Get-SqlTableSet result.</summary>
  /// <remarks>Owns its tables. Built by TSqlCatalog.TableSet.</remarks>
  TSqlTableSet = class
  private
    FDb                : string;
    FTables            : TDictionary<string, TSqlTable>;
    FOwned             : TObjectList<TSqlTable>;
    FDoctored          : Boolean;
    FNames             : TArray<string>;
    FDeclarationCount  : Integer;
    FCollapsedNames    : Integer;
    FProcedures        : TDictionary<string, Boolean>;
    FProcedureDeclCount: Integer;
  public
    /// <summary>Creates an empty set for the database pDb.</summary>
    /// <param name="pDb">The SQL index path (the PS .Db).</param>
    constructor Create(const pDb: string);
    /// <summary>Frees the tables.</summary>
    destructor Destroy; override;
    /// <summary>The table named pName (case-insensitive), or nil.</summary>
    /// <param name="pName">A table name.</param>
    /// <returns>The table; not owned by the caller.</returns>
    function Table(const pName: string): TSqlTable;
    /// <summary>Whether pName is a sql_procedure of the index (case-insensitive).</summary>
    /// <param name="pName">A procedure name.</param>
    /// <returns>True when declared.</returns>
    function HasProcedure(const pName: string): Boolean;
    /// <summary>A DOCTORED copy of the set with each 'TABLE.COLUMN' taken out of its table's extracted columns.</summary>
    /// <param name="pTableColumns">'TABLE.COLUMN' names to hide.</param>
    /// <returns>A NEW set the caller owns; it shares the untouched tables with this set, which
    /// must outlive it.</returns>
    /// <exception cref="EChartsIndex">'Hide-ExtractedColumns: &lt;tc&gt; is not an extracted column of
    /// the SQL index' for a name that is not exactly TABLE.COLUMN of an extracted column.</exception>
    /// <remarks>Port of Hide-ExtractedColumns (Emit-Common.ps1:1096), a test hook for the quoted
    /// and older column states.</remarks>
    function HideExtractedColumns(const pTableColumns: TArray<string>): TSqlTableSet;
    /// <summary>True for a HideExtractedColumns copy (its answers must never be cached under Db).</summary>
    property Doctored: Boolean read FDoctored;
    /// <summary>The database the set was read from.</summary>
    property Db: string read FDb;
    /// <summary>Table names, Sort-Object order (CompareGroupKeys).</summary>
    property Names: TArray<string> read FNames;
    /// <summary>sql_table symbols before collapsing.</summary>
    property DeclarationCount: Integer read FDeclarationCount;
    /// <summary>Names declared more than once.</summary>
    property CollapsedNames: Integer read FCollapsedNames;
    /// <summary>sql_procedure symbols (declarations, not names).</summary>
    property ProcedureDeclCount: Integer read FProcedureDeclCount;
  end;

  /// <summary>One procedure declaration with its scanned body. Port of a Get-SqlProcedureSet row.</summary>
  TSqlProcedure = record
    /// <summary>symbols.id.</summary>
    Id    : Integer;
    /// <summary>The procedure name.</summary>
    Name  : string;
    /// <summary>The script.</summary>
    Path  : string;
    /// <summary>The body: Stale, Found, EndLine, Reason, Text.</summary>
    Body  : TSqlBody;
    /// <summary>Tables the body names after an upper-case verb, sorted, unique.</summary>
    Tables: TArray<string>;
    /// <summary>Procedures it executes, sorted, unique.</summary>
    Procs : TArray<string>;
  end;

  /// <summary>One trigger with its table and scanned body. Port of a Get-SqlTriggerSet row.</summary>
  TSqlTrigger = record
    /// <summary>symbols.id.</summary>
    Id         : Integer;
    /// <summary>The trigger name.</summary>
    Name       : string;
    /// <summary>The script.</summary>
    Path       : string;
    /// <summary>The body: Stale, Found, EndLine (Text and Term are not kept by the PS).</summary>
    Body       : TSqlBody;
    /// <summary>The sql_table_ref on the CREATE TRIGGER line; '' when none.</summary>
    Table      : string;
    /// <summary>Table is in the collapsed set.</summary>
    TableKnown : Boolean;
    /// <summary>Distinct NEW./OLD. column names, upper case, sorted.</summary>
    Columns    : TArray<string>;
    /// <summary>Other tables the body names after an upper-case verb, sorted, unique.</summary>
    OtherTables: TArray<string>;
  end;

  /// <summary>The SQL-index catalogue: table set, script bodies, procedure and trigger sets.</summary>
  /// <remarks>Holds the per-run caches the PS kept in $script: variables (one catalogue per
  /// SQL index per run). Neither the index nor the reader is owned; the reader must be bound to
  /// the SAME SQL index (freshness is checked against it) and carry any source overrides
  /// BEFORE the first call. PS difference: Get-SqlTableSet ran Get-CloneDb on its path -- the
  /// caller guards the path before it opens the index. Not thread-safe.</remarks>
  TSqlCatalog = class
  private
    FIndex    : TChartsIndex;
    FReader   : TSourceReader;
    FTableSet : TSqlTableSet;
    FProcs    : TArray<TSqlProcedure>;
    FProcsDone: Boolean;
    FTrigs    : TArray<TSqlTrigger>;
    FTrigsDone: Boolean;
    FStripped : TDictionary<string, TArray<string>>;
    function FreshLines(const pPath: string; pLine: Integer; out pBody: TSqlBody; out pLines: TArray<string>): Boolean;
    function BlankSqlMatch(const pMatch: TMatch): string;
  public
    /// <summary>Creates a catalogue over one SQL index.</summary>
    /// <param name="pIndex">The SQL index; not owned.</param>
    /// <param name="pReader">A source reader over the same index; not owned.</param>
    constructor Create(pIndex: TChartsIndex; pReader: TSourceReader);
    /// <summary>Frees the caches.</summary>
    destructor Destroy; override;
    /// <summary>Every table name collapsed onto its newest declaration, read once.</summary>
    /// <returns>The catalogue's own set; do not free it.</returns>
    /// <remarks>Port of Get-SqlTableSet (Emit-Common.ps1:955). The winner of a name is the
    /// declaration in the newest file (files.mtime_unix), then the latest line; ties keep index
    /// order. A column only a losing declaration extracts is kept as older-only.</remarks>
    function TableSet: TSqlTableSet;
    /// <summary>SQL text with strings and comments blanked, line-preserving.</summary>
    /// <param name="pReadPath">The file to read.</param>
    /// <returns>The lines (shared, do not modify).</returns>
    /// <remarks>Port of Get-StrippedSqlLines (Emit-Common.ps1:1293): one regex,
    /// '[^']*'|/\*[\s\S]*?\*/|--[^\r\n]*, a match without LF becomes spaces, one with LF keeps
    /// its CR/LF; read as Latin-1 (BOM honoured); cached per read path.</remarks>
    function StrippedSqlLines(const pReadPath: string): TArray<string>;
    /// <summary>A TRIGGER body: from the declaration to the first line ending in '^'.</summary>
    /// <param name="pPath">The indexed script.</param>
    /// <param name="pLine">The declaration line.</param>
    /// <param name="pMaxLines">Scan limit.</param>
    /// <returns>The body (Stale when the script is not the indexed copy).</returns>
    /// <remarks>Port of Get-SqlBodyText (Emit-Common.ps1:1331).</remarks>
    function SqlBodyText(const pPath: string; pLine: Integer; pMaxLines: Integer = SQL_BODY_MAX_LINES): TSqlBody;
    /// <summary>A PROCEDURE body: to the first line ending in the SET TERM terminator in force.</summary>
    /// <param name="pPath">The indexed script.</param>
    /// <param name="pLine">The declaration line.</param>
    /// <param name="pMaxLines">Scan limit.</param>
    /// <returns>The body, terminator excluded; not found when ';' is still in force.</returns>
    /// <remarks>Port of Get-SqlProcBodyText (Emit-Common.ps1:1391).</remarks>
    function SqlProcBodyText(const pPath: string; pLine: Integer; pMaxLines: Integer = SQL_BODY_MAX_LINES): TSqlBody;
    /// <summary>Every procedure declaration with its scanned body, read once.</summary>
    /// <returns>The declarations in symbols.id order.</returns>
    /// <remarks>Port of Get-SqlProcedureSet (Emit-Common.ps1:1420); its counts are
    /// computed by the caller from the rows.</remarks>
    function ProcedureSet: TArray<TSqlProcedure>;
    /// <summary>Every trigger with its table and scanned body, read once.</summary>
    /// <returns>The triggers in symbols.id order.</returns>
    /// <remarks>Port of Get-SqlTriggerSet (Emit-Common.ps1:1466).</remarks>
    function TriggerSet: TArray<TSqlTrigger>;
    /// <summary>The SQL index (not owned).</summary>
    property Index: TChartsIndex read FIndex;
    /// <summary>The source reader over the SQL index (not owned).</summary>
    property Reader: TSourceReader read FReader;
  end;

/// <summary>Finds a body's terminator in already-stripped lines.</summary>
/// <param name="pLines">Stripped lines.</param>
/// <param name="pLine">1-based first line.</param>
/// <param name="pTerm">The terminator.</param>
/// <param name="pBareTerm">True: a line that IS pTerm; False: a line that ENDS in it.</param>
/// <param name="pMaxLines">Scan limit.</param>
/// <returns>Found, the 1-based terminator line, and the reason when not found.</returns>
/// <remarks>Port of Find-SqlBodyEnd (Emit-Common.ps1:1356). A line after the first that starts
/// CREATE / RECREATE / ALTER or SET TERM (case-insensitive, -match) ends the search not found.
/// Known approximation: .NET String.EndsWith is culture-sensitive (ICU ignores control
/// characters and U+00AD after the terminator); this compares ordinally.</remarks>
function FindSqlBodyEnd(const pLines: TArray<string>; pLine: Integer; const pTerm: string; pBareTerm: Boolean;
  pMaxLines: Integer = SQL_BODY_MAX_LINES): TSqlBodyEnd;

/// <summary>The statement terminator in force at a line: the last SET TERM above it, else ';'.</summary>
/// <param name="pLines">Stripped lines.</param>
/// <param name="pLine">1-based line.</param>
/// <returns>The one-character terminator.</returns>
/// <remarks>Port of Get-SqlTermAt (Emit-Common.ps1:1374); the regex is case-SENSITIVE as in the PS.</remarks>
function SqlTermAt(const pLines: TArray<string>; pLine: Integer): string;

/// <summary>Tables (and procedures) named IMMEDIATELY after an upper-case SQL verb.</summary>
/// <param name="pText">SQL text; '' gives none.</param>
/// <param name="pSet">The collapsed set: a name must be one of its tables (or procedures for
/// EXECUTE PROCEDURE).</param>
/// <returns>The hits in text order.</returns>
/// <remarks>Port of Get-SqlVerbTables (Emit-Common.ps1:1273). Case-SENSITIVE on purpose (the
/// verb and the name are upper case); a hit is a NAME match, rendered [inferred].</remarks>
function SqlVerbTables(const pText: string; pSet: TSqlTableSet): TArray<TSqlVerbHit>;

/// <summary>Sort-Object -Unique over names: CompareGroupKeys order, case-insensitive duplicates dropped.</summary>
/// <param name="pNames">Names in any order.</param>
/// <returns>The sorted, unique names (the first of equal names in sorted order is kept).</returns>
function SortUniqueNames(const pNames: TArray<string>): TArray<string>;

implementation

uses
  System.Classes
  , System.Generics.Defaults
  ;

const
  { .NET \s over Latin-1 text: PCRE's \s plus NEL (#$85) and NBSP (#$A0) }
  PS_WS = '[\s\x{85}\x{A0}]';
  { .NET \w over Latin-1 text: PCRE's ASCII \w plus the Latin-1 letters }
  PS_WORD = '[\w\x{AA}\x{B5}\x{BA}\x{C0}-\x{D6}\x{D8}-\x{F6}\x{F8}-\x{FF}]';
  STRIP_SQL_PATTERN = '''[^'']*''|/\*[\s\S]*?\*/|--[^\r\n]*';
  NEXT_STATEMENT_PATTERN = '(?i)^(CREATE|RECREATE|ALTER)' + PS_WS + '|^SET' + PS_WS + '+TERM(?!' + PS_WORD + ')';
  SET_TERM_PATTERN = '^' + PS_WS + '*SET' + PS_WS + '+TERM' + PS_WS + '*([^\s\x{85}\x{A0}])';
  VERB_PATTERN = '(?<![A-Za-z0-9_$.])(DELETE' + PS_WS + '+FROM|EXECUTE' + PS_WS + '+PROCEDURE|FROM|JOIN|INTO|UPDATE)' +
    PS_WS + '+([A-Z][A-Z0-9_$]*)(?![A-Za-z0-9_$])';
  NEW_OLD_PATTERN = '(?<!' + PS_WORD + ')(?:NEW|OLD)\.([A-Za-z_][A-Za-z0-9_$]*)';
  WS_RUN_PATTERN = PS_WS + '+';
  DEFAULT_TERM = ';';
  TRIGGER_TERM = '^';
  KIND_TABLE = 'table';
  KIND_PROCEDURE = 'procedure';
  VERB_EXECUTE = 'EXECUTE PROCEDURE';
  COLUMN_SEP = ',';

var
  { compiled once: a class-method TRegEx call compiles its pattern on every call }
  GNextStatement: TRegEx;
  GSetTerm      : TRegEx;
  GVerb         : TRegEx;
  GNewOld       : TRegEx;
  GWsRun        : TRegEx;
  GStripSql     : TRegEx;

function SortUniqueNames(const pNames: TArray<string>): TArray<string>;
begin
  var L:= TList<string>.Create(TComparer<string>.Construct(
    function(const pA, pB: string): Integer begin Result:= CompareGroupKeys(pA, pB); end));
  try
    L.AddRange(pNames);
    L.Sort;
    Result:= [];
    for var S in L do
      if (Length(Result) = 0) or (CompareGroupKeys(Result[High(Result)], S) <> 0) then
        Result:= Result + [S];
  finally
    L.Free;
  end;
end;

function FindSqlBodyEnd(const pLines: TArray<string>; pLine: Integer; const pTerm: string; pBareTerm: Boolean;
  pMaxLines: Integer): TSqlBodyEnd;
begin
  Result:= Default(TSqlBodyEnd);
  var Last:= pLine - 1 + pMaxLines;
  if Length(pLines) < Last then
    Last:= Length(pLines);
  for var J:= pLine - 1 to Last - 1 do
  begin
    var T:= PsTrim(pLines[J]);
    if (J > pLine - 1) and GNextStatement.IsMatch(T) then
    begin
      Result.Reason:= Format('reached the next statement at line %d before a %s terminator', [J + 1, pTerm]);
      Exit;
    end;
    var Hit:= if pBareTerm then SameText(T, pTerm) else T.EndsWith(pTerm);
    if Hit then
    begin
      Result.Found:= True;
      Result.EndLine:= J + 1;
      Exit;
    end;
  end;
  Result.Reason:= Format('no %s terminator within %d lines', [pTerm, pMaxLines]);
end;

function SqlTermAt(const pLines: TArray<string>; pLine: Integer): string;
begin
  Result:= DEFAULT_TERM;
  var N:= pLine - 1;
  if Length(pLines) < N then
    N:= Length(pLines);
  for var J:= 0 to N - 1 do
  begin
    var M:= GSetTerm.Match(pLines[J]);
    if M.Success then
      Result:= M.Groups[1].Value;
  end;
end;

function SqlVerbTables(const pText: string; pSet: TSqlTableSet): TArray<TSqlVerbHit>;
begin
  Result:= [];
  if pText = '' then
    Exit;
  for var M in GVerb.Matches(pText) do
  begin
    var Hit: TSqlVerbHit;
    Hit.Verb:= GWsRun.Replace(M.Groups[1].Value, ' ');
    Hit.Name:= M.Groups[2].Value;
    Hit.Index:= M.Index - 1;
    if SameText(Hit.Verb, VERB_EXECUTE) then
    begin
      if not pSet.HasProcedure(Hit.Name) then
        Continue;
      Hit.Kind:= KIND_PROCEDURE;
    end
    else if pSet.Table(Hit.Name) = nil then
      Continue
    else
      Hit.Kind:= KIND_TABLE;
    Result:= Result + [Hit];
  end;
end;

{ ---- TSqlTable ---- }

constructor TSqlTable.Create;
begin
  inherited Create;
  FColumns:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FOlderKeys:= TList<string>.Create;
  FOlder:= TDictionary<string, TOlderColumn>.Create(TIStringComparer.Ordinal);
end;

destructor TSqlTable.Destroy;
begin
  FOlder.Free;
  FOlderKeys.Free;
  FColumns.Free;
  inherited Destroy;
end;

function TSqlTable.HasColumn(const pCol: string): Boolean;
begin
  Result:= FColumns.ContainsKey(pCol);
end;

function TSqlTable.TryOlder(const pColUpper: string; out pOlder: TOlderColumn): Boolean;
begin
  Result:= FOlder.TryGetValue(pColUpper, pOlder);
end;

function TSqlTable.OlderKeys: TArray<string>;
begin
  Result:= FOlderKeys.ToArray;
end;

function TSqlTable.IsColumn(const pCol: string): Boolean;
begin
  Result:= FColumns.ContainsKey(pCol) or FOlder.ContainsKey(pCol.ToUpperInvariant);
end;

function TSqlTable.CopyWithout(const pCol: string; const pOlder: TOlderColumn; pHasOlder: Boolean): TSqlTable;
begin
  Result:= TSqlTable.Create;
  Result.FName:= FName;
  Result.FId:= FId;
  Result.FPath:= FPath;
  Result.FLine:= FLine;
  Result.FDeclarations:= FDeclarations;
  Result.FColumnNames:= [];
  for var C in FColumnNames do
    if not SameText(C, pCol) then
      Result.FColumnNames:= Result.FColumnNames + [C];
  for var C in FColumns.Keys do
    if not SameText(C, pCol) then
      Result.FColumns.Add(C, True);
  for var K in FOlderKeys do
  begin
    Result.FOlderKeys.Add(K);
    Result.FOlder.Add(K, FOlder[K]);
  end;
  if pHasOlder then
  begin
    var Up:= pCol.ToUpperInvariant;
    if not Result.FOlder.ContainsKey(Up) then
      Result.FOlderKeys.Add(Up);
    Result.FOlder.AddOrSetValue(Up, pOlder);
  end;
end;

{ ---- TSqlTableSet ---- }

constructor TSqlTableSet.Create(const pDb: string);
begin
  inherited Create;
  FDb:= pDb;
  FTables:= TDictionary<string, TSqlTable>.Create(TIStringComparer.Ordinal);
  FOwned:= TObjectList<TSqlTable>.Create(True);
  FProcedures:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
end;

destructor TSqlTableSet.Destroy;
begin
  FProcedures.Free;
  FTables.Free;
  FOwned.Free;
  inherited Destroy;
end;

function TSqlTableSet.Table(const pName: string): TSqlTable;
begin
  if not FTables.TryGetValue(pName, Result) then
    Result:= nil;
end;

function TSqlTableSet.HasProcedure(const pName: string): Boolean;
begin
  Result:= FProcedures.ContainsKey(pName);
end;

function TSqlTableSet.HideExtractedColumns(const pTableColumns: TArray<string>): TSqlTableSet;
begin
  { checked first, against this set, so a refusal builds nothing (the PS throws mid-copy) }
  for var TC in pTableColumns do
  begin
    var P:= TC.Split(['.']);
    var T: TSqlTable:= nil;
    if Length(P) = 2 then
      T:= Table(P[0]);
    if (T = nil) or not T.HasColumn(P[1]) then
      raise EChartsIndex.CreateFmt('Hide-ExtractedColumns: %s is not an extracted column of the SQL index', [TC]);
  end;
  Result:= TSqlTableSet.Create(FDb);
  for var Pair in FTables do
    Result.FTables.Add(Pair.Key, Pair.Value);
  for var Pair in FProcedures do
    Result.FProcedures.Add(Pair.Key, Pair.Value);
  Result.FNames:= FNames;
  Result.FDeclarationCount:= FDeclarationCount;
  Result.FCollapsedNames:= FCollapsedNames;
  Result.FProcedureDeclCount:= FProcedureDeclCount;
  for var TC in pTableColumns do
  begin
    var P:= TC.Split(['.']);
    var Hidden:= Result.Table(P[0]).CopyWithout(P[1], Default(TOlderColumn), False);
    Result.FOwned.Add(Hidden);
    Result.FTables.AddOrSetValue(P[0], Hidden);
  end;
  Result.FDoctored:= True;
end;

{ ---- TSqlCatalog ---- }

type
  TDeclRow = record
    Id   : Integer;
    Name : string;
    Line : Integer;
    Path : string;
    MTime: Int64;
  end;

function BuildSqlTableSet(pIndex: TChartsIndex): TSqlTableSet; forward;

constructor TSqlCatalog.Create(pIndex: TChartsIndex; pReader: TSourceReader);
begin
  inherited Create;
  FIndex:= pIndex;
  FReader:= pReader;
  FStripped:= TDictionary<string, TArray<string>>.Create(TIStringComparer.Ordinal);
end;

destructor TSqlCatalog.Destroy;
begin
  FStripped.Free;
  FTableSet.Free;
  inherited Destroy;
end;

function TSqlCatalog.TableSet: TSqlTableSet;
begin
  if FTableSet = nil then
    FTableSet:= BuildSqlTableSet(FIndex);
  Result:= FTableSet;
end;

function SqlDbPath(pIndex: TChartsIndex): string;
begin
  Result:= '';
  var Rows:= pIndex.Query('PRAGMA database_list');
  try
    for var R in Rows do
      if SameText(R.S('name'), 'main') then
        Exit(R.S('file'));
  finally
    Rows.Free;
  end;
end;

{ Get-SqlTableSet's body; a free function so the catalogue stays small. }
function BuildSqlTableSet(pIndex: TChartsIndex): TSqlTableSet;
var
  Cols  : TDictionary<Integer, TArray<string>>;
  Groups: TDictionary<string, TList<TDeclRow>>;
  Keys  : TList<string>;
begin
  Result:= TSqlTableSet.Create(SqlDbPath(pIndex));
  Cols:= TDictionary<Integer, TArray<string>>.Create;
  Groups:= TDictionary<string, TList<TDeclRow>>.Create;
  Keys:= TList<string>.Create;
  try
    var Rows:= pIndex.AllRows('SELECT c.parent_id AS tid, GROUP_CONCAT(c.name, '','') AS cols ' +
      'FROM symbols c WHERE c.kind = ''sql_column'' GROUP BY c.parent_id', 'c.parent_id');
    try
      for var R in Rows do
      begin
        var Names: TArray<string>:= [];
        for var S in R.S('cols').Split([COLUMN_SEP]) do
          if S <> '' then
            Names:= Names + [S];
        Cols.AddOrSetValue(R.I('tid'), Names);
      end;
    finally
      Rows.Free;
    end;
    Rows:= pIndex.AllRows('SELECT t.id AS id, t.name AS name, t.start_line AS line, f.path AS path, f.mtime_unix AS mtime ' +
      'FROM symbols t JOIN files f ON f.id = t.file_id WHERE t.kind = ''sql_table''', 't.id');
    try
      Result.FDeclarationCount:= Rows.Count;
      for var R in Rows do
      begin
        var D: TDeclRow;
        D.Id:= R.I('id');
        D.Name:= R.S('name');
        D.Line:= R.I('line');
        D.Path:= R.S('path');
        D.MTime:= StrToInt64Def(R.S('mtime'), 0);
        var Key:= D.Name.ToUpperInvariant;
        var G: TList<TDeclRow>:= nil;
        if not Groups.TryGetValue(Key, G) then
        begin
          G:= TList<TDeclRow>.Create;
          Groups.Add(Key, G);
          Keys.Add(Key);
        end;
        G.Add(D);
      end;
    finally
      Rows.Free;
    end;
    for var Key in Keys do
    begin
      var G:= Groups[Key];
      { newest file, then latest line; equal rows keep index (id) order }
      G.Sort(TComparer<TDeclRow>.Construct(
        function(const pA, pB: TDeclRow): Integer
        begin
          if pA.MTime <> pB.MTime then
            Exit(if pA.MTime > pB.MTime then -1 else 1);
          if pA.Line <> pB.Line then
            Exit(pB.Line - pA.Line);
          Result:= pA.Id - pB.Id;
        end));
      if G.Count > 1 then
        Inc(Result.FCollapsedNames);
      var Win:= G[0];
      var T:= TSqlTable.Create;
      T.FName:= Win.Name;
      T.FId:= Win.Id;
      T.FPath:= Win.Path;
      T.FLine:= Win.Line;
      T.FColumnNames:= [];
      Cols.TryGetValue(Win.Id, T.FColumnNames);
      for var C in T.FColumnNames do
        T.FColumns.AddOrSetValue(C, True);
      SetLength(T.FDeclarations, G.Count);
      for var K:= 0 to G.Count - 1 do
      begin
        var Names: TArray<string>:= [];
        Cols.TryGetValue(G[K].Id, Names);
        T.FDeclarations[K].Id:= G[K].Id;
        T.FDeclarations[K].Path:= G[K].Path;
        T.FDeclarations[K].Line:= G[K].Line;
        T.FDeclarations[K].Columns:= Length(Names);
        if K = 0 then
          Continue;
        for var C in Names do
        begin
          var Up:= C.ToUpperInvariant;
          if T.FColumns.ContainsKey(C) or T.FOlder.ContainsKey(Up) then
            Continue;
          var O: TOlderColumn;
          O.Column:= C;
          O.Path:= G[K].Path;
          O.Line:= G[K].Line;
          T.FOlder.Add(Up, O);
          T.FOlderKeys.Add(Up);
        end;
      end;
      Result.FOwned.Add(T);
      Result.FTables.AddOrSetValue(Win.Name, T);
    end;
    Result.FNames:= SortUniqueNames(Result.FTables.Keys.ToArray);
    Rows:= pIndex.AllRows('SELECT id, name FROM symbols WHERE kind = ''sql_procedure''', 'id');
    try
      Result.FProcedureDeclCount:= Rows.Count;
      for var R in Rows do
        Result.FProcedures.AddOrSetValue(R.S('name'), True);
    finally
      Rows.Free;
    end;
  finally
    for var G in Groups.Values do
      G.Free;
    Keys.Free;
    Groups.Free;
    Cols.Free;
  end;
end;

{ A match without LF becomes that many spaces; one with LF keeps every CR and LF. }
function TSqlCatalog.BlankSqlMatch(const pMatch: TMatch): string;
begin
  Result:= pMatch.Value;
  if Pos(#10, Result) = 0 then
    Exit(StringOfChar(' ', Length(Result)));
  for var K:= 1 to Length(Result) do
    if not CharInSet(Result[K], [#13, #10]) then
      Result[K]:= ' ';
end;

function TSqlCatalog.StrippedSqlLines(const pReadPath: string): TArray<string>;
begin
  if FStripped.TryGetValue(pReadPath, Result) then
    Exit;
  var Raw:= ReadLatin1(pReadPath);
  var Blanked:= GStripSql.Replace(Raw, BlankSqlMatch);
  Result:= SplitLines(Blanked);
  FStripped.Add(pReadPath, Result);
end;

function TSqlCatalog.FreshLines(const pPath: string; pLine: Integer; out pBody: TSqlBody;
  out pLines: TArray<string>): Boolean;
begin
  pBody:= Default(TSqlBody);
  pBody.StartLine:= pLine;
  pLines:= [];
  Result:= FReader.SourceFresh(pPath);
  if not Result then
  begin
    pBody.Stale:= True;
    pBody.Reason:= 'stale source';
    Exit;
  end;
  pLines:= StrippedSqlLines(FReader.ReadPath(pPath));
end;

function TSqlCatalog.SqlBodyText(const pPath: string; pLine, pMaxLines: Integer): TSqlBody;
var
  Lines: TArray<string>;
begin
  if not FreshLines(pPath, pLine, Result, Lines) then
    Exit;
  var E:= FindSqlBodyEnd(Lines, pLine, TRIGGER_TERM, False, pMaxLines);
  if not E.Found then
  begin
    Result.Reason:= E.Reason;
    Exit;
  end;
  Result.Found:= True;
  Result.EndLine:= E.EndLine;
  var J:= E.EndLine - 1;
  if J > pLine - 1 then
    Result.Text:= string.Join(#10, Lines, pLine - 1, J - (pLine - 1));
end;

function TSqlCatalog.SqlProcBodyText(const pPath: string; pLine, pMaxLines: Integer): TSqlBody;
var
  Lines: TArray<string>;
begin
  if not FreshLines(pPath, pLine, Result, Lines) then
    Exit;
  Result.Term:= SqlTermAt(Lines, pLine);
  if Result.Term = DEFAULT_TERM then
  begin
    Result.Reason:= 'no SET TERM in force at the declaration';
    Exit;
  end;
  var E:= FindSqlBodyEnd(Lines, pLine, Result.Term, False, pMaxLines);
  if not E.Found then
  begin
    Result.Reason:= E.Reason;
    Exit;
  end;
  Result.Found:= True;
  Result.EndLine:= E.EndLine;
  var Body:= string.Join(#10, Lines, pLine - 1, E.EndLine - pLine + 1);
  Result.Text:= Copy(Body, 1, Body.LastIndexOf(Result.Term));
end;

function TSqlCatalog.ProcedureSet: TArray<TSqlProcedure>;
begin
  if FProcsDone then
    Exit(FProcs);
  var TSet:= TableSet;
  var Rows:= FIndex.AllRows('SELECT s.id AS id, s.name AS name, s.start_line AS line, f.path AS path ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''sql_procedure''', 's.id');
  try
    SetLength(FProcs, Rows.Count);
    for var K:= 0 to Rows.Count - 1 do
    begin
      var P: TSqlProcedure;
      P.Id:= Rows[K].I('id');
      P.Name:= Rows[K].S('name');
      P.Path:= Rows[K].S('path');
      P.Body:= SqlProcBodyText(P.Path, Rows[K].I('line'));
      P.Tables:= [];
      P.Procs:= [];
      if P.Body.Found then
        for var H in SqlVerbTables(P.Body.Text, TSet) do
          if H.Kind = KIND_TABLE then
            P.Tables:= P.Tables + [H.Name]
          else
            P.Procs:= P.Procs + [H.Name];
      P.Tables:= SortUniqueNames(P.Tables);
      P.Procs:= SortUniqueNames(P.Procs);
      FProcs[K]:= P;
    end;
  finally
    Rows.Free;
  end;
  FProcsDone:= True;
  Result:= FProcs;
end;

function TSqlCatalog.TriggerSet: TArray<TSqlTrigger>;
begin
  if FTrigsDone then
    Exit(FTrigs);
  var TSet:= TableSet;
  var Rows:= FIndex.AllRows('SELECT s.id AS id, s.name AS name, s.start_line AS line, f.path AS path, ' +
    '(SELECT r.name_text FROM refs r WHERE r.file_id = s.file_id AND r.start_line = s.start_line ' +
    'AND r.kind = ''sql_table_ref'' LIMIT 1) AS tbl ' +  // dl:ok duplicate-code@d652 -- REVIEWED 2026-10-13: the shared shape is the row-loop scaffold of two loaders (sql_procedure vs sql_trigger rows, different records and body readers), one per PS function; a generic loader would hide the per-kind fields the parity probe compares
    'FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''sql_trigger''', 's.id');
  try
    SetLength(FTrigs, Rows.Count);
    for var K:= 0 to Rows.Count - 1 do
    begin
      var T: TSqlTrigger;
      T.Id:= Rows[K].I('id');
      T.Name:= Rows[K].S('name');
      T.Path:= Rows[K].S('path');
      T.Body:= SqlBodyText(T.Path, Rows[K].I('line'));
      T.Table:= Rows[K].S('tbl');
      T.TableKnown:= (T.Table <> '') and (TSet.Table(T.Table) <> nil);
      T.Columns:= [];
      T.OtherTables:= [];
      if T.Body.Found then
      begin
        for var M in GNewOld.Matches(T.Body.Text) do
          T.Columns:= T.Columns + [M.Groups[1].Value.ToUpperInvariant];
        for var H in SqlVerbTables(T.Body.Text, TSet) do
          if (H.Kind = KIND_TABLE) and not SameText(H.Name, T.Table) then
            T.OtherTables:= T.OtherTables + [H.Name];
      end;
      T.Columns:= SortUniqueNames(T.Columns);
      T.OtherTables:= SortUniqueNames(T.OtherTables);
      { the PS keeps no trigger body text or terminator }
      T.Body.Text:= '';
      FTrigs[K]:= T;
    end;
  finally
    Rows.Free;
  end;
  FTrigsDone:= True;
  Result:= FTrigs;
end;

initialization
  GNextStatement:= TRegEx.Create(NEXT_STATEMENT_PATTERN);
  GSetTerm:= TRegEx.Create(SET_TERM_PATTERN);
  GVerb:= TRegEx.Create(VERB_PATTERN);
  GNewOld:= TRegEx.Create(NEW_OLD_PATTERN);
  GWsRun:= TRegEx.Create(WS_RUN_PATTERN);
  GStripSql:= TRegEx.Create(STRIP_SQL_PATTERN);

end.
