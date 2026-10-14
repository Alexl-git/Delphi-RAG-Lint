unit DRagLint.Charts.Q.Consumers;

(* The `consumers` question in-process: a port of charts\src\Emit-Consumers.ps1 (the PS output
  is the reference, P3). Who reads and who writes this database TABLE, or this COLUMN, and what
  does the database itself hang on it (triggers, procedures, indexes)?

  Two indexes, neither of them the database: -DbPath is a Delphi project index (SERVER answers
  the SQL half, CLIENT the by-name and data-binding half) and -SqlDbPath the index of the .SQL
  scripts. Their roles are checked so a swapped pair refuses instead of rendering an empty chart.
  A routine whose sql_reads / sql_writes fact names T is [certain]; one with an upper-case SQL
  verb literal naming T inside its span is [inferred]; a literal EQUAL to T is a [by name]
  mention, not a read. The column form draws server routines naming C, triggers using NEW./OLD.C,
  procedures, indexes, and CLIENT bindings whose datasource chain resolves to T.

  Not ported: the -SourceOverride and -TestHideColumn test hooks (New-DiagramArtifact never passes
  them, so TestChart is always false and no TEST CHART row is drawn), the Write-Host progress
  lines, and Get-ClusterCount (defined in the script, called nowhere). A missing -SqlDbPath refuses
  with New-DiagramArtifact's own message, the layer that checks it before the PS emitter is
  reached. The script's numbered sections are methods of TConsumersChart and its local functions
  are private methods (New-Row, Get-RoutineLabel, New-RoutineRow, Sort-Keys, Add-Cluster,
  Get-FileRoutines, Find-Routine, Get-RoutineRows, Get-SpanLiterals, Set-ColumnFromState,
  Get-SqlIndexRows, Get-SqlLineText) or free routines (Get-NearestName, Split-Tables,
  Get-ShortList); Get-WordRx and Get-SqlTableSymbolCount are shared with lands-where
  (DRagLint.Charts.Sql).

  PS traps closed: `-eq`, `-in`, `-contains` and `-match` are case-insensitive while
  [regex]::IsMatch is not (Get-WordRx and the verb pattern are case-SENSITIVE on purpose);
  hashtables and [ordered] dictionaries keyed by text are case-insensitive (TIStringComparer.Ordinal);
  Sort-Object is not stable (TPsSort) and orders text with CompareGroupKeys; Group-Object emits its
  groups sorted; Measure-Object -Sum is a double (ByNameLiterals when non-zero, BindingsElsewhere,
  BindingsUnresolved print '.0'); a table-form Column is JSON null. *)

interface

const
  /// <summary>The registered question id.</summary>
  CONSUMERS_ID = 'consumers';

implementation

uses
  System.SysUtils, System.Math, System.Generics.Defaults, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Source, DRagLint.Charts.Sql, DRagLint.Charts.Columns, DRagLint.Charts.Chain,
  DRagLint.Charts.Checks, DRagLint.Charts.Tools, DRagLint.Charts.PsSort;

const
  READ_BORDER = '#3B5BDB';
  READ_FILL = '#EDF2FF';
  READ_HDR = '#3B5BDB';
  WRITE_BORDER = '#C2410C';
  WRITE_FILL = '#FFF4E6';
  WRITE_HDR = '#C2410C';
  DB_BORDER = '#BE185D';
  DB_FILL = '#FDF2F8';
  DB_HDR = '#BE185D';
  NAME_BORDER = '#6B7280';
  NAME_FILL = '#F3F4F6';
  NAME_HDR = '#6B7280';
  BIND_BORDER = '#7C3AED';
  BIND_FILL = '#F3EEFF';
  BIND_HDR = '#7C3AED';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FOCUS_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  SOLID_STYLE = 'rounded,filled';
  DASHED_STYLE = 'rounded,filled,dashed';
  K_READ = 'read';
  K_WRITE = 'write';
  K_DB = 'db';
  K_NAME = 'name';
  K_BIND = 'bind';
  SIDE_LEFT = 'left';
  SIDE_RIGHT = 'right';
  SIDE_DB = 'db';
  SIDE_MENTION = 'mention';
  KIND_TABLE = 'table';
  VERB_FROM = 'FROM';
  VERB_JOIN = 'JOIN';
  STATE_OLDER = 'older';
  STATE_STALE = 'stale';
  GRADE_STALE = 'stale source';
  NO_DATASOURCE = 'no datasource on the control or its view in the DFM';
  ROUTINE_KINDS: TArray<string> = ['method', 'procedure', 'function', 'constructor', 'destructor'];
  BIND_PROPS: TArray<string> = ['DataBinding.FieldName', 'DataBinding.DataField', 'FieldName', 'DataField',
    'DataController.KeyFieldNames', 'Properties.KeyFieldNames', 'DataController.DetailKeyFieldNames',
    'DataController.MasterKeyFieldNames', 'IndexFieldNames'];
  { Measured 2026-09-23 against the live Firebird DB, VALIDATION ONLY (P16). }
  SCHEMA_NOTE = '5 live tables are not in the scripts (2026-09-23)';
  { the P23 population: an UPPER-CASE SQL verb as a word }
  VERB_RX = '(?<![A-Za-z0-9_$])(SELECT|INSERT|UPDATE|DELETE|FROM|JOIN|INTO|EXECUTE)(?![A-Za-z0-9_$])';
  VERB_WORDS: TArray<string> = ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'FROM', 'JOIN', 'INTO', 'EXECUTE'];
  COLUMN_RX = '^\s*([A-Za-z_][A-Za-z0-9_$]*)\.([A-Za-z_][A-Za-z0-9_$]*)\s*$';
  { Get-RoutineRows asks for this many ids per query }
  ROUTINE_CHUNK = 60;
  { a shared prefix this long outranks raw edit distance (Get-NearestName) }
  NEAR_PREFIX = 3;
  NEAR_PREFIX_WEIGHT = 1000;
  { trigger columns listed on a row before "+N more" }
  TRIGGER_COLUMNS_SHOWN = 6;
  FOCUS_ROW_POINTS = 12;

