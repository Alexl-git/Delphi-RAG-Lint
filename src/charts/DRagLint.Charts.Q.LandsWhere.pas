unit DRagLint.Charts.Q.LandsWhere;

(* The `lands-where` question in-process: a port of charts\src\Emit-LandsWhere.ps1 (spec s11;
  the PS output is the reference, P3). This FIELD, where does it land in the database --
  which server code writes and reads it, which TABLE.COLUMN it is, which triggers and
  procedures touch that column, and which forms show it?

  Two selection kinds, dispatched on what resolves: an ORM object property (or its backing
  field) of a Tmc<T> / Imc<T> class, or a DFM-bound field <Form>.<Control> whose datasource
  chain is the one feeds-from walks (TChainWalker.FieldBindingChains), so the two verbs cannot
  disagree about which table a control feeds. Three indexes, none of them the database:
  -DbPath (CLIENT: the ORM classes and the DFM bindings), -ServerDbPath (SERVER:
  TDataService_<T>_SERVER, the write / read path) and -SqlDbPath (the SQL scripts: TABLE.COLUMN,
  triggers, procedures). Their roles are checked so a swapped pair refuses instead of rendering
  an empty chart. The table is a naming convention (Tmc<T>.PROP = T.PROP) and is drawn as one:
  dashed, graded with the numbers measured on this run.

  Not ported: the -SourceOverride and -TestHideColumn test hooks (New-DiagramArtifact never
  passes them, so TestChart is always false), and the Write-Host progress lines. A missing
  -ServerDbPath / -SqlDbPath refuses with New-DiagramArtifact's own message, the layer that
  checks them before the PS emitter is reached. The PS local functions Format-N,
  Get-DataServiceClassCount, Get-SqlTableSymbolCount, Get-ParamByNameStats, Get-WordRx and
  Get-RowAnchors are free routines below; New-Row, Find-OrmProperty, Add-Box and Add-Edge are
  private methods of TLandsWhereChart, and the script's numbered sections are its methods.

  PS traps closed: `-match`, `-eq`, `-in`, `-contains` and `switch` are case-insensitive, while
  [regex]::Match / IsMatch are not (Get-WordRx is case-SENSITIVE on purpose); hashtables are
  case-insensitive (TIStringComparer.Ordinal); Sort-Object is not stable (TPsSort) and orders
  text with CompareGroupKeys; Format-N is the invariant 'N0' (thousands grouped with ','); a
  $null Table / ServerClass is JSON null. *)

interface

const
  /// <summary>The registered question id.</summary>
  LANDS_WHERE_ID = 'lands-where';

implementation

uses
  System.SysUtils, System.Generics.Defaults, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Source, DRagLint.Charts.Sql, DRagLint.Charts.Columns, DRagLint.Charts.Chain,
  DRagLint.Charts.Tools, DRagLint.Charts.PsSort;