type
  { a symbol_facts row: the PS $null is HasReads / HasWrites False }
  TFact = record
    Sid      : Integer;
    Reads    : string;
    Writes   : string;
    HasReads : Boolean;
    HasWrites: Boolean;
  end;

  { one (literal, verb, name) of the index-wide verb scan }
  TVerbRow = record
    Fid : Integer;
    Line: Integer;
    Path: string;
    Text: string;
    Verb: string;
    Name: string;
    Kind: string;
  end;

  { a routine with an impl span in one file (Get-FileRoutines) }
  TFileRoutine = record
    Id: Integer;
    Q : string;
    A : Integer;
    B : Integer;
  end;

  { a Get-RoutineRows entry }
  TRoutineInfo = record
    Id  : Integer;
    Q   : string;
    Kind: string;
    Fid : Integer;
    Path: string;
    A   : Integer;
    B   : Integer;
    Line: Integer;
  end;

  { a verb literal naming T, per routine (or per unit at unit level) }
  TLitEntry = record
    Key  : Integer;
    Fid  : Integer;
    Path : string;
    Line : Integer;
    Verbs: TArray<string>;
    Text : string;
  end;

  { a literal inside a routine span }
  TSpanLit = record
    Line: Integer;
    Text: string;
  end;

  { a literal equal to the table name }
  TByNameLit = record
    Line   : Integer;
    Kind   : string;
    Routine: string;
  end;

  { a procedure name whose scanned body names T }
  TProcRow = record
    Decl : TSqlProcedure;
    Decls: Integer;
  end;

  { a procedure whose name carries T but whose body was not scanned }
  TProcUnscanned = record
    Decl : TSqlProcedure;
    Stale: Boolean;
  end;

  { a sql_index row on T }
  TIdxRow = record
    Name: string;
    Path: string;
    Line: Integer;
  end;

  { a drawn CLIENT data binding }
  TBindRow = record
    Dfm    : string;
    Line   : Integer;
    Control: string;
    Prop   : string;
    Ds     : string;
    Grade  : string;
  end;

  { the server-sql evidence for a column the SQL index does not extract }
  TScHit = record
    Path   : string;
    Line   : Integer;
    Routine: string;
  end;

  { an Add-Cluster entry }
  TCluster = record
    Side    : string;
    Id      : string;
    Title   : string;
    Count   : Integer;
    Subtitle: string;
    Rows    : TArray<TDotRow>;
    Style   : string;
    Border  : string;
    Fill    : string;
    Hdr     : string;
  end;

  { One consumers chart being drawn: the PS script-scope state and its local functions. Owns the
    two indexes, their readers, the SQL catalogue and the walker. }
  TConsumersChart = class  // dl:ok god-class@cc39, high-response@cc39 -- REVIEWED 2026-10-14: the class IS Emit-Consumers.ps1 (one script, one chart): its fields are the script-scope state the PS local functions share, its methods one per script section and local function; splitting it would break the line-for-line port the parity harness checks
  private
    FDbPath        : string;
    FIndex         : TChartsIndex;
    FReader        : TSourceReader;
    FSqlDb         : string;
    FSqlIndex      : TChartsIndex;
    FSqlReader     : TSourceReader;
    FCatalog       : TSqlCatalog;
    FWalker        : TChainWalker;
    FCap           : Integer;
    FAnchored      : Integer;
    FSelTable      : string;
    FSelCol        : string;
    FTbl           : TSqlTable;
    FTName         : string;
    FDeclText      : string;
    FColName       : string;
    FColFile       : string;
    FColLine       : Integer;
    FColOlder      : Boolean;
    FHasCs         : Boolean;
    FCs            : TSqlColumnState;
    FFacts         : TArray<TFact>;
    FNReadFacts    : Integer;
    FNWriteFacts   : Integer;
    FNFactReadTabs : Integer;
    FNVerbLits     : Integer;
    FNFromJoinTabs : Integer;
    FNoSql         : Boolean;
    FVerbHits      : TArray<TVerbRow>;
    FRoutineCache  : TDictionary<Integer, TArray<TFileRoutine>>;
    FRtInfo        : TDictionary<Integer, TRoutineInfo>;
    FSpanLits      : TDictionary<Integer, TArray<TSpanLit>>;
    FCertR         : TDictionary<Integer, Boolean>;
    FCertW         : TDictionary<Integer, Boolean>;
    FLitR          : TDictionary<Integer, TLitEntry>;
    FLitW          : TDictionary<Integer, TLitEntry>;
    FInfR          : TArray<Integer>;
    FInfW          : TArray<Integer>;
    FRtIds         : TArray<Integer>;
    FMR            : TConsumerKeys;
    FMW            : TConsumerKeys;
    FUnitLevel     : Integer;
    FByNameKeys    : TList<string>;
    FByNameFiles   : TDictionary<string, TArray<TByNameLit>>;
    FByNameSkipped : Integer;
    FByNameLits    : Integer;
    FCaseOnlyCount : Integer;
    FCaseOnlyText  : string;
    FTrigFor       : TArray<TSqlTrigger>;
    FTrigOther     : TArray<TSqlTrigger>;
    FProcCount     : Integer;
    FProcBodies    : Integer;
    FProcRows      : TArray<TProcRow>;
    FProcUnscanned : TArray<TProcUnscanned>;
    FProcNotScanned: Integer;
    FIdxRows       : TArray<TIdxRow>;
    FSrvCol        : TDictionary<Integer, TSpanLit>;
    FSrvColSilent  : Integer;
    FTrigCol       : TArray<TSqlTrigger>;
    FTrigColStale  : TArray<TSqlTrigger>;
    FTrigColNoBody : TArray<TSqlTrigger>;
    FProcCol       : TArray<TProcRow>;
    FIdxCol        : TArray<TIdxRow>;
    FBindAll       : Integer;
    FBindDrawn     : TArray<TBindRow>;
    FBindElsewhere : TDictionary<string, Integer>;
    FBindUnresolved: TDictionary<string, Integer>;
    FBindStale     : Integer;
    FClusters      : TArray<TCluster>;
    FLabel         : string;
    FSb            : TStringBuilder;
    function FileRoutines(pFid: Integer): TArray<TFileRoutine>;
    function FindRoutine(pFid, pLine: Integer; out pRoutine: TFileRoutine): Boolean;
    procedure LoadRoutineRows(const pIds: TArray<Integer>);
    function SpanLiterals(const pRt: TRoutineInfo): TArray<TSpanLit>;
    function FirstSpanMatch(const pRt: TRoutineInfo; const pPattern: string; out pHit: TSpanLit): Boolean;
    function RoutineQ(pKey: Integer): string;
    procedure SetColumnFromState;
    function SqlIndexRows(const pName: string): TArray<TIdxRow>;
    function SqlLineText(const pPath: string; pLine: Integer; out pText: string): Boolean;
    function NewRow(const pCaption, pFile: string; pLine: Integer; const pTip, pNote: string): TDotRow;
    function RoutineLabel(const pRt: TRoutineInfo): string;
    function NewRoutineRow(pKey: Integer; const pSide: string; pLitBag: TDictionary<Integer, TLitEntry>; pCertain: Boolean): TDotRow;
    function SortKeys(const pKeys: TArray<Integer>): TArray<Integer>;
    function RoutineRows(const pKeys: TArray<Integer>; const pSide: string; pLitBag: TDictionary<Integer, TLitEntry>;
      pCertain: Boolean): TArray<TDotRow>;
    procedure AddCluster(const pSide, pId, pTitle: string; const pRows: TArray<TDotRow>; const pKind: string; pDashed: Boolean;
      const pExtra: string);
    procedure SelectTarget(const pTarget: string);
    procedure CheckRoles;
    procedure ResolveTable;
    procedure ReadIndexWide;
    procedure ReadConsumers;
    procedure RecheckColumn;
    procedure ReadByName;
    procedure ReadDatabase;
    procedure ReadColumn;
    procedure ReadBindings;
    procedure ColumnClusters;
    procedure TableClusters;
    function FocusLabel: string;
    procedure DrawDot;
    function ResultFields: TArray<TMetaField>;
  public
    constructor Create(const pArgs: TQuestionArgs);
    destructor Destroy; override;
    function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
  end;

{ "file:line" of a tip }
function At(const pPath: string; pLine: Integer): string;
begin
  Result:= Format('%s:%d', [FileNameOf(pPath), pLine]);
end;

{ `Sort-Object` over text }
function SortedText(const pNames: TArray<string>): TArray<string>;
begin
  Result:= Copy(pNames);
  TPsSort<string>.Sort(Result,
    function(const pA, pB: string): Integer
    begin
      Result:= CompareGroupKeys(pA, pB);
    end);
end;

{ `-contains`: case-insensitive membership }
function ContainsText(const pItems: TArray<string>; const pName: string): Boolean;
begin
  Result:= False;
  for var S in pItems do
    if SameText(S, pName) then
      Exit(True);
end;

{ Get-NearestName: shared prefix (3+) first, then edit distance; ties to the ordinal-lowest name }
function NearestName(const pWant: string; const pNames: TArray<string>): string;
begin
  var W:= pWant.ToUpperInvariant;
  Result:= '';
  var BestD:= MaxInt;
  for var N in pNames do
  begin
    var U:= N.ToUpperInvariant;
    var D: TArray<TArray<Integer>>;
    SetLength(D, Length(W) + 1, Length(U) + 1);
    for var I:= 0 to High(D) do
      D[I][0]:= I;
    for var J:= 0 to High(D[0]) do
      D[0][J]:= J;
    for var I:= 1 to Length(W) do
      for var J:= 1 to Length(U) do
      begin
        var C:= if W[I] = U[J] then 0 else 1;
        D[I][J]:= Min(Min(D[I - 1][J] + 1, D[I][J - 1] + 1), D[I - 1][J - 1] + C);
      end;
    var Lcp:= 0;
    while (Lcp < Min(Length(W), Length(U))) and (W[Lcp + 1] = U[Lcp + 1]) do
      Inc(Lcp);
    var Bonus:= if Lcp >= NEAR_PREFIX then NEAR_PREFIX_WEIGHT * Lcp else 0;
    var Dist:= D[Length(W)][Length(U)] - Bonus;
    if (Dist < BestD) or ((Dist = BestD) and (CompareStr(U, Result) < 0)) then
    begin
      Result:= U;
      BestD:= Dist;
    end;
  end;
end;

{ Split-Tables: a fact's comma list, upper case, sorted, unique }
function SplitTables(const pValue: string): TArray<string>;
begin
  Result:= [];
  if PsTrim(pValue) = '' then
    Exit;
  var Parts: TArray<string>:= [];
  for var P in TRegEx.Split(pValue, ',\s*') do
  begin
    var T:= PsTrim(P).ToUpperInvariant;
    if T <> '' then
      Parts:= Parts + [T];
  end;
  Result:= SortUniqueNames(Parts);
end;

{ Get-ShortList: "A, B, C +N more" }
function ShortList(const pItems: TArray<string>; pMax: Integer): string;
begin
  if Length(pItems) <= pMax then
    Exit(string.Join(', ', pItems));
  Result:= string.Join(', ', Copy(pItems, 0, pMax)) + Format(' +%d more', [Length(pItems) - pMax]);
end;

{ how many of a count table (the PS $bindElsewhere / $bindUnresolved) }
procedure Bump(pCounts: TDictionary<string, Integer>; const pKey: string);
var
  N: Integer;
begin
  if not pCounts.TryGetValue(pKey, N) then
    N:= 0;
  pCounts.AddOrSetValue(pKey, N + 1);
end;

function SumOf(pCounts: TDictionary<string, Integer>): Integer;
begin
  Result:= 0;
  for var N in pCounts.Values do
    Inc(Result, N);
end;

function TriggerAt(const pTrig: TSqlTrigger): string;
begin
  Result:= Format('%s@%s', [pTrig.Name, At(pTrig.Path, pTrig.Body.StartLine)]);
end;

function TriggerList(const pTrigs: TArray<TSqlTrigger>): string;
begin
  var Parts: TArray<string>:= [];
  for var T in pTrigs do
    Parts:= Parts + [TriggerAt(T)];
  Result:= string.Join(', ', Parts);
end;

constructor TConsumersChart.Create(const pArgs: TQuestionArgs);
var
  Note: string;
begin
  inherited Create;
  FDbPath:= pArgs.GuardedDb;
  FSqlDb:= CloneDb(pArgs.SqlDbPath, pArgs.CloneRoot, Note);
  FIndex:= TChartsIndex.Create(FDbPath);
  FReader:= TSourceReader.Create(FIndex);
  FSqlIndex:= TChartsIndex.Create(FSqlDb);
  FSqlReader:= TSourceReader.Create(FSqlIndex);
  FCatalog:= TSqlCatalog.Create(FSqlIndex, FSqlReader);
  FCap:= pArgs.Cap;
  FRoutineCache:= TDictionary<Integer, TArray<TFileRoutine>>.Create;
  FRtInfo:= TDictionary<Integer, TRoutineInfo>.Create;
  FSpanLits:= TDictionary<Integer, TArray<TSpanLit>>.Create;
  FCertR:= TDictionary<Integer, Boolean>.Create;
  FCertW:= TDictionary<Integer, Boolean>.Create;
  FLitR:= TDictionary<Integer, TLitEntry>.Create;
  FLitW:= TDictionary<Integer, TLitEntry>.Create;
  FByNameKeys:= TList<string>.Create;
  FByNameFiles:= TDictionary<string, TArray<TByNameLit>>.Create(TIStringComparer.Ordinal);
  FSrvCol:= TDictionary<Integer, TSpanLit>.Create;
  FBindElsewhere:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  FBindUnresolved:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  FSb:= TStringBuilder.Create;
end;

destructor TConsumersChart.Destroy;
begin
  FSb.Free;
  FBindUnresolved.Free;
  FBindElsewhere.Free;
  FSrvCol.Free;
  FByNameFiles.Free;
  FByNameKeys.Free;
  FLitW.Free;
  FLitR.Free;
  FCertW.Free;
  FCertR.Free;
  FSpanLits.Free;
  FRtInfo.Free;
  FRoutineCache.Free;
  FWalker.Free;
  FCatalog.Free;
  FSqlReader.Free;
  FSqlIndex.Free;
  FReader.Free;
  FIndex.Free;
  inherited Destroy;
end;

{ Get-FileRoutines: the routines of one file with an impl span, cached }
function TConsumersChart.FileRoutines(pFid: Integer): TArray<TFileRoutine>;
begin
  if FRoutineCache.TryGetValue(pFid, Result) then
    Exit;
  Result:= [];
  var Rows:= FIndex.AllRows(
    'SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS a, s.impl_end_line AS b' + sLineBreak +
    '  FROM symbols s' + sLineBreak +
    Format(' WHERE s.file_id = %d AND s.impl_start_line > 0 AND s.kind IN (%s)', [pFid, TChartsIndex.SqlInList(ROUTINE_KINDS)]),
    's.id');
  try
    for var R in Rows do
    begin
      var F: TFileRoutine;
      F.Id:= R.I('id');
      F.Q:= R.S('q');
      F.A:= R.I('a');
      F.B:= R.I('b');
      Result:= Result + [F];
    end;
  finally
    Rows.Free;
  end;
  FRoutineCache.Add(pFid, Result);
end;

{ Find-Routine: the INNERMOST routine whose impl span holds the line; False at unit level }
function TConsumersChart.FindRoutine(pFid, pLine: Integer; out pRoutine: TFileRoutine): Boolean;
begin
  Result:= False;
  pRoutine:= Default(TFileRoutine);
  for var R in FileRoutines(pFid) do
    if (R.A <= pLine) and (R.B >= pLine) then
      if not Result or (R.B - R.A < pRoutine.B - pRoutine.A) then
      begin
        pRoutine:= R;
        Result:= True;
      end;
end;

{ Get-RoutineRows: symbols rows of routine ids, ROUTINE_CHUNK per query }
procedure TConsumersChart.LoadRoutineRows(const pIds: TArray<Integer>);
begin
  var I:= 0;
  while I < Length(pIds) do
  begin
    var Chunk: TArray<string>:= [];
    for var K:= I to Min(I + ROUTINE_CHUNK - 1, High(pIds)) do
      Chunk:= Chunk + [IntToStr(pIds[K])];
    var Rows:= FIndex.Query(
      'SELECT s.id AS id, s.qualified_name AS q, s.kind AS kind, s.file_id AS fid, f.path AS path,' + sLineBreak +
      '       s.start_line AS dline, s.impl_start_line AS a, s.impl_end_line AS b' + sLineBreak +
      '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
      ' WHERE s.id IN (' + string.Join(',', Chunk) + ')');
    try
      for var R in Rows do
      begin
        var T: TRoutineInfo;
        T.Id:= R.I('id');
        T.Q:= R.S('q');
        T.Kind:= R.S('kind');
        T.Fid:= R.I('fid');
        T.Path:= R.S('path');
        T.A:= R.I('a');
        T.B:= R.I('b');
        T.Line:= if T.A <> 0 then T.A else R.I('dline');
        FRtInfo.AddOrSetValue(T.Id, T);
      end;
    finally
      Rows.Free;
    end;
    Inc(I, ROUTINE_CHUNK);
  end;
end;

{ Get-SpanLiterals: the literals inside one span, cached per routine }
function TConsumersChart.SpanLiterals(const pRt: TRoutineInfo): TArray<TSpanLit>;
begin
  if FSpanLits.TryGetValue(pRt.Id, Result) then
    Exit;
  Result:= [];
  if (pRt.A > 0) and (pRt.B >= pRt.A) then
  begin
    var Rows:= FIndex.AllRows(
      'SELECT sl.id AS id, sl.start_line AS line, sl.text AS text' + sLineBreak +
      '  FROM string_literals sl' + sLineBreak +
      Format(' WHERE sl.file_id = %d AND sl.kind IN (''literal'',''format'',''const'')', [pRt.Fid]) + sLineBreak +
      Format('   AND sl.start_line BETWEEN %d AND %d', [pRt.A, pRt.B]),
      'sl.start_line, sl.id');
    try
      for var R in Rows do
      begin
        var L: TSpanLit;
        L.Line:= R.I('line');
        L.Text:= R.S('text');
        Result:= Result + [L];
      end;
    finally
      Rows.Free;
    end;
  end;
  FSpanLits.Add(pRt.Id, Result);
end;

{ the first literal of a span that IsMatch-es pPattern (Get-SpanLiterals, Where-Object, Select-Object -First 1) }
function TConsumersChart.FirstSpanMatch(const pRt: TRoutineInfo; const pPattern: string; out pHit: TSpanLit): Boolean;
begin
  pHit:= Default(TSpanLit);
  for var L in SpanLiterals(pRt) do
    if TRegEx.IsMatch(L.Text, pPattern) then
    begin
      pHit:= L;
      Exit(True);
    end;
  Result:= False;
end;

{ $rtInfo[$key].Q; '' for a routine the index did not return (the PS $null) }
function TConsumersChart.RoutineQ(pKey: Integer): string;
var
  Rt: TRoutineInfo;
begin
  Result:= '';
  if FRtInfo.TryGetValue(pKey, Rt) then
    Result:= Rt.Q;
end;

{ Set-ColumnFromState }
procedure TConsumersChart.SetColumnFromState;
begin
  FColOlder:= SameText(FCs.State, STATE_OLDER);
  FColFile:= FCs.Path;
  FColLine:= FCs.Line;
  FColName:= FCs.Column;
  for var C in FTbl.ColumnNames do
    if SameText(C, FSelCol) then
    begin
      FColName:= C;
      Break;
    end;
end;

{ Get-SqlIndexRows: the sql_index declarations whose line names the table }
function TConsumersChart.SqlIndexRows(const pName: string): TArray<TIdxRow>;
begin
  Result:= [];
  var Rows:= FSqlIndex.Query(
    'SELECT s.name AS name, s.start_line AS line, f.path AS path' + sLineBreak +
    '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
    ' WHERE s.kind = ''sql_index''' + sLineBreak +
    '   AND EXISTS (SELECT 1 FROM refs r WHERE r.file_id = s.file_id AND r.start_line = s.start_line' + sLineBreak +
    Format('                  AND r.kind = ''sql_table_ref'' AND UPPER(r.name_text) = UPPER(''%s''))', [TChartsIndex.SqlText(pName)]) + sLineBreak +
    ' ORDER BY f.path, s.start_line');
  try
    for var R in Rows do
    begin
      var X: TIdxRow;
      X.Name:= R.S('name');
      X.Path:= R.S('path');
      X.Line:= R.I('line');
      Result:= Result + [X];
    end;
  finally
    Rows.Free;
  end;
end;

{ Get-SqlLineText: the stripped text of one SQL line; False when its script is stale }
function TConsumersChart.SqlLineText(const pPath: string; pLine: Integer; out pText: string): Boolean;
begin
  pText:= '';
  Result:= FSqlReader.SourceFresh(pPath);
  if not Result then
    Exit;
  var Lines:= FCatalog.StrippedSqlLines(FSqlReader.ReadPath(pPath));
  if (pLine >= 1) and (pLine <= Length(Lines)) then
    pText:= Lines[pLine - 1];
end;

{ New-Row: every built row counts toward Expected; Add-Cluster takes the capped ones back out }
function TConsumersChart.NewRow(const pCaption, pFile: string; pLine: Integer; const pTip, pNote: string): TDotRow;
begin
  Inc(FAnchored);
  Result:= TDotRow.Anchored(pCaption, pLine, RowHref(pFile, pLine), pTip, pNote);
end;

{ Get-RoutineLabel }
function TConsumersChart.RoutineLabel(const pRt: TRoutineInfo): string;
begin
  Result:= ShortName(pRt.Q, UnitNameOf(pRt.Path));
end;

{ New-RoutineRow: literal provenance first, the routine line as the fallback, and SAID so }
function TConsumersChart.NewRoutineRow(pKey: Integer; const pSide: string; pLitBag: TDictionary<Integer, TLitEntry>;
  pCertain: Boolean): TDotRow;
var
  E: TLitEntry;
  C: TSpanLit;
  Hit: TSpanLit;
begin
  if pKey < 0 then
  begin
    E:= pLitBag[pKey];
    Exit(NewRow('(unit level) ' + UnitNameOf(E.Path), E.Path, E.Line,
      Format('%s %s outside any routine -- %s', [string.Join(', ', E.Verbs), FTName, At(E.Path, E.Line)]), 'unit-level literal'));
  end;
  var Rt:= FRtInfo[pKey];
  var UnitName:= UnitNameOf(Rt.Path);
  if FColName <> '' then
  begin
    C:= FSrvCol[pKey];
    var How:= if FCertR.ContainsKey(pKey) or FCertW.ContainsKey(pKey) then 'table by fact' else 'table by literal';
    Exit(NewRow(RoutineLabel(Rt), Rt.Path, C.Line, Format('%s -- %s names %s (%s)', [Rt.Q, At(Rt.Path, C.Line), FColName, How]),
      UnitName + '; ' + How));
  end;
  if pCertain then
  begin
    if FirstSpanMatch(Rt, WordRx(FTName), Hit) then
      Exit(NewRow(RoutineLabel(Rt), Rt.Path, Hit.Line, Format('%s (%s, sql_%ss fact) -- %s', [Rt.Q, pSide, pSide, At(Rt.Path, Hit.Line)]),
        UnitName));
    Exit(NewRow(RoutineLabel(Rt), Rt.Path, Rt.Line, Format('%s (%s, sql_%ss fact) -- no literal inside the routine names %s',
      [Rt.Q, pSide, pSide, FTName]), UnitName + '; fact only'));
  end;
  E:= pLitBag[pKey];
  Result:= NewRow(RoutineLabel(Rt), Rt.Path, E.Line, Format('%s -- %s %s at %s', [Rt.Q, string.Join(', ', E.Verbs), FTName,
    At(Rt.Path, E.Line)]), UnitName + '; ' + string.Join('/', E.Verbs));
end;

{ Sort-Keys: by the routine's qualified name ('' at unit level), then by the key }
function TConsumersChart.SortKeys(const pKeys: TArray<Integer>): TArray<Integer>;
begin
  Result:= Copy(pKeys);
  TPsSort<Integer>.Sort(Result,
    function(const pA, pB: Integer): Integer
    begin
      var QA:= if pA > 0 then RoutineQ(pA) else '';
      var QB:= if pB > 0 then RoutineQ(pB) else '';
      Result:= CompareGroupKeys(QA, QB);
      if Result = 0 then
        Result:= CompareValue(pA, pB);
    end);
end;

{ New-RoutineRow over the keys in Sort-Keys order }
function TConsumersChart.RoutineRows(const pKeys: TArray<Integer>; const pSide: string; pLitBag: TDictionary<Integer, TLitEntry>;
  pCertain: Boolean): TArray<TDotRow>;
begin
  Result:= [];
  for var K in SortKeys(pKeys) do
    Result:= Result + [NewRoutineRow(K, pSide, pLitBag, pCertain)];
end;

{ Add-Cluster: capped rows, the disclosure, then the extra note lines }
procedure TConsumersChart.AddCluster(const pSide, pId, pTitle: string; const pRows: TArray<TDotRow>; const pKind: string;
  pDashed: Boolean; const pExtra: string);
var
  C: TCluster;
begin
  if (Length(pRows) = 0) and (pExtra = '') then
    Exit;
  var Top:= TRanked<TDotRow>.TopRanked(pRows, FCap, nil);
  var Shown:= Top.Shown;
  Dec(FAnchored, Top.HiddenRows);
  var D:= DisclosureText(Top.HiddenRows, 0, 'rows');
  if D <> '' then
    Shown:= Shown + [NoteRow(D)];
  if pExtra <> '' then
    for var X in pExtra.Split([#10]) do
      if X <> '' then
        Shown:= Shown + [NoteRow(X)];
  C.Side:= pSide;
  C.Id:= pId;
  C.Title:= pTitle;
  C.Count:= Length(pRows);
  C.Subtitle:= Format('%d row%s%s', [C.Count, if C.Count <> 1 then 's' else '', if pDashed then ' [inferred]' else '']);
  C.Rows:= Shown;
  C.Style:= if pDashed then DASHED_STYLE else SOLID_STYLE;
  if pKind = K_READ then
  begin
    C.Border:= READ_BORDER;
    C.Fill:= READ_FILL;
    C.Hdr:= READ_HDR;
  end
  else if pKind = K_WRITE then
  begin
    C.Border:= WRITE_BORDER;
    C.Fill:= WRITE_FILL;
    C.Hdr:= WRITE_HDR;
  end
  else if pKind = K_DB then
  begin
    C.Border:= DB_BORDER;
    C.Fill:= DB_FILL;
    C.Hdr:= DB_HDR;
  end
  else if pKind = K_NAME then
  begin
    C.Border:= NAME_BORDER;
    C.Fill:= NAME_FILL;
    C.Hdr:= NAME_HDR;
  end
  else
  begin
    C.Border:= BIND_BORDER;
    C.Fill:= BIND_FILL;
    C.Hdr:= BIND_HDR;
  end;
  FClusters:= FClusters + [C];
end;

{ ---- 0. the selection ---- }
procedure TConsumersChart.SelectTarget(const pTarget: string);
begin
  if pTarget = '' then
    raise EChartsQuestion.Create('consumers: pass -Table <TABLE> or -Column <TABLE.COLUMN>');
  FSelTable:= pTarget;
  FSelCol:= '';
  { New-DiagramArtifact: the dot decides the form }
  if pTarget.Contains('.') then
  begin
    var M:= TRegEx.Match(pTarget, COLUMN_RX, [roIgnoreCase]);
    if not M.Success then
      raise EChartsQuestion.CreateFmt('consumers: -Column takes TABLE.COLUMN, got ''%s''', [pTarget]);
    FSelTable:= M.Groups[1].Value;
    FSelCol:= M.Groups[2].Value;
  end;
  FSelTable:= PsTrim(FSelTable);
end;

{ the two DB roles must not be swapped }
procedure TConsumersChart.CheckRoles;
begin
  if SqlTableSymbolCount(FSqlIndex) = 0 then
    raise EChartsQuestion.CreateFmt('consumers: %s is not a SQL index (0 sql_table symbols). -SqlDbPath takes the ' +
      'index of the .SQL scripts (SQL-drag-lint-sql.sqlite); the Delphi project index goes in -DbPath.', [FSqlDb]);
  if SqlTableSymbolCount(FIndex) > 0 then
    raise EChartsQuestion.CreateFmt('consumers: %s is a SQL-script index, not a Delphi project index. -DbPath takes the ' +
      'Delphi project clone (SERVER for the SQL half, CLIENT for bindings); the scripts go in -SqlDbPath.', [FDbPath]);
end;

{ ---- 1. resolve against the COLLAPSED script schema ---- }
procedure TConsumersChart.ResolveTable;
begin
  var SqlSet:= FCatalog.TableSet;
  FTbl:= SqlSet.Table(FSelTable);
  if FTbl = nil then
    raise EChartsQuestion.CreateFmt('consumers: no table %s in the SQL index (script-derived; the scripts may lag the live ' +
      'schema) -- nearest: %s. The index holds %d table names from %d declarations; %s.',
      [FSelTable, NearestName(FSelTable, SqlSet.Names), Length(SqlSet.Names), SqlSet.DeclarationCount, SCHEMA_NOTE]);
  FTName:= FTbl.Name;
  var DeclFile:= FileNameOf(FTbl.Path);
  var DeclCount:= Length(FTbl.Declarations);
  if DeclCount > 1 then
    FDeclText:= Format('declared %d times in the scripts; showing the newest (%s:%d, by file date)', [DeclCount, DeclFile, FTbl.Line])
  else
    FDeclText:= Format('declared 1 time in the scripts (%s:%d)', [DeclFile, FTbl.Line]);
  FColFile:= FTbl.Path;
  FColLine:= FTbl.Line;
  if FSelCol <> '' then
  begin
    FCs:= SqlColumnState(FCatalog, SqlSet, FTName, FSelCol, TServerSqlHit.None, '');
    FHasCs:= True;
    if FCs.IsColumn then
      SetColumnFromState;
  end;
end;

{ ---- 2. index-wide pre-check on the Delphi index ---- }
procedure TConsumersChart.ReadIndexWide;
begin
  var Rows:= FIndex.AllRows(
    'SELECT sf.symbol_id AS sid, sf.sql_reads AS r, sf.sql_writes AS w,' + sLineBreak +
    '       (sf.sql_reads IS NOT NULL) AS hr, (sf.sql_writes IS NOT NULL) AS hw' + sLineBreak +
    '  FROM symbol_facts sf' + sLineBreak +
    ' WHERE sf.sql_reads IS NOT NULL OR sf.sql_writes IS NOT NULL',
    'sf.symbol_id');
  try
    for var R in Rows do
    begin
      var F:= Default(TFact);
      F.Sid:= R.I('sid');
      F.Reads:= R.S('r');
      F.Writes:= R.S('w');
      F.HasReads:= R.I('hr') <> 0;
      F.HasWrites:= R.I('hw') <> 0;
      FFacts:= FFacts + [F];
    end;
  finally
    Rows.Free;
  end;
  var ReadTables: TArray<string>:= [];
  for var F in FFacts do
  begin
    if F.HasReads then
      Inc(FNReadFacts);
    if F.HasWrites then
      Inc(FNWriteFacts);
    ReadTables:= ReadTables + SplitTables(F.Reads);
  end;
  FNFactReadTabs:= Length(SortUniqueNames(ReadTables));

  var Globs: TArray<string>:= [];
  for var V in VERB_WORDS do
    Globs:= Globs + [Format('sl.text GLOB ''*%s*''', [V])];
  var Pre:= FIndex.AllRows(
    'SELECT sl.id AS id, sl.file_id AS fid, sl.start_line AS line, sl.text AS text, f.path AS path' + sLineBreak +
    '  FROM string_literals sl JOIN files f ON f.id = sl.file_id' + sLineBreak +
    ' WHERE sl.source = ''pas'' AND sl.kind IN (''literal'',''format'') AND (' + string.Join(' OR ', Globs) + ')',
    'sl.id');
  try
    var FromJoin: TArray<string>:= [];
    for var X in Pre do
    begin
      var Text:= X.S('text');
      if not TRegEx.IsMatch(Text, VERB_RX) then
        Continue;
      Inc(FNVerbLits);
      for var H in SqlVerbTables(Text, FCatalog.TableSet) do
      begin
        var V:= Default(TVerbRow);
        V.Fid:= X.I('fid');
        V.Path:= X.S('path');
        V.Line:= X.I('line');
        V.Text:= Text;
        V.Verb:= H.Verb;
        V.Name:= H.Name;
        V.Kind:= H.Kind;
        FVerbHits:= FVerbHits + [V];
        if SameText(V.Kind, KIND_TABLE) and (SameText(V.Verb, VERB_FROM) or SameText(V.Verb, VERB_JOIN)) then
          FromJoin:= FromJoin + [V.Name];
      end;
    end;
    FNFromJoinTabs:= Length(SortUniqueNames(FromJoin));
  finally
    Pre.Free;
  end;
  FNoSql:= (Length(FFacts) = 0) and (FNVerbLits = 0);
end;

{ ---- 3. the table's SQL consumers on the Delphi side ---- }
procedure TConsumersChart.ReadConsumers;
var
  Rt: TFileRoutine;
  E: TLitEntry;
begin
  var Upper:= FTName.ToUpperInvariant;
  for var F in FFacts do
  begin
    if ContainsText(SplitTables(F.Reads), Upper) then
      FCertR.AddOrSetValue(F.Sid, True);
    if ContainsText(SplitTables(F.Writes), Upper) then
      FCertW.AddOrSetValue(F.Sid, True);
  end;
  { verb literals naming T -> routine; unit-level ones are keyed by -file id }
  for var H in FVerbHits do
  begin
    if not (SameText(H.Kind, KIND_TABLE) and SameText(H.Name, FTName)) then
      Continue;
    var Key:= -H.Fid;
    if FindRoutine(H.Fid, H.Line, Rt) then
      Key:= Rt.Id;
    var Bag:= if SameText(H.Verb, VERB_FROM) or SameText(H.Verb, VERB_JOIN) then FLitR else FLitW;
    if not Bag.TryGetValue(Key, E) then
    begin
      E:= Default(TLitEntry);
      E.Key:= Key;
      E.Fid:= H.Fid;
      E.Path:= H.Path;
      E.Line:= H.Line;
      E.Text:= H.Text;
    end;
    var Has:= False;
    for var V in E.Verbs do
      if V = H.Verb then
        Has:= True;
    if not Has then
      E.Verbs:= E.Verbs + [H.Verb];
    Bag.AddOrSetValue(Key, E);
  end;
  for var K in FLitR.Keys do
    if not FCertR.ContainsKey(K) then
      FInfR:= FInfR + [K];
  for var K in FLitW.Keys do
    if not FCertW.ContainsKey(K) then
      FInfW:= FInfW + [K];
  var Ids: TArray<Integer>:= FCertR.Keys.ToArray + FCertW.Keys.ToArray + FLitR.Keys.ToArray + FLitW.Keys.ToArray;
  TArray.Sort<Integer>(Ids);
  for var K in Ids do
    if (K > 0) and ((Length(FRtIds) = 0) or (FRtIds[High(FRtIds)] <> K)) then
      FRtIds:= FRtIds + [K];
  if Length(FRtIds) > 0 then
    LoadRoutineRows(FRtIds);
  { routines and unit-level rows counted apart }
  FMR:= MeasureConsumerKeys(FCertR.Keys.ToArray, FLitR.Keys.ToArray);
  FMW:= MeasureConsumerKeys(FCertW.Keys.ToArray, FLitW.Keys.ToArray);
  FUnitLevel:= MeasureConsumerKeys([], FLitR.Keys.ToArray + FLitW.Keys.ToArray).Units;
end;

{ ---- 3b. a column the SQL index does not extract: this index's own SQL (server-sql) ---- }
procedure TConsumersChart.RecheckColumn;
var
  Rt: TRoutineInfo;
  H1: TSpanLit;
begin
  if (FSelCol = '') or FCs.IsColumn then
    Exit;
  var ScRx:= WordRx(FSelCol.ToUpperInvariant);
  var Hits: TArray<TScHit>:= [];
  for var Id in FRtIds do
  begin
    if not FRtInfo.TryGetValue(Id, Rt) then
      Continue;
    if FirstSpanMatch(Rt, ScRx, H1) then
    begin
      var S: TScHit;
      S.Path:= Rt.Path;
      S.Line:= H1.Line;
      S.Routine:= ShortName(Rt.Q, UnitNameOf(Rt.Path));
      Hits:= Hits + [S];
    end;
  end;
  TPsSort<TScHit>.Sort(Hits,
    function(const pA, pB: TScHit): Integer
    begin
      Result:= CompareGroupKeys(pA.Path, pB.Path);
      if Result = 0 then
        Result:= CompareValue(pA.Line, pB.Line);
    end);
  var Hit:= TServerSqlHit.None;
  if Length(Hits) > 0 then
    Hit:= TServerSqlHit.Make(Hits[0].Path, Hits[0].Line, Hits[0].Routine);
  FCs:= SqlColumnState(FCatalog, FCatalog.TableSet, FTName, FSelCol, Hit, FileNameOf(FDbPath));
  if SameText(FCs.State, STATE_STALE) then
    raise EChartsQuestion.CreateFmt('consumers: cannot tell whether %s.%s is a column -- %s. Script-derived; the scripts may lag ' +
      'the live schema.', [FTName, FSelCol.ToUpperInvariant, FCs.Caption]);
  if not FCs.IsColumn then
    raise EChartsQuestion.CreateFmt('consumers: no column %s in %s: %s -- nearest: %s. Script-derived; the scripts may lag the ' +
      'live schema.', [FSelCol, FTName, FCs.Caption, NearestName(FSelCol, FTbl.ColumnNames + FTbl.OlderKeys)]);
  SetColumnFromState;
end;

{ ---- 4. [by name]: literals EQUAL to the table name ---- }
procedure TConsumersChart.ReadByName;
var
  Rt: TFileRoutine;
  Lits: TArray<TByNameLit>;
begin
  var Tq:= TChartsIndex.SqlText(FTName);
  var Named:= FIndex.AllRows(
    'SELECT sl.id AS id, sl.file_id AS fid, sl.start_line AS line, sl.kind AS kind, f.path AS path' + sLineBreak +
    '  FROM string_literals sl JOIN files f ON f.id = sl.file_id' + sLineBreak +
    Format(' WHERE sl.source = ''pas'' AND sl.kind IN (''literal'',''const'',''format'') AND sl.text = ''%s''', [Tq]),
    'sl.id');
  try
    var Order: TArray<TIndexRow>:= Named.ToArray;
    TPsSort<TIndexRow>.Sort(Order,
      function(const pA, pB: TIndexRow): Integer
      begin
        Result:= CompareGroupKeys(pA.S('path'), pB.S('path'));
        if Result = 0 then
          Result:= CompareValue(pA.I('line'), pB.I('line'));
      end);
    for var N in Order do
    begin
      var InRoutine:= FindRoutine(N.I('fid'), N.I('line'), Rt);
      if InRoutine and (FCertR.ContainsKey(Rt.Id) or FCertW.ContainsKey(Rt.Id) or FLitR.ContainsKey(Rt.Id) or FLitW.ContainsKey(Rt.Id)) then
      begin
        Inc(FByNameSkipped);
        Continue;
      end;
      var P:= N.S('path');
      if not FByNameFiles.TryGetValue(P, Lits) then
      begin
        Lits:= [];
        FByNameKeys.Add(P);
      end;
      var L: TByNameLit;
      L.Line:= N.I('line');
      L.Kind:= N.S('kind');
      L.Routine:= if InRoutine then Rt.Q else '';
      FByNameFiles.AddOrSetValue(P, Lits + [L]);
      Inc(FByNameLits);
    end;
  finally
    Named.Free;
  end;
  { literals equal to T only case-insensitively are COUNTED and named, not drawn }
  var CaseOnly:= FIndex.Query(
    'SELECT sl.text AS text, sl.start_line AS line, f.path AS path' + sLineBreak +
    '  FROM string_literals sl JOIN files f ON f.id = sl.file_id' + sLineBreak +
    Format(' WHERE sl.source = ''pas'' AND sl.kind IN (''literal'',''const'',''format'') AND UPPER(sl.text) = UPPER(''%s'') AND sl.text <> ''%s''',
      [Tq, Tq]) + sLineBreak +
    ' ORDER BY f.path, sl.start_line');
  try
    var Parts: TArray<string>:= [];
    for var C in CaseOnly do
      Parts:= Parts + [Format('''%s'' %s', [C.S('text'), At(C.S('path'), C.I('line'))])];
    FCaseOnlyCount:= Length(Parts);
    FCaseOnlyText:= string.Join(', ', Parts);
  finally
    CaseOnly.Free;
  end;
end;

{ ---- 5. the database side (SQL index) ---- }
procedure TConsumersChart.ReadDatabase;
begin
  for var T in FCatalog.TriggerSet do
    if SameText(T.Table, FTName) then
      FTrigFor:= FTrigFor + [T]
    else if ContainsText(T.OtherTables, FTName) then
      FTrigOther:= FTrigOther + [T];
  var ByName: TComparison<TSqlTrigger>:=
    function(const pA, pB: TSqlTrigger): Integer
    begin
      Result:= CompareGroupKeys(pA.Name, pB.Name);
    end;
  TPsSort<TSqlTrigger>.Sort(FTrigFor, ByName);
  TPsSort<TSqlTrigger>.Sort(FTrigOther, ByName);

  var Procs:= FCatalog.ProcedureSet;
  FProcCount:= Length(Procs);
  var Groups:= TDictionary<string, TArray<TSqlProcedure>>.Create;
  try
    for var P in Procs do
    begin
      if P.Body.Found then
        Inc(FProcBodies)
      else
        Inc(FProcNotScanned);
      var Key:= P.Name.ToUpperInvariant;
      var G: TArray<TSqlProcedure>;
      if not Groups.TryGetValue(Key, G) then
        G:= [];
      Groups.AddOrSetValue(Key, G + [P]);
    end;
    var TokRx:= '(^|_)' + TRegEx.Escape(FTName.ToUpperInvariant) + '(_|$)';
    { Group-Object emits its groups sorted by name }
    for var Key in SortedText(Groups.Keys.ToArray) do
    begin
      var Group:= Groups[Key];
      var HitDecl: TArray<TSqlProcedure>:= [];
      var Unscanned: TArray<TSqlProcedure>:= [];
      for var P in Group do
        if not P.Body.Found then
          Unscanned:= Unscanned + [P]
        else if ContainsText(P.Tables, FTName) then
          HitDecl:= HitDecl + [P];
      if Length(HitDecl) > 0 then
      begin
        TPsSort<TSqlProcedure>.Sort(HitDecl,
          function(const pA, pB: TSqlProcedure): Integer
          begin
            Result:= CompareValue(pA.Body.StartLine, pB.Body.StartLine);
          end);
        var R: TProcRow;
        R.Decl:= HitDecl[0];
        R.Decls:= Length(Group);
        FProcRows:= FProcRows + [R];
        Continue;
      end;
      if (Length(Unscanned) > 0) and TRegEx.IsMatch(Key, TokRx, [roIgnoreCase]) then
      begin
        var U: TProcUnscanned;
        U.Decl:= Unscanned[0];
        U.Stale:= Unscanned[0].Body.Stale;
        FProcUnscanned:= FProcUnscanned + [U];
      end;
    end;
  finally
    Groups.Free;
  end;
  FIdxRows:= SqlIndexRows(FTName);
end;

{ ---- 6. the COLUMN form ---- }
procedure TConsumersChart.ReadColumn;
var
  Rt: TRoutineInfo;
  Hit: TSpanLit;
  LineText: string;
begin
  { case-SENSITIVE on the upper-case name: the SQL in this corpus is upper case (P23) }
  var ColRx:= WordRx(FColName.ToUpperInvariant);
  for var Id in FRtIds do
  begin
    if not FRtInfo.TryGetValue(Id, Rt) then
      Continue;
    if FirstSpanMatch(Rt, ColRx, Hit) then
      FSrvCol.AddOrSetValue(Id, Hit)
    else
      Inc(FSrvColSilent);
  end;
  for var T in FTrigFor do
  begin
    if ContainsText(T.Columns, FColName.ToUpperInvariant) then
      FTrigCol:= FTrigCol + [T];
    if T.Body.Stale then
      FTrigColStale:= FTrigColStale + [T]
    else if not T.Body.Found then
      FTrigColNoBody:= FTrigColNoBody + [T];
  end;
  for var P in FProcRows do
    if TRegEx.IsMatch(P.Decl.Body.Text, ColRx) then
      FProcCol:= FProcCol + [P];
  for var X in FIdxRows do
    if SqlLineText(X.Path, X.Line, LineText) and (LineText <> '') and TRegEx.IsMatch(LineText.ToUpperInvariant, ColRx) then
      FIdxCol:= FIdxCol + [X];
  ReadBindings;
end;

{ CLIENT data bindings of C, drawn only when the chain resolves to T (P32-P34) }
procedure TConsumersChart.ReadBindings;
var
  Ch: TDataSourceChain;
begin
  var Binds:= FIndex.AllRows(
    'SELECT sl.id AS id, sl.start_line AS line, sl.owner_name AS prop, f.path AS dfm, c.name AS ctl,' + sLineBreak +
    '       ' + ControlDataSourceSql('sl', 'c') + ' AS ds' + sLineBreak +
    '  FROM string_literals sl' + sLineBreak +
    '  JOIN files f ON f.id = sl.file_id' + sLineBreak +
    '  LEFT JOIN symbols c ON c.id = sl.symbol_id' + sLineBreak +
    Format(' WHERE sl.kind = ''dfm-prop'' AND UPPER(sl.text) = UPPER(''%s'')', [TChartsIndex.SqlText(FColName)]) + sLineBreak +
    '   AND sl.owner_name IN (' + TChartsIndex.SqlInList(BIND_PROPS) + ')',
    'sl.id');
  var Chains:= TDictionary<string, TDataSourceChain>.Create(TIStringComparer.Ordinal);
  try
    FBindAll:= Binds.Count;
    if Binds.Count > 0 then
      FWalker:= TChainWalker.Create(FIndex, FReader, FCatalog, FCatalog.TableSet);
    for var B in Binds do
    begin
      var Ds:= B.S('ds');
      if Ds = '' then
      begin
        Bump(FBindUnresolved, NO_DATASOURCE);
        Continue;
      end;
      var Dfm:= B.S('dfm');
      var Ck:= Dfm + '|' + Ds;
      if not Chains.TryGetValue(Ck, Ch) then
      begin
        Ch:= FWalker.DataSourceChain(Dfm, Ds);
        Chains.Add(Ck, Ch);
      end;
      if SameText(Ch.Grade, GRADE_STALE) then
        Inc(FBindStale)
      else if (Ch.ResolvedTable <> '') and SameText(Ch.ResolvedTable, FTName) then
      begin
        var R: TBindRow;
        R.Dfm:= Dfm;
        R.Line:= B.I('line');
        R.Control:= B.S('ctl');
        R.Prop:= B.S('prop');
        R.Ds:= Ds;
        R.Grade:= Ch.Grade;
        FBindDrawn:= FBindDrawn + [R];
      end
      else if Ch.ResolvedTable <> '' then
        Bump(FBindElsewhere, Ch.ResolvedTable)
      else
        Bump(FBindUnresolved, Ch.Grade);
    end;
  finally
    Chains.Free;
    Binds.Free;
  end;
end;

{ ---- 7. rows: the column form ---- }
procedure TConsumersChart.ColumnClusters;
begin
  var ReadKeys: TArray<Integer>:= [];
  var WriteKeys: TArray<Integer>:= [];
  for var K in FSrvCol.Keys do
  begin
    if FCertR.ContainsKey(K) or FLitR.ContainsKey(K) then
      ReadKeys:= ReadKeys + [K];
    if FCertW.ContainsKey(K) or FLitW.ContainsKey(K) then
      WriteKeys:= WriteKeys + [K];
  end;
  AddCluster(SIDE_LEFT, 'colreads', Format('reads %s and names %s', [FTName, FColName]), RoutineRows(ReadKeys, K_READ, FLitR, False),
    K_READ, True, '');
  AddCluster(SIDE_RIGHT, 'colwrites', Format('writes %s and names %s', [FTName, FColName]), RoutineRows(WriteKeys, K_WRITE, FLitW, False),
    K_WRITE, True, '');

  var Extra: TArray<string>:= [Format('%d binding(s) of %s in this index; only chains resolving to %s are drawn', [FBindAll, FColName, FTName])];
  for var K in SortedText(FBindElsewhere.Keys.ToArray) do
    Extra:= Extra + [Format('%d bound on a datasource that resolves to %s', [FBindElsewhere[K], K])];
  for var K in SortedText(FBindUnresolved.Keys.ToArray) do
    Extra:= Extra + [Format('%d whose datasource chain stops (%s)', [FBindUnresolved[K], K])];
  if FBindStale <> 0 then
    Extra:= Extra + [Format('%d in a form whose source differs from the index [stale source]', [FBindStale])];
  if FBindAll > 0 then
  begin
    var BindRows: TArray<TDotRow>:= [];
    for var B in FBindDrawn do
      BindRows:= BindRows + [NewRow(B.Control, B.Dfm, B.Line, Format('%s.%s = ''%s'' via %s -> %s (%s) -- %s',
        [B.Control, B.Prop, FColName, B.Ds, FTName, B.Grade, At(B.Dfm, B.Line)]), UnitNameOf(B.Dfm) + '; ' + B.Ds)];
    AddCluster(SIDE_LEFT, 'bindings', Format('bound to %s via a datasource on %s', [FColName, FTName]), BindRows, K_BIND, True,
      string.Join(#10, Extra));
  end;

  var Tx: TArray<string>:= [];
  if Length(FTrigColStale) > 0 then
    Tx:= Tx + [Format('%d trigger(s) FOR %s in a script that differs from the index [stale source] -- not scanned for %s: %s',
      [Length(FTrigColStale), FTName, FColName, TriggerList(FTrigColStale)])];
  if Length(FTrigColNoBody) > 0 then
    Tx:= Tx + [Format('%d trigger(s) FOR %s whose body was not found -- not scanned for %s: %s',
      [Length(FTrigColNoBody), FTName, FColName, TriggerList(FTrigColNoBody)])];
  var TrigRows: TArray<TDotRow>:= [];
  for var T in FTrigCol do
    TrigRows:= TrigRows + [NewRow(T.Name, T.Path, T.Body.StartLine, Format('%s FOR %s: NEW./OLD.%s in its body -- %s',
      [T.Name, FTName, FColName, At(T.Path, T.Body.StartLine)]), 'NEW/OLD.' + FColName)];
  AddCluster(SIDE_DB, 'coltriggers', Format('triggers FOR %s using %s', [FTName, FColName]), TrigRows, K_DB, False, string.Join(#10, Tx));

  { procedure bodies not scanned cannot name the column either }
  var Cpx: TArray<string>:= [];
  if FProcNotScanned <> 0 then
    Cpx:= Cpx + [Format('%d of %d procedure bodies not scanned', [FProcNotScanned, FProcCount])];
  for var U in FProcUnscanned do
    Cpx:= Cpx + [Format('%s: name contains %s, body not scanned %s', [U.Decl.Name, FTName,
      if U.Stale then '[stale source]' else '[body not scanned]'])];
  var ProcRows: TArray<TDotRow>:= [];
  for var P in FProcCol do
    ProcRows:= ProcRows + [NewRow(P.Decl.Name, P.Decl.Path, P.Decl.Body.StartLine, Format('%s: body names %s and %s -- %s',
      [P.Decl.Name, FTName, FColName, At(P.Decl.Path, P.Decl.Body.StartLine)]), 'body scan')];
  AddCluster(SIDE_DB, 'colprocs', Format('procedures naming %s and %s', [FTName, FColName]), ProcRows, K_DB, True, string.Join(#10, Cpx));

  var IdxRows: TArray<TDotRow>:= [];
  for var X in FIdxCol do
    IdxRows:= IdxRows + [NewRow(X.Name, X.Path, X.Line, Format('%s ON %s (...%s...) -- %s', [X.Name, FTName, FColName, At(X.Path, X.Line)]), '')];
  AddCluster(SIDE_DB, 'colindexes', Format('indexes on %s over %s', [FTName, FColName]), IdxRows, K_DB, False, '');
end;

{ ---- 7. rows: the table form ---- }
procedure TConsumersChart.TableClusters;
begin
  AddCluster(SIDE_LEFT, 'certreads', 'reads [certain]', RoutineRows(FCertR.Keys.ToArray, K_READ, FLitR, True), K_READ, False, '');
  AddCluster(SIDE_LEFT, 'infreads', 'reads, by SQL literal', RoutineRows(FInfR, K_READ, FLitR, False), K_READ, True, '');
  AddCluster(SIDE_RIGHT, 'certwrites', 'writes [certain]', RoutineRows(FCertW.Keys.ToArray, K_WRITE, FLitW, True), K_WRITE, False, '');
  AddCluster(SIDE_RIGHT, 'infwrites', 'writes, by SQL literal', RoutineRows(FInfW, K_WRITE, FLitW, False), K_WRITE, True, '');

  { R15: NOT on the readers side and no arrow into the focus -- a mention, not a read }
  var NameRows: TArray<TDotRow>:= [];
  for var P in FByNameKeys do
  begin
    var Ls:= FByNameFiles[P];
    var Kinds: TArray<string>:= [];
    var Lines: TArray<string>:= [];
    for var L in Ls do
    begin
      Kinds:= Kinds + [Format('%s :%d', [L.Kind, L.Line])];
      Lines:= Lines + [Format(':%d', [L.Line])];
    end;
    NameRows:= NameRows + [NewRow(UnitNameOf(P), P, Ls[0].Line, Format('%s: ''%s'' at %s', [FileNameOf(P), FTName, string.Join(', ', Kinds)]),
      Format('%d literal%s: %s', [Length(Ls), if Length(Ls) <> 1 then 's' else '', string.Join(' ', Lines)]))];
  end;
  AddCluster(SIDE_MENTION, 'byname', Format('mentions (not SQL) [by name] -- a literal equal to %s', [FTName]), NameRows, K_NAME, True, '');

  var TrigRows: TArray<TDotRow>:= [];
  for var T in FTrigFor do
  begin
    var Cl: string;
    if T.Body.Stale then
      Cl:= '[stale source]'
    else if T.Body.Found then
      Cl:= 'NEW/OLD: ' + ShortList(T.Columns, TRIGGER_COLUMNS_SHOWN)
    else
      Cl:= 'body not found';
    TrigRows:= TrigRows + [NewRow(T.Name, T.Path, T.Body.StartLine, Format('%s FOR %s -- %s', [T.Name, FTName, At(T.Path, T.Body.StartLine)]), Cl)];
  end;
  AddCluster(SIDE_DB, 'triggers', 'triggers FOR ' + FTName, TrigRows, K_DB, False, '');

  var OtherRows: TArray<TDotRow>:= [];
  for var T in FTrigOther do
    OtherRows:= OtherRows + [NewRow(T.Name, T.Path, T.Body.StartLine, Format('%s FOR %s: body names %s -- %s',
      [T.Name, T.Table, FTName, At(T.Path, T.Body.StartLine)]), 'FOR ' + T.Table)];
  AddCluster(SIDE_DB, 'othertriggers', Format('other triggers naming %s in their body', [FTName]), OtherRows, K_DB, True, '');

  var PExtra:= if FProcNotScanned <> 0 then Format('%d of %d procedure bodies not scanned', [FProcNotScanned, FProcCount]) else '';
  var ProcRows: TArray<TDotRow>:= [];
  for var P in FProcRows do
  begin
    var Decls:= if P.Decls > 1 then Format(' (%d declarations)', [P.Decls]) else '';
    ProcRows:= ProcRows + [NewRow(P.Decl.Name, P.Decl.Path, P.Decl.Body.StartLine, Format('%s: body names %s -- %s%s',
      [P.Decl.Name, FTName, At(P.Decl.Path, P.Decl.Body.StartLine), Decls]), 'body scan')];
  end;
  for var U in FProcUnscanned do
    ProcRows:= ProcRows + [NewRow(U.Decl.Name, U.Decl.Path, U.Decl.Body.StartLine, Format('%s: name contains %s; body not scanned',
      [U.Decl.Name, FTName]), if U.Stale then '[stale source]' else '[body not scanned]')];
  AddCluster(SIDE_DB, 'procs', 'procedures naming ' + FTName, ProcRows, K_DB, True, PExtra);

  var IdxRows: TArray<TDotRow>:= [];
  for var X in FIdxRows do
    IdxRows:= IdxRows + [NewRow(X.Name, X.Path, X.Line, Format('%s ON %s -- %s', [X.Name, FTName, At(X.Path, X.Line)]), '')];
  AddCluster(SIDE_DB, 'indexes', 'indexes ON ' + FTName, IdxRows, K_DB, False, '');
end;

{ the focus box: the table (or column), anchored on its script declaration }
function TConsumersChart.FocusLabel: string;
begin
  var Html:= TStringBuilder.Create;
  try
    Html.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    Html.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; focus </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS, if FColName <> '' then 'column' else 'table']));
    var FFile:= if FColName <> '' then FColFile else FTbl.Path;
    var FLine:= if FColName <> '' then FColLine else FTbl.Line;
    Inc(FAnchored);
    Html.Append(Format('<TR><TD ALIGN="LEFT" HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR>',
      [RowHref(FFile, FLine), XmlText(FLabel + ' -- ' + At(FFile, FLine)), FOCUS_INK, XmlText(FLabel)]));
    AddDisclosureRow(Html, FDeclText, LINE_INK);
    if FColName <> '' then
      AddDisclosureRow(Html, Format('column state %s: %s', [ColumnStateName(FCs.State), FCs.Caption]), LINE_INK)
    else
    begin
      var Older:= FTbl.OlderKeys;
      var OlderText:= if Length(Older) > 0 then Format('; %d more extracted only from an older one (%s)', [Length(Older), string.Join(', ', Older)]) else '';
      AddDisclosureRow(Html, Format('%d columns extracted from the newest declaration%s', [Length(FTbl.ColumnNames), OlderText]), LINE_INK);
    end;
    if Length(FFacts) = 0 then
      AddDisclosureRow(Html, 'this index has no SQL facts (0 sql_reads / 0 sql_writes)', LINE_INK);
    if FNoSql then
      AddDisclosureRow(Html, 'this index has no SQL at all (no facts, no upper-case SQL literal) -- ask the SERVER index', LINE_INK);
    { R7: BOTH grades, so the gap between fact and literal is visible }
    AddDisclosureRow(Html, Format('[certain] by fact: %d reader(s) / %d writer(s); [inferred] by SQL literal: %d reader(s) / %d writer(s)',
      [FCertR.Count, FCertW.Count, Length(FInfR), Length(FInfW)]), FOCUS_INK, FOCUS_ROW_POINTS);
    if FUnitLevel <> 0 then
      AddDisclosureRow(Html, Format('routines: %d reading / %d writing; plus %d unit(s) with an SQL literal naming %s ' +
        'outside any routine (%d read / %d write) -- drawn as (unit level) rows, not counted as routines',
        [FMR.Routines, FMW.Routines, FUnitLevel, FTName, FMR.Units, FMW.Units]), LINE_INK);
    if (FColName <> '') and (Length(FRtIds) > 0) then
      AddDisclosureRow(Html, Format('%d of those routines name %s in a literal; %d touch %s without naming it ' +
        '(SELECT *, positional or built-up SQL) -- every column row is [inferred]', [FSrvCol.Count, FColName, FSrvColSilent, FTName]), LINE_INK);
    if (FByNameLits > 0) and (FColName = '') then
    begin
      var Skipped:= if FByNameSkipped <> 0 then Format(' (+%d inside a routine already drawn)', [FByNameSkipped]) else '';
      AddDisclosureRow(Html, Format('[by name]: %d literal(s) equal to %s in %d unit(s)%s -- mentions, not reads',
        [FByNameLits, FTName, FByNameKeys.Count, Skipped]), LINE_INK);
    end;
    if (FCaseOnlyCount > 0) and (FColName = '') then
      AddDisclosureRow(Html, Format('%d literal(s) equal %s only case-insensitively, not drawn: %s', [FCaseOnlyCount, FTName, FCaseOnlyText]), LINE_INK);
    AddDisclosureRow(Html, Format('index-wide: %d read / %d write facts over %d routines (%d tables read by fact); ' +
      '%d upper-case SQL-verb literals name %d tables after FROM/JOIN',
      [FNReadFacts, FNWriteFacts, Length(FFacts), FNFactReadTabs, FNVerbLits, FNFromJoinTabs]), LINE_INK);
    AddDisclosureRow(Html, Format('script-derived schema: %d tables; %s', [Length(FCatalog.TableSet.Names), SCHEMA_NOTE]), LINE_INK);
    AddDisclosureRow(Html, 'positional Fields[i] reads and SQL built from non-literal pieces are not visible', LINE_INK);
    Html.Append('</TABLE>');
    Result:= Html.ToString;
  finally
    Html.Free;
  end;
end;

{ ---- 8. dot: the DB clusters first, reversed, then the focus, then readers / writers ---- }
procedure TConsumersChart.DrawDot;
var
  Style: TClusterStyle;
begin
  FSb.AppendLine('digraph consumers {');
  FSb.AppendLine('  rankdir=LR; newrank=true; bgcolor="transparent"; compound=true;');
  FSb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;');
  FSb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
  FSb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
  FSb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
  FSb.AppendLine('');
  var Focus:= FocusLabel;
  var Ordered: TArray<TCluster>:= [];
  for var I:= High(FClusters) downto 0 do
    if FClusters[I].Side = SIDE_DB then
      Ordered:= Ordered + [FClusters[I]];
  for var C in FClusters do
    if C.Side <> SIDE_DB then
      Ordered:= Ordered + [C];
  var SbDb:= TStringBuilder.Create;
  var SbRest:= TStringBuilder.Create;
  var SbEdges:= TStringBuilder.Create;
  try
    var SameNodes: TArray<string>:= [];
    var MentionNodes: TArray<string>:= [];
    var Ni:= 0;
    for var C in Ordered do
    begin
      Inc(Ni);
      var Nid:= 'n' + IntToStr(Ni);
      var Target:= if C.Side = SIDE_DB then SbDb else SbRest;
      Style:= TClusterStyle.Make(C.Border, C.Fill, C.Hdr);
      Style.RowInk:= ROW_INK;
      Style.LineInk:= LINE_INK;
      Style.FontSans:= FONT_SANS;
      Style.Style:= C.Style;
      var Ports:= AddRowCluster(Target, Format('cluster_%s_%d', [C.Id, Ni]), Nid, C.Title, C.Subtitle, C.Rows, Style);
      var Dashed:= if C.Style.Contains('dashed') then ', style="dashed"' else '';
      if C.Side = SIDE_LEFT then
      begin
        for var I:= 0 to High(Ports) do
          if C.Rows[I].Href <> '' then
            SbEdges.AppendLine(Format('  %s -> focus [color="%s"%s];', [Ports[I], C.Border, Dashed]));
      end
      else if C.Side = SIDE_RIGHT then
      begin
        for var I:= 0 to High(Ports) do
          if C.Rows[I].Href <> '' then
            SbEdges.AppendLine(Format('  focus -> %s [color="%s", penwidth=2.2%s];', [Ports[I], C.Border, Dashed]));
      end
      else if C.Side = SIDE_DB then
      begin
        SameNodes:= SameNodes + [Nid];
        SbEdges.AppendLine(Format('  focus -> %s [color="%s", arrowhead=none%s];', [Nid, C.Border, Dashed]));
      end
      else
      begin
        { a neutral dotted line, no arrowhead: the literal MENTIONS the table }
        MentionNodes:= MentionNodes + [Nid];
        SbEdges.AppendLine(Format('  focus -> %s [color="%s", style="dotted", arrowhead=none, label=" mentions "];', [Nid, C.Border]));
      end;
    end;
    FSb.Append(SbDb.ToString);
    FSb.AppendLine('  subgraph cluster_focus {');
    FSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
    FSb.AppendLine('    label=""; margin=12;');
    FSb.AppendLine(Format('    focus [label=<%s>];', [Focus]));
    FSb.AppendLine('  }');
    FSb.Append(SbRest.ToString);
    FSb.AppendLine('');
    FSb.Append(SbEdges.ToString);
    { BOTTOM = the database side: the same rank as the focus stacks it under it }
    SameNodes:= SameNodes + MentionNodes;
    if Length(SameNodes) > 0 then
      FSb.AppendLine(Format('  { rank=same; focus; %s; }', [string.Join('; ', SameNodes)]));
    FSb.AppendLine('}');
  finally
    SbEdges.Free;
    SbRest.Free;
    SbDb.Free;
  end;
end;

{ the emitter object's properties, in the PS order (the file paths excluded) }
function TConsumersChart.ResultFields: TArray<TMetaField>;
begin
  var InfNames: TArray<string>:= [];
  for var K in FInfR do
    if K > 0 then
      InfNames:= InfNames + [RoutineQ(K)];
  var CertWNames: TArray<string>:= [];
  for var K in FCertW.Keys do
    CertWNames:= CertWNames + [RoutineQ(K)];
  var ByNameLines: TArray<string>:= [];
  for var P in FByNameKeys do
  begin
    var Ls: TArray<string>:= [];
    for var L in FByNameFiles[P] do
      Ls:= Ls + [IntToStr(L.Line)];
    ByNameLines:= ByNameLines + [UnitNameOf(P) + ':' + string.Join('+', Ls)];
  end;
  var TrigNames: TArray<string>:= [];
  for var T in FTrigFor do
    TrigNames:= TrigNames + [TriggerAt(T)];
  var ProcNames: TArray<string>:= [];
  for var P in FProcRows do
    ProcNames:= ProcNames + [P.Decl.Name];
  var SrvNames: TArray<string>:= [];
  for var K in FSrvCol.Keys do
    SrvNames:= SrvNames + [RoutineQ(K)];
  var ColTrigNames: TArray<string>:= [];
  for var T in FTrigCol do
    ColTrigNames:= ColTrigNames + [T.Name];
  var BindRows: TArray<string>:= [];
  for var B in FBindDrawn do
    BindRows:= BindRows + [Format('%s:%s', [At(B.Dfm, B.Line), B.Control])];
  var ColumnField:= TMetaField.Str('Column', FColName);
  if FColName = '' then
    ColumnField.Json:= 'null';
  { `Measure-Object -Sum` is a double; $byNameLits falls back to the int 0 }
  var ByNameField:= if FByNameLits > 0 then TMetaField.Real('ByNameLiterals', FByNameLits) else TMetaField.Int('ByNameLiterals', 0);
  var ColLine:= if FColName <> '' then At(FColFile, FColLine) else '';
  var ColState:= if FHasCs then FCs.State else '';
  var ColLabel:= if FHasCs then FCs.Caption else '';
  Result:= [TMetaField.Bool('TestChart', False), TMetaField.Str('Table', FTName), ColumnField,
    TMetaField.Bool('ColumnOlderOnly', FColOlder), TMetaField.Str('ColumnState', ColState), TMetaField.Str('ColumnLabel', ColLabel),
    TMetaField.Str('ColumnLine', ColLine), TMetaField.Int('Declarations', Length(FTbl.Declarations)),
    TMetaField.Int('Columns', Length(FTbl.ColumnNames)), TMetaField.Int('Readers', FMR.Routines), TMetaField.Int('Writers', FMW.Routines),
    TMetaField.Int('ReaderUnits', FMR.Units), TMetaField.Int('WriterUnits', FMW.Units)];
  Result:= Result + [TMetaField.Int('CertainReaders', FCertR.Count), TMetaField.Int('CertainWriters', FCertW.Count),
    TMetaField.Int('InferredReaders', Length(FInfR)), TMetaField.Int('InferredWriters', Length(FInfW)),
    TMetaField.Str('InferredReaderNames', string.Join(',', SortedText(InfNames))),
    TMetaField.Str('CertainWriterNames', string.Join(',', SortedText(CertWNames))), TMetaField.Int('UnitLevelUnits', FUnitLevel),
    TMetaField.Int('ByNameUnits', FByNameKeys.Count), ByNameField, TMetaField.Str('ByNameCaseOnly', FCaseOnlyText),
    TMetaField.Str('ByNameLines', string.Join(',', ByNameLines))];
  Result:= Result + [TMetaField.Int('Triggers', Length(FTrigFor)), TMetaField.Str('TriggerNames', string.Join(',', TrigNames)),
    TMetaField.Int('OtherTriggers', Length(FTrigOther)), TMetaField.Int('Procedures', Length(FProcRows)),
    TMetaField.Str('ProcedureNames', string.Join(',', SortedText(ProcNames))), TMetaField.Int('ProcsUnscanned', Length(FProcUnscanned)),
    TMetaField.Str('ProcBodies', Format('%d/%d', [FProcBodies, FProcCount])), TMetaField.Int('Indexes', Length(FIdxRows)),
    TMetaField.Int('ServerRoutines', FSrvCol.Count), TMetaField.Str('ServerRoutineNames', string.Join(',', SortedText(SrvNames))),
    TMetaField.Int('SilentRoutines', FSrvColSilent), TMetaField.Int('ColumnTriggers', Length(FTrigCol)),
    TMetaField.Str('ColumnTriggerNames', string.Join(',', ColTrigNames)), TMetaField.Int('ColumnTriggersStale', Length(FTrigColStale)),
    TMetaField.Int('ColumnTriggersNoBody', Length(FTrigColNoBody)), TMetaField.Int('ColumnProcedures', Length(FProcCol)),
    TMetaField.Int('ColumnIndexes', Length(FIdxCol))];
  Result:= Result + [TMetaField.Int('IndexBindings', FBindAll), TMetaField.Int('DrawnBindings', Length(FBindDrawn)),
    TMetaField.Str('DrawnBindingRows', string.Join(',', BindRows)), TMetaField.Real('BindingsElsewhere', SumOf(FBindElsewhere)),
    TMetaField.Real('BindingsUnresolved', SumOf(FBindUnresolved)), TMetaField.Int('BindingsStale', FBindStale),
    TMetaField.Int('IndexReadFacts', FNReadFacts), TMetaField.Int('IndexWriteFacts', FNWriteFacts),
    TMetaField.Int('IndexFactSymbols', Length(FFacts)), TMetaField.Int('IndexFactReadTables', FNFactReadTabs),
    TMetaField.Int('IndexVerbLiterals', FNVerbLits), TMetaField.Int('IndexFromJoinTables', FNFromJoinTabs),
    TMetaField.Bool('NoSqlFacts', Length(FFacts) = 0), TMetaField.Bool('NoSql', FNoSql),
    TMetaField.Int('Clusters', Length(FClusters) + 1)];
end;

function TConsumersChart.Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  SelectTarget(pArgs.Target);
  CheckRoles;
  ResolveTable;
  ReadIndexWide;
  ReadConsumers;
  RecheckColumn;
  ReadByName;
  ReadDatabase;
  if FColName <> '' then
  begin
    ReadColumn;
    ColumnClusters;
  end
  else
    TableClusters;
  FLabel:= if FColName <> '' then FTName + '.' + FColName else FTName;
  DrawDot;

  var Msgs: TArray<string>;
  Result.Layout:= DotLayout(pArgs.Dot, FSb.ToString, pOutDir, 'consumers_' + TRegEx.Replace(FLabel, '[^A-Za-z0-9]', '_'), Msgs);
  Result.LeftCount:= FMR.Routines;
  Result.RightCount:= FMW.Routines;
  Result.ClickTargets:= Result.Layout.Anchors;
  Result.AllClickable:= Result.Layout.Anchors >= FAnchored;
  Result.Fields:= ResultFields + [TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', FAnchored),
    TMetaField.Bool('AllClickable', Result.AllClickable)];
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  { New-DiagramArtifact refuses before the PS emitter is reached }
  if pArgs.SqlDbPath = '' then
    raise EChartsQuestion.Create('consumers needs -SqlDbPath: the SQL-script index clone (charts\scratch\db\SQL-drag-lint-sql.sqlite)');
  var Chart:= TConsumersChart.Create(pArgs);
  try
    Result:= Chart.Emit(pArgs, pOutDir);
  finally
    Chart.Free;
  end;
end;

initialization
  RegisterChartQuestion(CONSUMERS_ID, Emit);

end.