const
  PROP_BORDER = '#0F766E';
  PROP_FILL = '#E2F1EF';
  PROP_HDR = '#0F766E';
  CTL_BORDER = '#7C3AED';
  CTL_FILL = '#F3EEFF';
  CTL_HDR = '#7C3AED';
  WRITE_BORDER = '#C2410C';
  WRITE_FILL = '#FFF4E6';
  WRITE_HDR = '#C2410C';
  READ_BORDER = '#3B5BDB';
  READ_FILL = '#EDF2FF';
  READ_HDR = '#3B5BDB';
  DB_BORDER = '#BE185D';
  DB_FILL = '#FDF2F8';
  DB_HDR = '#BE185D';
  STOP_BORDER = '#6B7280';
  STOP_FILL = '#F3F4F6';
  STOP_HDR = '#6B7280';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  SOLID_STYLE = 'rounded,filled';
  DASHED_STYLE = 'rounded,filled,dashed';
  K_PROP = 'prop';
  K_CTL = 'ctl';
  K_WRITE = 'write';
  K_READ = 'read';
  K_DB = 'db';
  K_STOP = 'stop';
  KIND_ORM = 'orm';
  KIND_DFM = 'dfm';
  G_CERTAIN = 'certain';
  G_INFERRED = 'inferred';
  S_STALE = 'stale';
  S_QUOTED = 'quoted';
  O_COLUMN = 'column';
  ORM_CLASS_RX = '^(Tmc|Imc)(.+)$';
  DATASERVICE_RX = '^TDataService_(.+)_SERVER$';
  SELECTION_RX = '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$';
  { Measured 2026-09-23 against the live Firebird DB, VALIDATION ONLY (P16). }
  SCHEMA_NOTE = '5 live tables are not in the scripts (2026-09-23)';
  NOT_ORM = 'not an ORM object property (class is not Tmc<T>) and not a DFM-bound field';
  FIELD_NAME_PROP = 'FieldName';
  { a selection of more than <Form>.<Control> is a full qualified name }
  FORM_CONTROL_SEGMENTS = 2;
  { the Tmc / Imc prefix a convention property's class name carries }
  CLASS_PREFIX_LEN = 3;
  ORM_TABLE_GROUP = 2;

type
  { a symbols row the PS read as $selSym / Find-OrmProperty's result; Present False = $null }
  TSymRow = record
    Present: Boolean;
    Id, Line, Pid: Integer;
    Name, Kind, QName, Path, PName, PKind, PHer: string;
  end;

  { the selected component (the PS $ctl) }
  TCtlRow = record
    Id, Pid, Line: Integer;
    Name, QName, Sig, Path, PName: string;
  end;

  { the index-wide naming-convention numbers (the PS $conv) }
  TConvStats = record
    Props, OnTable, Column, NQuoted: Integer;
    NonColumn, Quoted, Stale: string;
  end;

  { Get-ParamByNameStats }
  TPbnStats = record
    All, InDataService, Column: Integer;
  end;

  TSrvRoutine = record
    Id, A, B: Integer;
    Name, QName: string;
  end;

  TSrvAccess = record
    Line, Eid: Integer;
    Mode, Rt: string;
  end;

  TSrvPbn = record
    Line, Eid: Integer;
    Txt: string;
  end;

  TSrvLiteral = record
    Line: Integer;
    Txt: string;
  end;

  TEvidence = record
    Line: Integer;
    Grade, Text: string;
  end;

  { One lands-where chart being drawn: the PS script-scope state ($sb, $ni, $anchored, the
    selection, the server / database / client rows) and its local functions. Owns the three
    indexes, their readers, the SQL catalogue and the walker. }
  TLandsWhereChart = class  // dl:ok god-class@9672, high-response@9672 -- REVIEWED 2026-10-14: the class IS Emit-LandsWhere.ps1 (one script, one chart): its fields are the script-scope state the PS local functions share, its methods one per script section and local function; splitting it would break the line-for-line port the parity harness checks
  private
    FDbPath      : string;
    FIndex       : TChartsIndex;
    FReader      : TSourceReader;
    FSrvDb       : string;
    FSrvIndex    : TChartsIndex;
    FSqlDb       : string;
    FSqlIndex    : TChartsIndex;
    FSqlReader   : TSourceReader;
    FCatalog     : TSqlCatalog;
    FWalker      : TChainWalker;
    FSb          : TStringBuilder;
    FCap         : Integer;
    FNi          : Integer;
    FAnchored    : Integer;
    FNDsClasses  : Integer;
    FOlCli       : TOrmLinksState;
    FOlSrv       : TOrmLinksState;
    FSel         : string;
    FKind        : string;
    FSelSym      : TSymRow;
    FCtl         : TCtlRow;
    FIx          : TFieldBindingChains;
    FConv        : TConvStats;
    FConvGrade   : string;
    FPbn         : TPbnStats;
    FSelRows     : TArray<TDotRow>;
    FBindRow     : TFieldBinding;
    FHasChain    : Boolean;
    FChain       : TDataSourceChain;
    FHasRpr      : Boolean;
    FRpr         : TRePointTable;
    FTName       : string;
    FProp        : string;
    FStop        : string;
    FChainOutcome: string;
    FOrmSym      : TSymRow;
    FTbl         : TSqlTable;
    FColState    : string;
    FHasCs       : Boolean;
    FCs          : TSqlColumnState;
    FHasColumn   : Boolean;
    FCol         : string;
    FColRow      : TDotRow;
    FHasColRow   : Boolean;
    FSrvWrite    : TArray<TDotRow>;
    FSrvRead     : TArray<TDotRow>;
    FSrvOther    : TArray<TDotRow>;
    FSrvClass    : string;
    FSrvElsewhere: Integer;
    FSrvFile     : string;
    FSrvSqlHit   : Boolean;
    FSrvSqlLine  : Integer;
    FSrvSqlRtn   : string;
    FTrigRows    : TArray<TDotRow>;
    FProcRows    : TArray<TDotRow>;
    FTrigNames   : TArray<string>;
    FProcNames   : TArray<string>;
    FTrigStale   : Integer;
    FProcUnscanned: Integer;
    FBindSame    : TArray<TFieldBinding>;
    FBindOther   : TArray<TFieldBinding>;
    FBindSorted  : TArray<TFieldBinding>;
    FBindRowsOut : TArray<TDotRow>;
    FNTop        : string;
    FNProp       : string;
    FNCol        : string;
    function NewRow(const pCaption, pFile: string; pLine: Integer; const pTip, pNote: string): TDotRow;
    function FindOrmProperty(const pClassName, pName: string): TSymRow;
    function AddBox(const pTitle, pSub: string; const pRows: TArray<TDotRow>; const pKind: string; pDashed: Boolean): string;
    procedure AddEdge(const pFrom, pTo, pLabel: string; pDashed: Boolean; pBack: Boolean = False; const pColor: string = '');
    procedure CheckRoles;
    procedure SelectField(const pTarget: string);
    procedure MeasureConvention;
    procedure MeasureParamByName;
    procedure ResolveOrm;  // dl:ok unused-private-member@bbd3 -- REVIEWED 2026-10-14: linter FP -- Emit calls it as the bare then / else statement of `if FKind = KIND_ORM then ResolveOrm else ResolveDfm;`, which the extractor emits no call ref for (logged to draglint-gaps.log)
    procedure ResolveDfm;  // dl:ok unused-private-member@717d -- REVIEWED 2026-10-14: linter FP -- Emit calls it as the bare then / else statement of `if FKind = KIND_ORM then ResolveOrm else ResolveDfm;`, which the extractor emits no call ref for (logged to draglint-gaps.log)
    procedure ReadColumn;
    procedure ReadServer;
    procedure RecheckColumn;
    procedure ReadDatabase;
    procedure ReadClient;
    procedure DrawSelection;
    procedure DrawColumn;
    procedure DrawServer;
    procedure DrawDatabase;
    procedure DrawClient;
    procedure DrawFocus;
    function ResultFields: TArray<TMetaField>;
  public
    constructor Create(const pArgs: TQuestionArgs);
    destructor Destroy; override;
    function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
  end;

{ Format-N: [int].ToString('N0', InvariantCulture) }
function FormatN(pN: Integer): string;
begin
  Result:= FormatFloat('#,##0', pN, TFormatSettings.Invariant);
end;

{ Get-WordRx: the name as a whole word, `$` counting as a word character (case-SENSITIVE) }
function WordRx(const pName: string): string;
begin
  Result:= '(?<![A-Za-z0-9_$])' + TRegEx.Escape(pName) + '(?![A-Za-z0-9_$])';
end;

function CountOf(pIndex: TChartsIndex; const pSql: string): Integer;
begin
  var Rows:= pIndex.Query(pSql);
  try
    Result:= Rows[0].I('n');
  finally
    Rows.Free;
  end;
end;

{ Get-DataServiceClassCount }
function DataServiceClassCount(pIndex: TChartsIndex): Integer;
begin
  Result:= CountOf(pIndex, 'SELECT COUNT(*) AS n FROM symbols WHERE kind = ''class'' AND name GLOB ''TDataService_*_SERVER''');
end;

{ Get-SqlTableSymbolCount }
function SqlTableSymbolCount(pIndex: TChartsIndex): Integer;
begin
  Result:= CountOf(pIndex, 'SELECT COUNT(*) AS n FROM symbols WHERE kind = ''sql_table''');
end;

{ Get-RowAnchors: "Label:Line" of every anchored row }
function RowAnchors(const pRows: TArray<TDotRow>): string;
begin
  var Parts: TArray<string>:= [];
  for var R in pRows do
    if R.Href <> '' then
      Parts:= Parts + [R.Caption + ':' + R.Line];
  Result:= string.Join(',', Parts);
end;

{ `Sort-Object` over text }
function SortedNames(const pNames: TArray<string>): TArray<string>;
begin
  Result:= Copy(pNames);
  TPsSort<string>.Sort(Result,
    function(const pA, pB: string): Integer
    begin
      Result:= CompareGroupKeys(pA, pB);
    end);
end;

{ `Sort-Object Dfm, Line` }
procedure SortBindings(var pRows: TArray<TFieldBinding>);
begin
  TPsSort<TFieldBinding>.Sort(pRows,
    function(const pA, pB: TFieldBinding): Integer
    begin
      Result:= CompareGroupKeys(pA.Dfm, pB.Dfm);
      if Result = 0 then
        Result:= pA.Line - pB.Line;
    end);
end;

{ "file:line" of a tip }
function At(const pPath: string; pLine: Integer): string;
begin
  Result:= Format('%s:%d', [FileNameOf(pPath), pLine]);
end;

function SymRowOf(pRow: TIndexRow): TSymRow;
begin
  Result.Present:= True;
  Result.Id:= pRow.I('id');
  Result.Name:= pRow.S('name');
  Result.Kind:= pRow.S('kind');
  Result.QName:= pRow.S('q');
  Result.Line:= pRow.I('line');
  Result.Path:= pRow.S('path');
  Result.Pid:= pRow.I('pid');
  Result.PName:= pRow.S('pname');
  Result.PKind:= pRow.S('pkind');
  Result.PHer:= pRow.S('pher');
end;

{ how many ~ counts a case-insensitive hashtable keeps (the PS $byT / $byO / $oc2) }
procedure Bump(pCounts: TDictionary<string, Integer>; const pKey: string);
var
  N: Integer;
begin
  if not pCounts.TryGetValue(pKey, N) then
    N:= 0;
  pCounts.AddOrSetValue(pKey, N + 1);
end;

{ "<n> more ... (<key> <n>, ...)" of a count table, keys in Sort-Object order }
function CountList(pCounts: TDictionary<string, Integer>; out pSum: Integer): string;
begin
  pSum:= 0;
  var Parts: TArray<string>:= [];
  for var K in SortedNames(pCounts.Keys.ToArray) do
  begin
    Inc(pSum, pCounts[K]);
    Parts:= Parts + [Format('%s %d', [K, pCounts[K]])];
  end;
  Result:= string.Join(', ', Parts);
end;

constructor TLandsWhereChart.Create(const pArgs: TQuestionArgs);
var
  Note: string;
begin
  inherited Create;
  FDbPath:= pArgs.GuardedDb;
  FSrvDb:= CloneDb(pArgs.ServerDbPath, pArgs.CloneRoot, Note);
  FSqlDb:= CloneDb(pArgs.SqlDbPath, pArgs.CloneRoot, Note);
  FIndex:= TChartsIndex.Create(FDbPath);
  FReader:= TSourceReader.Create(FIndex);
  FSrvIndex:= TChartsIndex.Create(FSrvDb);
  FSqlIndex:= TChartsIndex.Create(FSqlDb);
  FSqlReader:= TSourceReader.Create(FSqlIndex);
  FCatalog:= TSqlCatalog.Create(FSqlIndex, FSqlReader);
  FWalker:= TChainWalker.Create(FIndex, FReader, FCatalog, FCatalog.TableSet);
  FSb:= TStringBuilder.Create;
  FCap:= pArgs.Cap;
  FColState:= 'n/a';
end;

destructor TLandsWhereChart.Destroy;
begin
  FSb.Free;
  FWalker.Free;
  FCatalog.Free;
  FSqlReader.Free;
  FSqlIndex.Free;
  FSrvIndex.Free;
  FReader.Free;
  FIndex.Free;
  inherited Destroy;
end;

{ New-Row: every anchored row counts toward Expected, shown or not }
function TLandsWhereChart.NewRow(const pCaption, pFile: string; pLine: Integer; const pTip, pNote: string): TDotRow;
begin
  Inc(FAnchored);
  Result:= TDotRow.Anchored(pCaption, pLine, RowHref(pFile, pLine), pTip, pNote);
end;

{ Find-OrmProperty: the property pName of the class / interface pClassName }
function TLandsWhereChart.FindOrmProperty(const pClassName, pName: string): TSymRow;
begin
  Result:= Default(TSymRow);
  var Rows:= FIndex.Query(
    'SELECT s.id AS id, s.name AS name, s.kind AS kind, s.qualified_name AS q, s.start_line AS line, f.path AS path,' + sLineBreak +
    '       p.id AS pid, p.name AS pname, p.kind AS pkind, p.heritage AS pher' + sLineBreak +
    '  FROM symbols s JOIN files f ON f.id = s.file_id JOIN symbols p ON p.id = s.parent_id' + sLineBreak +
    Format(' WHERE s.kind = ''property'' AND UPPER(p.name) = UPPER(''%s'') AND p.kind IN (''class'',''interface'')',
      [TChartsIndex.SqlText(pClassName)]) + sLineBreak +
    Format('   AND UPPER(s.name) = UPPER(''%s'')', [TChartsIndex.SqlText(pName)]));
  try
    if Rows.Count > 0 then
      Result:= SymRowOf(Rows[0]);
  finally
    Rows.Free;
  end;
end;

{ Add-Box: one row cluster, capped; the rows past the cap leave Expected }
function TLandsWhereChart.AddBox(const pTitle, pSub: string; const pRows: TArray<TDotRow>; const pKind: string;
  pDashed: Boolean): string;
var
  Style: TClusterStyle;
begin
  var Top:= TRanked<TDotRow>.TopRanked(pRows, FCap, nil);
  var Shown:= Top.Shown;
  { Select-Object -Skip $Cap: the rows past the cap }
  var Skip:= if FCap > 0 then FCap else 0;
  for var K:= Skip to High(pRows) do
    if pRows[K].Href <> '' then
      Dec(FAnchored);
  var D:= DisclosureText(Top.HiddenRows, 0, 'rows');
  if D <> '' then
    Shown:= Shown + [NoteRow(D)];
  Inc(FNi);
  Result:= 'n' + IntToStr(FNi);
  if pKind = K_PROP then
    Style:= TClusterStyle.Make(PROP_BORDER, PROP_FILL, PROP_HDR)
  else if pKind = K_CTL then
    Style:= TClusterStyle.Make(CTL_BORDER, CTL_FILL, CTL_HDR)
  else if pKind = K_WRITE then
    Style:= TClusterStyle.Make(WRITE_BORDER, WRITE_FILL, WRITE_HDR)
  else if pKind = K_READ then
    Style:= TClusterStyle.Make(READ_BORDER, READ_FILL, READ_HDR)
  else if pKind = K_DB then
    Style:= TClusterStyle.Make(DB_BORDER, DB_FILL, DB_HDR)
  else
    Style:= TClusterStyle.Make(STOP_BORDER, STOP_FILL, STOP_HDR);
  Style.RowInk:= ROW_INK;
  Style.LineInk:= LINE_INK;
  Style.FontSans:= FONT_SANS;
  Style.Style:= if pDashed then DASHED_STYLE else SOLID_STYLE;
  AddRowCluster(FSb, Format('cluster_%s_%d', [pKind, FNi]), Result, pTitle, pSub, Shown, Style);
end;

{ Add-Edge }
procedure TLandsWhereChart.AddEdge(const pFrom, pTo, pLabel: string; pDashed, pBack: Boolean; const pColor: string);
begin
  var St:= if pDashed then 'dashed' else 'solid';
  var C:= if pColor <> '' then pColor else LINE_INK;
  var Back:= if pBack then ', dir=back' else '';
  FSb.AppendLine(Format('  %s -> %s [style=%s, color="%s", label=" %s "%s];', [pFrom, pTo, St, C, XmlText(pLabel), Back]));
end;

{ ---- 0. roles: each clone must be what its parameter says ---- }
procedure TLandsWhereChart.CheckRoles;
begin
  if Length(FCatalog.TableSet.Names) = 0 then
    raise EChartsQuestion.CreateFmt('lands-where: %s is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone', [FSqlDb]);
  if (SqlTableSymbolCount(FIndex) > 0) or (SqlTableSymbolCount(FSrvIndex) > 0) then
    raise EChartsQuestion.Create('lands-where: a SQL-script index was passed as a Delphi clone -- -DbPath takes CLIENT, -ServerDbPath SERVER, ' +
      '-SqlDbPath the scripts');
  FNDsClasses:= DataServiceClassCount(FSrvIndex);
  if FNDsClasses = 0 then
    raise EChartsQuestion.CreateFmt('lands-where: %s holds no TDataService_<T>_SERVER class -- -ServerDbPath takes the SERVER clone ' +
      '(SERVER-MicroniteMW1Service.sqlite), where the write and read path live', [FSrvDb]);
  if DataServiceClassCount(FIndex) > 0 then
    raise EChartsQuestion.CreateFmt('lands-where: %s holds TDataService_<T>_SERVER classes, so it is a SERVER index -- -DbPath takes the CLIENT ' +
      'clone (the ORM classes and the DFM bindings); the SERVER clone goes in -ServerDbPath', [FDbPath]);
  { path B detector: orm_links on BOTH Delphi clones (0 today) }
  FOlCli:= OrmLinksState(FIndex);
  FOlSrv:= OrmLinksState(FSrvIndex);
end;

{ ---- 1. the selection: ORM property / field, or <Form>.<Control> ---- }
procedure TLandsWhereChart.SelectField(const pTarget: string);
begin
  FSel:= PsTrim(pTarget);
  if not TRegEx.IsMatch(FSel, SELECTION_RX, [roIgnoreCase]) then
    raise EChartsQuestion.CreateFmt('lands-where: -Field takes <Unit>.<Tmc class>.<property> or <Form>.<Control>, got ''%s''', [pTarget]);
  var Sym:= FIndex.Query(
    'SELECT s.id AS id, s.name AS name, s.kind AS kind, s.qualified_name AS q, s.start_line AS line, f.path AS path,' + sLineBreak +
    '       p.id AS pid, p.name AS pname, p.kind AS pkind, p.heritage AS pher' + sLineBreak +
    '  FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbols p ON p.id = s.parent_id' + sLineBreak +
    Format(' WHERE UPPER(s.qualified_name) = UPPER(''%s'')', [TChartsIndex.SqlText(FSel)]));
  try
    if Sym.Count > 0 then
      FSelSym:= SymRowOf(Sym[0]);
  finally
    Sym.Free;
  end;
  var Segs:= FSel.Split(['.']);
  if FSelSym.Present then
  begin
    if not (SameText(FSelSym.Kind, 'property') or SameText(FSelSym.Kind, 'field')) then
      raise EChartsQuestion.CreateFmt('lands-where: %s is a %s -- %s. lands-where selects a property or field of a Tmc<T> / Imc<T> object.',
        [FSel, FSelSym.Kind, NOT_ORM]);
    if not TRegEx.IsMatch(FSelSym.PName, ORM_CLASS_RX, [roIgnoreCase]) or
      not (SameText(FSelSym.PKind, 'class') or SameText(FSelSym.PKind, 'interface')) then
      raise EChartsQuestion.CreateFmt('lands-where: %s is on %s -- %s.', [FSel, FSelSym.PName, NOT_ORM]);
    FKind:= KIND_ORM;
    { refuse BEFORE the index-wide work: the class name must name a table }
    var Tn0:= TRegEx.Match(FSelSym.PName, ORM_CLASS_RX).Groups[ORM_TABLE_GROUP].Value;
    if FCatalog.TableSet.Table(Tn0) = nil then
    begin
      { the FIB$ tables: `$` is not legal in a Delphi identifier, so the class says `_` }
      var Declared:= ' (script-derived; the scripts may lag the live schema)';
      for var N in FCatalog.TableSet.Names do
        if SameText(N.Replace('$', '_'), Tn0.ToUpperInvariant) then
        begin
          Declared:= ' (the scripts declare ' + N + ')';
          Break;
        end;
      raise EChartsQuestion.CreateFmt('lands-where: no table named %s in the SQL index%s -- the name was derived from ' +
        '%s by the Tmc<T> / Imc<T> naming convention. %s.', [Tn0, Declared, FSelSym.PName, SCHEMA_NOTE]);
    end;
    Exit;
  end;
  var Fids: TArray<string>:= [];
  var Forms:= FIndex.Query(
    'SELECT s.file_id AS fid, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +  // dl:ok sql-injection-concat@3492 -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
    Format(' WHERE s.kind = ''form'' AND UPPER(s.name) = UPPER(''%s'')', [TChartsIndex.SqlText(Segs[0])]));
  try
    for var R in Forms do
      Fids:= Fids + [IntToStr(R.I('fid'))];
  finally
    Forms.Free;
  end;
  if Length(Fids) = 0 then
    raise EChartsQuestion.CreateFmt('lands-where: %s resolves to no property or field in this index and %s is no form -- %s.',
      [FSel, Segs[0], NOT_ORM]);
  var Last:= Segs[High(Segs)];
  var Found: TArray<TCtlRow>:= [];
  var Cands:= FIndex.Query(
    'SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.parent_id AS pid,' + sLineBreak +
    '       c.start_line AS line, f.path AS path, p.name AS pname' + sLineBreak +
    '  FROM symbols c JOIN files f ON f.id = c.file_id LEFT JOIN symbols p ON p.id = c.parent_id' + sLineBreak +
    Format(' WHERE c.kind = ''component'' AND c.file_id IN (%s)', [string.Join(',', Fids)]) + sLineBreak +
    Format('   AND UPPER(c.name) = UPPER(''%s'')', [TChartsIndex.SqlText(Last)]));
  try
    for var R in Cands do
    begin
      if (Length(Segs) > FORM_CONTROL_SEGMENTS) and not string.Equals(R.S('q').ToUpperInvariant, FSel.ToUpperInvariant) then
        Continue;
      var C:= Default(TCtlRow);
      C.Id:= R.I('id');
      C.Name:= R.S('name');
      C.QName:= R.S('q');
      C.Sig:= R.S('sig');
      C.Pid:= R.I('pid');
      C.Line:= R.I('line');
      C.Path:= R.S('path');
      C.PName:= R.S('pname');
      Found:= Found + [C];
    end;
  finally
    Cands.Free;
  end;
  if Length(Found) = 0 then
    raise EChartsQuestion.CreateFmt('lands-where: no component named %s on %s -- %s.', [Last, Segs[0], NOT_ORM]);
  if Length(Found) > 1 then
  begin
    var Names: TArray<string>:= [];
    for var C in Found do
      Names:= Names + [C.QName];
    raise EChartsQuestion.CreateFmt('lands-where: %s names %d components (%s) -- pass the full qualified name',
      [FSel, Length(Found), string.Join(', ', Names)]);
  end;
  FCtl:= Found[0];
  var HasFieldName:= False;
  var HasOther:= False;
  var Fb:= FIndex.Query(
    'SELECT owner_name AS prop, text AS col, start_line AS line FROM string_literals' + sLineBreak +  // dl:ok sql-injection-concat@6184 -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
    Format(' WHERE kind = ''dfm-prop'' AND symbol_id = %d', [FCtl.Id]) + sLineBreak +
    '   AND owner_name IN (''DataBinding.FieldName'',''DataBinding.DataField'',''DataField'',''FieldName'')' + sLineBreak +
    ' ORDER BY start_line');
  try
    for var R in Fb do
      if SameText(R.S('prop'), FIELD_NAME_PROP) then
        HasFieldName:= True
      else
        HasOther:= True;
  finally
    Fb.Free;
  end;
  if HasFieldName and not HasOther then
    raise EChartsQuestion.CreateFmt('lands-where: %s is a persistent FIELD (%s) of the dataset %s, not a ' +
      'data-aware control -- its dataset is not a datasource chain. Ask lands-where of the ORM property, or of a control bound to that column.',
      [FCtl.QName, FCtl.Sig, FCtl.PName]);
  if not HasOther then
    raise EChartsQuestion.CreateFmt('lands-where: %s (%s) binds no field in the DFM -- %s.', [FCtl.QName, FCtl.Sig, NOT_ORM]);
  FKind:= KIND_DFM;
end;

{ ---- 2a. P35: Tmc properties / on a table-named class / extracted as a column of that table ---- }
procedure TLandsWhereChart.MeasureConvention;
begin
  var TSet:= FCatalog.TableSet;
  var NonCol: TArray<string>:= [];
  var Quoted: TArray<string>:= [];
  var Stale: TArray<string>:= [];
  var Rows:= FIndex.AllRows(
    'SELECT p.id AS id, p.name AS pn, c.name AS cn' + sLineBreak +
    '  FROM symbols p JOIN symbols c ON c.id = p.parent_id' + sLineBreak +
    ' WHERE p.kind = ''property'' AND c.kind = ''class'' AND c.name GLOB ''Tmc*''', 'p.id');
  try
    FConv.Props:= Rows.Count;
    for var R in Rows do
    begin
      var Tn:= R.S('cn').Substring(CLASS_PREFIX_LEN);
      var T:= TSet.Table(Tn);
      if T = nil then
        Continue;
      Inc(FConv.OnTable);
      var Pn:= R.S('pn');
      if T.IsColumn(Pn) then
      begin
        Inc(FConv.Column);
        Continue;
      end;
      var Name:= Tn + '.' + Pn;
      NonCol:= NonCol + [Name];
      { each non-extracted one through the SHARED state: quoted, or not scanned because its
        script is stale -- a stale scan is COUNTED and named, never "not a column" }
      var St:= SqlColumnState(FCatalog, TSet, Tn, Pn, TServerSqlHit.None, '').State;
      if SameText(St, S_QUOTED) then
        Quoted:= Quoted + [Name]
      else if SameText(St, S_STALE) then
        Stale:= Stale + [Name];
    end;
  finally
    Rows.Free;
  end;
  FConv.NonColumn:= string.Join(',', SortedNames(NonCol));
  FConv.Quoted:= string.Join(',', SortedNames(Quoted));
  FConv.Stale:= string.Join(',', SortedNames(Stale));
  FConv.NQuoted:= Length(Quoted);
  FConvGrade:= Format('inferred -- naming convention, %s of %s properties on table-named classes are extracted as a column of that table',
    [FormatN(FConv.Column), FormatN(FConv.OnTable)]);
  if FConv.NQuoted > 0 then
    FConvGrade:= FConvGrade + Format(' (+%d a QUOTED column the index does not extract)', [FConv.NQuoted]);
end;

{ ---- 2b. Get-ParamByNameStats: P36/P37 on the SERVER ---- }
procedure TLandsWhereChart.MeasureParamByName;
begin
  var TSet:= FCatalog.TableSet;
  var Rows:= FSrvIndex.AllRows(
    'SELECT sl.id AS id, sl.text AS txt, cls.name AS cls' + sLineBreak +
    '  FROM string_literals sl' + sLineBreak +
    '  JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.name_text = ''ParamByName''' + sLineBreak +
    '             AND r.kind = ''call'' AND sl.start_col = r.end_col + 1' + sLineBreak +
    '  LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id' + sLineBreak +
    '  LEFT JOIN symbols cls ON cls.id = e.parent_id', 'sl.id');
  try
    FPbn.All:= Rows.Count;
    for var R in Rows do
    begin
      var Cls:= R.S('cls');
      if not TRegEx.IsMatch(Cls, DATASERVICE_RX, [roIgnoreCase]) then
        Continue;
      Inc(FPbn.InDataService);
      var T:= TSet.Table(TRegEx.Match(Cls, DATASERVICE_RX).Groups[1].Value);
      if (T <> nil) and T.IsColumn(R.S('txt')) then
        Inc(FPbn.Column);
    end;
  finally
    Rows.Free;
  end;
end;

{ ---- 3. resolve an ORM selection to T and PROP ---- }
procedure TLandsWhereChart.ResolveOrm;
begin
  FTName:= TRegEx.Match(FSelSym.PName, ORM_CLASS_RX).Groups[ORM_TABLE_GROUP].Value;
  if SameText(FSelSym.Kind, 'field') then
  begin
    { a backing field `fREASON` -> its property REASON, by the f<PROP> naming }
    var Pn:= TRegEx.Replace(FSelSym.Name, '^[fF]', '', [roIgnoreCase]);
    FOrmSym:= FindOrmProperty(FSelSym.PName, Pn);
    if not FOrmSym.Present then
      raise EChartsQuestion.CreateFmt('lands-where: %s is a field of %s with no property named %s -- select the property itself',
        [FSel, FSelSym.PName, Pn]);
    FSelRows:= FSelRows + [NewRow(FSelSym.Name + ' : field', FSelSym.Path, FSelSym.Line,
      FSelSym.QName + ' -- ' + At(FSelSym.Path, FSelSym.Line), Format('[by name] backing field of %s (f<PROP>)', [Pn]))];
  end
  else
    FOrmSym:= FSelSym;
  FProp:= FOrmSym.Name;
end;

{ ---- 3. resolve a DFM selection through the feeds-from chain ---- }
procedure TLandsWhereChart.ResolveDfm;
begin
  var Mine: TArray<TFieldBinding>:= [];
  for var B in FIx.Bindings do
    if B.ControlId = FCtl.Id then
      Mine:= Mine + [B];
  TPsSort<TFieldBinding>.Sort(Mine,
    function(const pA, pB: TFieldBinding): Integer
    begin
      Result:= pA.Line - pB.Line;
    end);
  if Length(Mine) = 0 then
    raise EChartsQuestion.CreateFmt('lands-where: %s is not in the field-binding population (no DataBinding.FieldName / DataField) -- %s.',
      [FCtl.QName, NOT_ORM]);
  FBindRow:= Mine[0];
  FChainOutcome:= FBindRow.Outcome;
  if FBindRow.Ds <> '' then
  begin
    var Key:= ChainKey(FBindRow.Dfm, FBindRow.Ds);
    for var K:= 0 to High(FIx.ChainKeys) do
      if SameText(FIx.ChainKeys[K], Key) then
      begin
        FHasChain:= True;
        FChain:= FIx.Chains[K];
        Break;
      end;
  end;
  FSelRows:= FSelRows + [NewRow(FCtl.Name + ' : ' + FCtl.Sig, FBindRow.Dfm, FBindRow.Line,
    Format('%s.%s = ''%s'' -- %s', [FCtl.QName, FBindRow.Prop, FBindRow.Column, At(FBindRow.Dfm, FBindRow.Line)]),
    FBindRow.Prop + ' = ' + FBindRow.Column)];
  if FHasChain then
    for var H in FChain.Hops do
    begin
      var Lbl:= Format('[%s] %s: %s', [H.Grade, H.Hop, H.Caption]);
      if (H.Line > 0) and (H.Path <> '') then
        FSelRows:= FSelRows + [NewRow(Lbl, H.Path, H.Line, H.Caption + ' -- ' + At(H.Path, H.Line), H.Reason)]
      else
        FSelRows:= FSelRows + [NoteRow(Lbl + ' -- ' + H.Reason)];
    end;
  { Task 2 (2026-10-05): past a DANGLING designer datasource the owner's code re-point is
    followed -- the SAME Resolve-RePointTable result feeds-from draws }
  if FBindRow.RePointKey <> '' then
    for var K:= 0 to High(FIx.RePointKeys) do
      if SameText(FIx.RePointKeys[K], FBindRow.RePointKey) then
      begin
        FHasRpr:= True;
        FRpr:= FIx.RePoints[K];
        Break;
      end;
  if FHasRpr then
  begin
    for var H in FRpr.Hops do
    begin
      var Lbl:= Format('[%s] %s: %s', [H.Grade, H.Hop, H.Caption]);
      var Notes: TArray<string>:= [];
      if H.Routine <> '' then
        Notes:= Notes + ['in ' + H.Routine];
      if H.Reason <> '' then
        Notes:= Notes + [H.Reason];
      FSelRows:= FSelRows + [NewRow(Lbl, H.Path, H.Line, H.Caption + ' -- ' + At(H.Path, H.Line), string.Join('; ', Notes))];
    end;
    var D:= FRpr.DataSet;
    if D.Present then
      FSelRows:= FSelRows + [NewRow(Format('[certain] dataset field: %s : %s', [D.Name, D.TypeName]), D.Path, D.Line,
        Format('%s : %s -- %s', [D.Name, D.TypeName, At(D.Path, D.Line)]), 'the dataset the re-pointed datasource is given')];
    if FRpr.Table <> '' then
      FSelRows:= FSelRows + [NewRow('[inferred] table: ' + FRpr.Table, D.Path, FRpr.TableLine,
        Format('''%s'' literal -- %s', [FRpr.Table, At(D.Path, FRpr.TableLine)]),
        Format('the table literal beside %s on %d line(s)', [D.Name, FRpr.TableLines]))];
  end;
  var ChainStop:= if FHasChain then FChain.StopReason else '';
  var ChainGrade:= if FHasChain then FChain.Grade else '';
  if SameText(FChainOutcome, O_COLUMN) or SameText(FChainOutcome, 'not-column') then
  begin
    FTName:= FBindRow.Table;
    FProp:= FBindRow.Column;
  end
  else if SameText(FChainOutcome, 'no-ds') then
    FStop:= Format('no DataSource on %s or its two enclosing components in the DFM -- the chain cannot start', [FCtl.Name])
  else if SameText(FChainOutcome, 'dangling') then
    FStop:= Format('the designer datasource %s is dangling (%s) -- no table', [FBindRow.Ds, ChainStop]) +
      (if FHasRpr then '; the code re-point: ' + FRpr.Stop else '')
  else if SameText(FChainOutcome, S_STALE) then
  begin
    { stale with a table: the chain resolved, but the table's script is stale, so the column's
      state is unknown -- step 4 says so ([stale source]) }
    if FBindRow.Table <> '' then
    begin
      FTName:= FBindRow.Table;
      FProp:= FBindRow.Column;
    end
    else
      FStop:= '[stale source] ' + (if FHasRpr and SameText(FRpr.Status, S_STALE) then FRpr.Stop else ChainStop);
  end
  else
    FStop:= Format('the chain stops before a table (%s): %s', [ChainGrade, ChainStop]);
  if FTName <> '' then
    FOrmSym:= FindOrmProperty('Tmc' + FTName, FProp);
end;

{ ---- 4. the table and the column ---- }
procedure TLandsWhereChart.ReadColumn;
begin
  if FTName <> '' then
  begin
    { (an ORM selection was checked in step 1; a DFM chain only resolves to a table of the set) }
    FTbl:= FCatalog.TableSet.Table(FTName);
    if FTbl <> nil then
      FTName:= FTbl.Name;
    { the SHARED state; `no` / `stale` are looked at again after the server step }
    FCs:= SqlColumnState(FCatalog, FCatalog.TableSet, FTName, FProp, TServerSqlHit.None, '');
    FHasCs:= True;
    FColState:= FCs.State;
  end;
  FHasColumn:= FHasCs and FCs.IsColumn;
  FCol:= FProp.ToUpperInvariant;
end;

{ ---- 5. the server write / read path ---- }
procedure TLandsWhereChart.ReadServer;
var
  ClsId, ClsFid, ImpId: Integer;
begin
  if FTName = '' then
    Exit;
  ClsId:= 0;
  ClsFid:= 0;
  ImpId:= 0;
  var Cls:= FSrvIndex.Query(
    'SELECT c.id AS id, c.name AS name, f.path AS path, c.file_id AS fid FROM symbols c JOIN files f ON f.id = c.file_id' + sLineBreak +  // dl:ok sql-injection-concat@1ef2 -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
    Format(' WHERE c.kind = ''class'' AND UPPER(c.name) = UPPER(''TDataService_%s_SERVER'')', [TChartsIndex.SqlText(FTName)]));
  try
    if Cls.Count > 0 then
    begin
      ClsId:= Cls[0].I('id');
      ClsFid:= Cls[0].I('fid');
      FSrvClass:= Cls[0].S('name');
      FSrvFile:= Cls[0].S('path');
    end;
  finally
    Cls.Free;
  end;
  var Imp:= FSrvIndex.Query(
    'SELECT s.id AS id, s.qualified_name AS q FROM symbols s JOIN symbols p ON p.id = s.parent_id' + sLineBreak +  // dl:ok sql-injection-concat@5dc0 -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
    Format(' WHERE s.kind = ''property'' AND p.kind = ''interface'' AND UPPER(p.name) = UPPER(''Imc%s'')', [TChartsIndex.SqlText(FTName)]) + sLineBreak +
    Format('   AND UPPER(s.name) = UPPER(''%s'')', [TChartsIndex.SqlText(FProp)]));
  try
    if Imp.Count > 0 then
    begin
      { the PS also keeps its qualified name, read only by a Write-Host line }
      ImpId:= Imp[0].I('id');
    end;
  finally
    Imp.Free;
  end;
  var Rts: TArray<TSrvRoutine>:= [];
  var Acc: TArray<TSrvAccess>:= [];
  var Pbn: TArray<TSrvPbn>:= [];
  var Lits: TArray<TSrvLiteral>:= [];
  if FSrvClass <> '' then
  begin
    var RtRows:= FSrvIndex.AllRows(
      'SELECT s.id AS id, s.name AS name, s.qualified_name AS q, s.impl_start_line AS a, s.impl_end_line AS b' + sLineBreak +
      Format('  FROM symbols s WHERE s.parent_id = %d AND s.impl_start_line > 0 AND s.kind IN (%s)',
        [ClsId, TChartsIndex.SqlInList(['method', 'procedure', 'function', 'constructor', 'destructor'])]), 's.id');
    try
      for var R in RtRows do
      begin
        var Rt:= Default(TSrvRoutine);
        Rt.Id:= R.I('id');
        Rt.Name:= R.S('name');
        Rt.QName:= R.S('q');
        Rt.A:= R.I('a');
        Rt.B:= R.I('b');
        Rts:= Rts + [Rt];
      end;
    finally
      RtRows.Free;
    end;
    var Ids: TArray<string>:= [];
    for var Rt in Rts do
      Ids:= Ids + [IntToStr(Rt.Id)];
    var IdList:= string.Join(',', Ids);
    if Length(Ids) > 0 then
    begin
      if ImpId <> 0 then
      begin
        var AccRows:= FSrvIndex.Query(
          'SELECT r.start_line AS line, r.enclosing_symbol_id AS eid, ma.mode AS mode, r.receiver_text AS rt' + sLineBreak +
          '  FROM refs r JOIN member_accesses ma ON ma.ref_id = r.id' + sLineBreak +
          Format(' WHERE ma.member_symbol_id = %d AND r.enclosing_symbol_id IN (%s)', [ImpId, IdList]) + sLineBreak +
          ' ORDER BY r.start_line');
        try
          for var R in AccRows do
          begin
            var A:= Default(TSrvAccess);
            A.Line:= R.I('line');
            A.Eid:= R.I('eid');
            A.Mode:= R.S('mode');
            A.Rt:= R.S('rt');
            Acc:= Acc + [A];
          end;
        finally
          AccRows.Free;
        end;
        FSrvElsewhere:= CountOf(FSrvIndex, 'SELECT COUNT(*) AS n FROM refs r JOIN member_accesses ma ON ma.ref_id = r.id' + sLineBreak +  // dl:ok sql-injection-concat@8c59 -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
          Format(' WHERE ma.member_symbol_id = %d AND (r.enclosing_symbol_id IS NULL OR r.enclosing_symbol_id NOT IN (%s))', [ImpId, IdList]));
      end;
      if FProp <> '' then
      begin
        var PbnRows:= FSrvIndex.AllRows(
          'SELECT sl.start_line AS line, r.enclosing_symbol_id AS eid, sl.text AS txt' + sLineBreak +
          '  FROM string_literals sl JOIN refs r ON r.file_id = sl.file_id AND r.start_line = sl.start_line AND r.name_text = ''ParamByName''' + sLineBreak +
          '                                     AND r.kind = ''call'' AND sl.start_col = r.end_col + 1' + sLineBreak +
          Format(' WHERE r.enclosing_symbol_id IN (%s) AND UPPER(sl.text) = UPPER(''%s'')', [IdList, TChartsIndex.SqlText(FProp)]),
          'sl.start_line, sl.id, r.id');
        try
          for var R in PbnRows do
          begin
            var P:= Default(TSrvPbn);
            P.Line:= R.I('line');
            P.Eid:= R.I('eid');
            P.Txt:= R.S('txt');
            Pbn:= Pbn + [P];
          end;
        finally
          PbnRows.Free;
        end;
        var LitRows:= FSrvIndex.AllRows(
          'SELECT sl.id AS id, sl.start_line AS line, sl.text AS txt FROM string_literals sl' + sLineBreak +  // dl:ok sql-injection-concat@41ff -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
          Format(' WHERE sl.file_id = %d AND sl.kind IN (''literal'',''format'',''const'')', [ClsFid]), 'sl.start_line, sl.id');
        try
          for var R in LitRows do
          begin
            var L:= Default(TSrvLiteral);
            L.Line:= R.I('line');
            L.Txt:= R.S('txt');
            Lits:= Lits + [L];
          end;
        finally
          LitRows.Free;
        end;
      end;
    end;
  end;

  TPsSort<TSrvRoutine>.Sort(Rts,
    function(const pA, pB: TSrvRoutine): Integer
    begin
      Result:= pA.A - pB.A;
    end);
  var WordPattern:= if FCol <> '' then WordRx(FCol) else '';
  var TSet:= FCatalog.TableSet;
  for var Rt in Rts do
  begin
    var Ev: TArray<TEvidence>:= [];
    for var A in Acc do
      if A.Eid = Rt.Id then
      begin
        var E:= Default(TEvidence);
        E.Line:= A.Line;
        E.Grade:= G_CERTAIN;
        E.Text:= (if A.Rt <> '' then A.Rt + '.' else '') + FProp + ' ' + A.Mode;
        Ev:= Ev + [E];
      end;
    for var P in Pbn do
      if P.Eid = Rt.Id then
      begin
        var E:= Default(TEvidence);
        E.Line:= P.Line;
        E.Grade:= G_INFERRED;
        E.Text:= Format('ParamByName(''%s'')', [P.Txt]);
        Ev:= Ev + [E];
      end;
    if (Rt.A <> 0) and (Rt.B <> 0) then
    begin
      var Span: TArray<TSrvLiteral>:= [];
      for var L in Lits do
        if (L.Line >= Rt.A) and (L.Line <= Rt.B) then
          Span:= Span + [L];
      var NamesT:= False;
      for var L in Span do
      begin
        for var H in SqlVerbTables(L.Txt, TSet) do
          if SameText(H.Kind, 'table') and SameText(H.Name, FTName) then
          begin
            NamesT:= True;
            Break;
          end;
        if NamesT then
          Break;
      end;
      if NamesT then
        for var L in Span do
          if TRegEx.IsMatch(L.Txt, WordPattern) then
          begin
            var E:= Default(TEvidence);
            E.Line:= L.Line;
            E.Grade:= G_INFERRED;
            E.Text:= 'SQL literal names ' + FCol;
            Ev:= Ev + [E];
            if not FSrvSqlHit then
            begin
              FSrvSqlHit:= True;
              FSrvSqlLine:= L.Line;
              FSrvSqlRtn:= Rt.QName;
            end;
            Break;
          end;
    end;
    if Length(Ev) = 0 then
      Continue;
    var Grade:= G_INFERRED;
    for var E in Ev do
      if SameText(E.Grade, G_CERTAIN) then
        Grade:= G_CERTAIN;
    TPsSort<TEvidence>.Sort(Ev,
      function(const pA, pB: TEvidence): Integer
      begin
        Result:= pA.Line - pB.Line;
      end);
    var Parts: TArray<string>:= [];
    for var E in Ev do
      Parts:= Parts + [Format('%s :%d', [E.Text, E.Line])];
    var EvText:= string.Join('; ', Parts);
    var Row:= NewRow(Rt.Name, FSrvFile, Ev[0].Line, Rt.QName + ' -- ' + EvText, Format('[%s] %s', [Grade, EvText]));
    if TRegEx.IsMatch(Rt.Name, 'save', [roIgnoreCase]) then
      FSrvWrite:= FSrvWrite + [Row]
    else if TRegEx.IsMatch(Rt.Name, 'load', [roIgnoreCase]) then
      FSrvRead:= FSrvRead + [Row]
    else
      FSrvOther:= FSrvOther + [Row];
  end;
end;

{ NOT IN THE SCRIPTS IS NOT "NOT A COLUMN" (FINDING 2026-09-23): "computed or UI-only" is said
  ONLY when the server's own SQL for T does not name the column either }
procedure TLandsWhereChart.RecheckColumn;
begin
  if not (SameText(FColState, 'no') or SameText(FColState, S_STALE)) then
    Exit;
  var Hit:= TServerSqlHit.None;
  if FSrvSqlHit then
    Hit:= TServerSqlHit.Make(FSrvFile, FSrvSqlLine, ShortName(FSrvSqlRtn, UnitNameOf(FSrvFile)));
  var Searched:= if FSrvClass <> '' then 'the server''s ' + FSrvClass else '';
  FCs:= SqlColumnState(FCatalog, FCatalog.TableSet, FTName, FProp, Hit, Searched);
  FColState:= FCs.State;
  FHasColumn:= FCs.IsColumn;
end;

{ ---- 6. the database side: triggers and procedures ---- }
procedure TLandsWhereChart.ReadDatabase;
begin
  { a column whose state is unknown ([stale source]) is still looked up by name on the
    database side: a trigger naming NEW.<COL> is evidence either way }
  if (FTName = '') or not (FHasColumn or SameText(FColState, S_STALE)) then
    Exit;
  var ForT: TArray<TSqlTrigger>:= [];
  for var T in FCatalog.TriggerSet do
    if SameText(T.Table, FTName) then
      ForT:= ForT + [T];
  TPsSort<TSqlTrigger>.Sort(ForT,
    function(const pA, pB: TSqlTrigger): Integer
    begin
      Result:= CompareGroupKeys(pA.Name, pB.Name);
    end);
  for var T in ForT do
  begin
    if T.Body.Stale then
      Inc(FTrigStale);
    var Hits:= False;
    for var C in T.Columns do
      if SameText(C, FCol) then
        Hits:= True;
    if not Hits then
      Continue;
    var Line:= T.Body.StartLine;
    FTrigNames:= FTrigNames + [Format('%s@%s', [T.Name, At(T.Path, Line)])];
    FTrigRows:= FTrigRows + [NewRow(T.Name, T.Path, Line,
      Format('%s FOR %s: NEW./OLD.%s in its body -- %s', [T.Name, FTName, FCol, At(T.Path, Line)]), 'NEW/OLD.' + FCol)];
  end;
  var Procs:= FCatalog.ProcedureSet;
  var Groups:= TDictionary<string, TArray<TSqlProcedure>>.Create;
  try
    for var P in Procs do
    begin
      if not P.Body.Found then
        Inc(FProcUnscanned);
      var Key:= P.Name.ToUpperInvariant;
      var G: TArray<TSqlProcedure>;
      if not Groups.TryGetValue(Key, G) then
        G:= [];
      Groups.AddOrSetValue(Key, G + [P]);
    end;
    var WordPattern:= WordRx(FCol);
    for var Key in SortedNames(Groups.Keys.ToArray) do
    begin
      var Cands: TArray<TSqlProcedure>:= [];
      for var P in Groups[Key] do
      begin
        if not P.Body.Found or not TRegEx.IsMatch(P.Body.Text, WordPattern) then
          Continue;
        for var T in P.Tables do
          if SameText(T, FTName) then
          begin
            Cands:= Cands + [P];
            Break;
          end;
      end;
      if Length(Cands) = 0 then
        Continue;
      TPsSort<TSqlProcedure>.Sort(Cands,
        function(const pA, pB: TSqlProcedure): Integer
        begin
          Result:= pA.Body.StartLine - pB.Body.StartLine;
        end);
      var D:= Cands[0];
      FProcNames:= FProcNames + [D.Name];
      FProcRows:= FProcRows + [NewRow(D.Name, D.Path, D.Body.StartLine,
        Format('%s: body names %s and %s -- %s', [D.Name, FTName, FCol, At(D.Path, D.Body.StartLine)]), '[inferred] body scan')];
    end;
  finally
    Groups.Free;
  end;
end;

{ ---- 7. the client side: field-bound controls, the REVERSE of feeds-from ---- }
procedure TLandsWhereChart.ReadClient;
begin
  if FCol <> '' then
    for var B in FIx.Bindings do
    begin
      if not B.Column.ToUpperInvariant.Equals(FCol.ToUpperInvariant) then
        Continue;
      if (B.Table <> '') and B.Table.ToUpperInvariant.Equals(FTName.ToUpperInvariant) then
        FBindSame:= FBindSame + [B]
      else
        FBindOther:= FBindOther + [B];
    end;
  FBindSorted:= Copy(FBindSame);
  SortBindings(FBindSorted);
  for var B in FBindSorted do
  begin
    var Dangling:= if SameText(B.RePoint, 'table') then '; dangling in the DFM, re-point followed' else '';
    var Extracted:= '';
    if SameText(B.Outcome, 'not-column') then
      Extracted:= '; not extracted as a column'
    else if SameText(B.Outcome, S_STALE) then
      Extracted:= '; [stale source]';
    var Note:= B.Ds + Dangling + Extracted;
    FBindRowsOut:= FBindRowsOut + [NewRow(UnitNameOf(B.Dfm) + '.' + B.Control, B.Dfm, B.Line,
      Format('%s.%s = ''%s'' via %s -> %s -- %s', [B.Control, B.Prop, B.Column, B.Ds, FTName, At(B.Dfm, B.Line)]), Note)];
  end;
end;

{ -- top: the selection, and the ORM property -- }
procedure TLandsWhereChart.DrawSelection;
begin
  if FKind = KIND_DFM then
    FNTop:= AddBox('control ' + FCtl.Name, Format('%d chain hop(s)', [Length(FSelRows) - 1]), FSelRows, K_CTL, False);
  if not FOrmSym.Present then
    Exit;
  var PropRows: TArray<TDotRow>:= [];
  if FKind = KIND_ORM then
    PropRows:= Copy(FSelRows);
  var Imps: string;
  if SameText(FOrmSym.PKind, 'interface') then
    Imps:= 'the interface the server reads'
  else if TRegEx.IsMatch(FOrmSym.PHer, '(^|[\s,<])Imc' + TRegEx.Escape(FTName) + '(\s*,|\s*$|>)', [roIgnoreCase]) then
    Imps:= 'implements Imc' + FTName + ' (heritage)'
  else
    Imps:= 'Imc' + FTName + ' not in its heritage';
  PropRows:= PropRows + [NewRow(FOrmSym.Name + ' : property of ' + FOrmSym.PName, FOrmSym.Path, FOrmSym.Line,
    FOrmSym.QName + ' -- ' + At(FOrmSym.Path, FOrmSym.Line), Imps)];
  var PropSub:= if FKind = KIND_DFM then 'inferred -- naming convention Tmc<T>.<COL>' else G_CERTAIN;
  FNProp:= AddBox('ORM property', PropSub, PropRows, K_PROP, FKind = KIND_DFM);
  if FNTop <> '' then
    AddEdge(FNTop, FNProp, '[inferred] Tmc<T>.<COL>', True);
end;

{ -- the table / column -- }
procedure TLandsWhereChart.DrawColumn;
begin
  if FTName = '' then
  begin
    if FStop <> '' then
      FNCol:= AddBox('chain stops here', '', [NoteRow(FStop)], K_STOP, False);
    Exit;
  end;
  if FHasColumn then
  begin
    var CLabel:= if SameText(FColState, S_QUOTED) then Format('%s."%s"', [FTName, FCol]) else FTName + '.' + FCol;
    var CTip: string;
    if SameText(FColState, S_QUOTED) then
      CTip:= FCs.Text
    else if SameText(FColState, 'server-sql') then
      CTip:= Format('%s names %s in its SQL for %s', [FSrvSqlRtn, FCol, FTName])
    else
      CTip:= FTName + '.' + FCol;
    FColRow:= NewRow(CLabel, FCs.Path, FCs.Line, CTip + ' -- ' + At(FCs.Path, FCs.Line), FCs.Caption);
    FHasColRow:= True;
  end;
  var From:= if FKind = KIND_ORM then Format('from %s by the naming convention', [FOrmSym.PName]) else 'where the chain resolved';
  { FTbl is not nil: ReadColumn's SqlColumnState raised for a table outside the set }
  var CRows: TArray<TDotRow>:= [NewRow('table ' + FTName, FTbl.Path, FTbl.Line, FTName + ' -- ' + At(FTbl.Path, FTbl.Line),
    Format('%s; newest of %d declaration(s)', [From, Length(FTbl.Declarations)]))];
  if FHasColRow then
    CRows:= CRows + [FColRow]
  { R11: a stale scan is NOT an absence -- never "computed or UI-only" }
  else if SameText(FColState, S_STALE) then
    CRows:= CRows + [NoteRow(FProp + ': ' + FCs.Caption)]
  { R24 item 8: "computed or UI-only" only when a DataService's SQL was searched }
  else
    CRows:= CRows + [NoteRow(FormatNotAColumnNote(FProp, FTName, FCs.Caption, FSrvClass))];
  var Title: string;
  if FHasColumn then
    Title:= FTName + '.' + FCol
  else if SameText(FColState, S_STALE) then
    Title:= FTName + '.' + FCol + ' [stale source]'
  else if FSrvClass <> '' then
    Title:= Format('%s (no column %s)', [FTName, FProp])
  else
    Title:= Format('%s (%s not extracted)', [FTName, FProp]);
  FNCol:= AddBox(Title, FConvGrade, CRows, K_DB, True);
end;

{ -- server clusters -- }
procedure TLandsWhereChart.DrawServer;
var
  Nodes, Colors: array[0..2] of string;
begin
  var Sub:= if FSrvClass <> '' then FSrvClass + ' [by name]' else '';
  if Length(FSrvWrite) > 0 then
    Nodes[0]:= AddBox('server write path', Sub, FSrvWrite, K_WRITE, False);
  if Length(FSrvRead) > 0 then
    Nodes[1]:= AddBox('server read path', Sub, FSrvRead, K_READ, False);
  if Length(FSrvOther) > 0 then
    Nodes[2]:= AddBox('other DataService routines', Sub, FSrvOther, K_STOP, False);
  Colors[0]:= WRITE_BORDER;
  Colors[1]:= READ_BORDER;
  Colors[2]:= STOP_BORDER;
  var Src:= if FNProp <> '' then FNProp else FNTop;
  for var K:= 0 to 2 do
  begin
    if Nodes[K] = '' then
      Continue;
    var IsRead:= K = 1;
    if Src <> '' then
      AddEdge(Src, Nodes[K], 'Obj.' + FProp, False, IsRead, Colors[K]);
    if FNCol <> '' then
      AddEdge(Nodes[K], FNCol, if FHasColumn then '[inferred] SQL names it' else '', True, IsRead, Colors[K]);
  end;
  if (Src <> '') and (FNCol <> '') and (Nodes[0] = '') and (Nodes[1] = '') and (Nodes[2] = '') then
    AddEdge(Src, FNCol, if (FKind = KIND_DFM) and (FNProp = '') then '[inferred] chain' else '[inferred] naming convention', True);
  if (FNTop <> '') and (FNProp <> '') and (FNCol <> '') then
    FSb.AppendLine(Format('  %s -> %s [style=invis];', [FNTop, FNCol]));
end;

{ -- database side -- }
procedure TLandsWhereChart.DrawDatabase;
begin
  if Length(FTrigRows) > 0 then
  begin
    var NT:= AddBox(Format('triggers FOR %s using %s', [FTName, FCol]), Format('%d row(s)', [Length(FTrigRows)]), FTrigRows, K_DB, False);
    AddEdge(FNCol, NT, 'NEW./OLD.', False, False, DB_BORDER);
  end;
  if Length(FProcRows) > 0 then
  begin
    var NP:= AddBox(Format('procedures naming %s and %s', [FTName, FCol]), Format('%d row(s) [inferred]', [Length(FProcRows)]), FProcRows, K_DB, True);
    AddEdge(FNCol, NP, 'body scan', True, False, DB_BORDER);
  end;
end;

{ -- client side cluster -- }
procedure TLandsWhereChart.DrawClient;
var
  SumT, SumO: Integer;
begin
  if (FCol = '') or (FTName = '') then
    Exit;
  var Cx:= Copy(FBindRowsOut);
  var Extra: TArray<string>:= [];
  var ByT:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  var ByO:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    for var B in FBindOther do
      if B.Table <> '' then
        Bump(ByT, B.Table)
      else
        Bump(ByO, B.Outcome);
    if ByT.Count > 0 then
    begin
      var L:= CountList(ByT, SumT);
      Extra:= Extra + [Format('%d more bound to %s on a chain resolving to another table (%s)', [SumT, FCol, L])];
    end;
    if ByO.Count > 0 then
    begin
      var L:= CountList(ByO, SumO);
      Extra:= Extra + [Format('%d more whose chain does not reach a table (%s)', [SumO, L])];
    end;
  finally
    ByO.Free;
    ByT.Free;
  end;
  if (Length(Cx) = 0) and (Length(Extra) = 0) then
    Exit;
  if Length(Cx) = 0 then
    Cx:= Cx + [NoteRow(Format('no field-bound control in this index resolves to %s.%s', [FTName, FCol]))];
  var NB:= AddBox('client: controls bound to it', Format('%d resolve to %s [inferred]', [Length(FBindSame), FTName]), Cx, K_CTL, True);
  if Length(Extra) > 0 then
  begin
    Inc(FNi);
    var Xn:= 'n' + IntToStr(FNi);
    var Rows: TArray<TDotRow>:= [];
    for var E in Extra do
      Rows:= Rows + [NoteRow(E)];
    var Style:= TClusterStyle.Make(STOP_BORDER, STOP_FILL, STOP_HDR);
    Style.RowInk:= ROW_INK;
    Style.LineInk:= LINE_INK;
    Style.FontSans:= FONT_SANS;
    AddRowCluster(FSb, Format('cluster_ctlx_%d', [FNi]), Xn, 'other bindings of this name', 'counted, not drawn', Rows, Style);
    FSb.AppendLine(Format('  %s -> %s [style=invis];', [NB, Xn]));
  end;
  if FNCol <> '' then
    AddEdge(NB, FNCol, '[inferred] chain resolves here', True, False, CTL_BORDER);
end;

{ -- the focus box: what was asked, and what the chart can and cannot see -- }
procedure TLandsWhereChart.DrawFocus;
begin
  Inc(FNi);
  var FNid:= 'n' + IntToStr(FNi);
  var FocusHtml:= TStringBuilder.Create;
  try
    FocusHtml.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    FocusHtml.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> lands-where &#183; %s </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS, XmlText(FSel)]));
    { R24 item 7: a QUOTED column the index does not extract is still a column }
    AddDisclosureRow(FocusHtml, Format('table by naming convention (Tmc<T>): %s of %s Tmc properties in this index are a column of their class''s table',
      [FormatN(FConv.Column + FConv.NQuoted), FormatN(FConv.Props)]), LINE_INK);
    var ConvText:= Format('(%s sit on a table-named class; %d are not extracted as a column by the SQL index',
      [FormatN(FConv.OnTable), FConv.OnTable - FConv.Column]);
    if FConv.Quoted <> '' then
      ConvText:= ConvText + Format('; of those, %s is a QUOTED column the index does not extract', [FConv.Quoted]);
    if FConv.Stale <> '' then
      ConvText:= ConvText + '; not scanned for a quoted identifier [stale source]: ' + FConv.Stale;
    AddDisclosureRow(FocusHtml, ConvText + ')', LINE_INK);
    if FKind = KIND_DFM then
    begin
      var NColumn:= 0;
      for var B in FIx.Bindings do
        if SameText(B.Outcome, O_COLUMN) then
          Inc(NColumn);
      AddDisclosureRow(FocusHtml, Format('DFM-field selection: the feeds-from chain (%d of %d field-bound controls reach a column of one table; ' +
        'outcome here: %s)', [NColumn, Length(FIx.Bindings), FChainOutcome]), LINE_INK);
    end;
    { R24 item 9: an unknown table is said, not spelled TDataService__SERVER / Imc. }
    if FTName = '' then
      AddDisclosureRow(FocusHtml, 'server: the table could not be determined, so no DataService was looked up', LINE_INK)
    else
    begin
      var Found:= if FSrvClass <> '' then Format('%s (found by name; %d DataService classes)', [FSrvClass, FNDsClasses])
        else Format('no TDataService_%s_SERVER in the SERVER index', [FTName]);
      var Elsewhere:= if FSrvElsewhere <> 0 then Format('; %d access(es) to it outside the DataService not drawn', [FSrvElsewhere]) else '';
      AddDisclosureRow(FocusHtml, Format('server: %s; member accesses resolved to Imc%s.%s are [certain], SQL / ParamByName literals [inferred]',
        [Found, FTName, FProp]) + Elsewhere, LINE_INK);
    end;
    AddDisclosureRow(FocusHtml, 'positional Fields[i] / Params[i] reads are not shown -- they never name the column', LINE_INK);
    AddDisclosureRow(FocusHtml, Format('script-derived schema: %d tables; %s', [Length(FCatalog.TableSet.Names), SCHEMA_NOTE]), LINE_INK);
    if FTrigStale <> 0 then
      AddDisclosureRow(FocusHtml, Format('%d trigger(s) FOR %s in a script that differs from the index [stale source] -- not scanned', [FTrigStale, FTName]), LINE_INK);
    if FProcUnscanned <> 0 then
      AddDisclosureRow(FocusHtml, Format('%d procedure bodies not scanned', [FProcUnscanned]), LINE_INK);
    var Route:= Format('route: derived (path A) -- orm_links rows: %d on %s, %d on %s',
      [FOlCli.Rows, FileNameOf(FDbPath), FOlSrv.Rows, FileNameOf(FSrvDb)]);
    if (FOlCli.Rows <> 0) or (FOlSrv.Rows <> 0) then
      Route:= Route + ' -- the engine HAS links now; this chart does not read them yet (path B awaits the owner)';
    AddDisclosureRow(FocusHtml, Route, LINE_INK);
    FocusHtml.Append('</TABLE>');
    FSb.AppendLine(Format('  subgraph cluster_focus_%d {', [FNi]));
    FSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
    FSb.AppendLine('    label=""; margin=10;');
    FSb.AppendLine(Format('    %s [label=<%s>];', [FNid, FocusHtml.ToString]));
    FSb.AppendLine('  }');
  finally
    FocusHtml.Free;
  end;
  var First:= if FNTop <> '' then FNTop else if FNProp <> '' then FNProp else FNCol;
  if First <> '' then
    FSb.AppendLine(Format('  %s -> %s [style=invis];', [FNid, First]));
  FSb.AppendLine('}');
end;

{ the emitter object's properties, in the PS order (the file paths excluded) }
function TLandsWhereChart.ResultFields: TArray<TMetaField>;
begin
  var Outcomes: TArray<string>:= [];
  for var B in FBindSorted do
    Outcomes:= Outcomes + [B.Outcome];
  var NColumn:= 0;
  for var B in FIx.Bindings do
    if SameText(B.Outcome, O_COLUMN) then
      Inc(NColumn);
  var ClientRows: TArray<string>:= [];
  for var B in FBindSame do
    ClientRows:= ClientRows + [Format('%s:%s', [At(B.Dfm, B.Line), B.Control])];
  var TableField:= TMetaField.Str('Table', FTName);
  if FTName = '' then
    TableField.Json:= 'null';
  var ServerField:= TMetaField.Str('ServerClass', FSrvClass);
  if FSrvClass = '' then
    ServerField.Json:= 'null';
  var PropQ:= if FOrmSym.Present then FOrmSym.QName else '';
  var TableCol:= if FHasColumn then FTName + '.' + FCol else '';
  var ColLabel:= if FHasCs then FCs.Caption else '';
  var SrvCount:= Length(FSrvWrite) + Length(FSrvRead) + Length(FSrvOther);
  Result:= [TMetaField.Bool('TestChart', False), TMetaField.Str('ClientOutcomes', string.Join(',', Outcomes)),
    TMetaField.Int('IndexBindColumn', NColumn), TMetaField.Str('Selection', FSel), TMetaField.Str('Kind', FKind),
    TMetaField.Str('Property', PropQ), TableField, TMetaField.Str('TableColumn', TableCol),
    TMetaField.Str('ColumnState', FColState), TMetaField.Str('ChainOutcome', FChainOutcome), TMetaField.Str('StopReason', FStop),
    ServerField, TMetaField.Int('ServerRows', SrvCount)];
  Result:= Result + [TMetaField.Str('ServerWrite', RowAnchors(FSrvWrite)), TMetaField.Str('ServerRead', RowAnchors(FSrvRead)),
    TMetaField.Str('ServerOther', RowAnchors(FSrvOther)), TMetaField.Int('ServerElsewhere', FSrvElsewhere),
    TMetaField.Int('Triggers', Length(FTrigRows)), TMetaField.Str('TriggerNames', string.Join(',', FTrigNames)),
    TMetaField.Int('TriggersStale', FTrigStale), TMetaField.Int('Procedures', Length(FProcRows)),
    TMetaField.Str('ProcedureNames', string.Join(',', FProcNames)), TMetaField.Int('ClientBindings', Length(FBindSame)),
    TMetaField.Str('ClientRows', string.Join(',', ClientRows)), TMetaField.Int('ClientOther', Length(FBindOther))];
  Result:= Result + [TMetaField.Int('ConvProps', FConv.Props), TMetaField.Int('ConvOnTable', FConv.OnTable),
    TMetaField.Int('ConvColumn', FConv.Column), TMetaField.Str('ConvNonColumn', FConv.NonColumn),
    TMetaField.Str('ConvQuoted', FConv.Quoted), TMetaField.Str('ConvStale', FConv.Stale), TMetaField.Str('ColumnLabel', ColLabel),
    TMetaField.Int('DsClasses', FNDsClasses), TMetaField.Int('ParamByNameAll', FPbn.All), TMetaField.Int('ParamByNameDs', FPbn.InDataService),
    TMetaField.Int('ParamByNameCol', FPbn.Column), TMetaField.Int('OrmLinksCli', FOlCli.Rows), TMetaField.Int('OrmLinksSrv', FOlSrv.Rows)];
end;

function TLandsWhereChart.Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  CheckRoles;
  SelectField(pArgs.Target);
  { ---- 2. index-wide numbers, measured on this run (R10: never quoted) ---- }
  FIx:= FWalker.FieldBindingChains;
  MeasureConvention;
  MeasureParamByName;
  { ---- 3 .. 7 ---- }
  if FKind = KIND_ORM then
    ResolveOrm
  else
    ResolveDfm;
  ReadColumn;
  ReadServer;
  RecheckColumn;
  ReadDatabase;
  ReadClient;

  { ---- 8. dot ---- }
  FSb.AppendLine('digraph landswhere {');
  FSb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;');
  FSb.AppendLine('  nodesep=0.5; ranksep=0.6; splines=spline;');
  FSb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
  FSb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
  FSb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
  FSb.AppendLine('');
  DrawSelection;
  DrawColumn;
  DrawServer;
  DrawDatabase;
  DrawClient;
  DrawFocus;

  var Msgs: TArray<string>;
  Result.Layout:= DotLayout(pArgs.Dot, FSb.ToString, pOutDir, 'landswhere_' + TRegEx.Replace(FSel, '[^A-Za-z0-9]', '_'), Msgs);
  Result.LeftCount:= Length(FSrvWrite) + Length(FSrvRead) + Length(FSrvOther);
  Result.RightCount:= Length(FTrigRows);
  Result.ClickTargets:= Result.Layout.Anchors;
  Result.AllClickable:= Result.Layout.Anchors >= FAnchored;
  Result.Fields:= ResultFields + [TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', FAnchored),
    TMetaField.Bool('AllClickable', Result.AllClickable)];
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  { New-DiagramArtifact refuses before the PS emitter is reached, SQL index first }
  if pArgs.SqlDbPath = '' then
    raise EChartsQuestion.Create('lands-where needs -SqlDbPath: the SQL-script index clone (charts\scratch\db\SQL-drag-lint-sql.sqlite)');
  if pArgs.ServerDbPath = '' then
    raise EChartsQuestion.Create('lands-where needs -ServerDbPath: the SERVER clone (charts\scratch\db\SERVER-MicroniteMW1Service.sqlite); ' +
      '-DbPath is the CLIENT clone');
  var Chart:= TLandsWhereChart.Create(pArgs);
  try
    Result:= Chart.Emit(pArgs, pOutDir);
  finally
    Chart.Free;
  end;
end;

initialization
  RegisterChartQuestion(LANDS_WHERE_ID, Emit);

end.
