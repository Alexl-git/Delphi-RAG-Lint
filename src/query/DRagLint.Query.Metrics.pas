unit DRagLint.Query.Metrics;

{ drag-lint 1.56 -- lane MET-1: the metrics row API of gap-plan S3.
  One read-only pass over an index gives rows at four levels (routine, class, unit, folder) plus a
  total row, and two sections: repeated parameter groups (G-58) and one implementor / one
  descendant (G-59). DRagLint.CLI.Metrics prints them (`metrics`, G-48); later consumers
  (ask dependency-matrix / main-sequence / hotspots / risk, the panel column and the code lens)
  read the same rows.

  FROZEN by MET-1.1: the record fields, their meaning per level, the row order and the JSON
  member names below are a contract. Add a field or a member; never rename or re-define one.

  What a number means, per level:
    routines / classes / interfaces / units   how many rows of that kind the row covers
                                              (a routine row covers itself: routines = 1)
    cyclomatic      routine: symbol_facts.cyclomatic. Above: the SUM over the covered routines
    cyclomatic_max  the largest single routine value among the covered routines
    body_loc        routine: symbol_facts.body_loc. Above: the SUM over the covered routines that
                    are NOT nested in another routine (a nested routine's lines are already inside
                    its enclosing routine's body_loc)
    body_loc_max    the largest single routine value among the covered routines
    lines           routine: body span (impl_end_line - impl_start_line + 1). class: declaration
                    span. unit: last line of the unit symbol. folder / total: the sum over units
    comment_lines   comment lines (comment_facts, every style) inside the routine body / inside
                    the class declaration plus its routines' bodies / in the whole file
    params          routine: declared parameters. Above: the largest count among covered routines
    fan_in/fan_out  the coupling that exists at that level:
                    routine  distinct routines calling it / distinct routines it calls
                             (call_edges of confidence 'certain', self-calls excluded)
                    class    direct descendants + implementors in this index / declared ancestors
                    unit     units of this index that use it / units it uses (uses clauses)
                    folder   outside units using a unit of the folder / units used outside it
                    total    METRIC_NOT_MEASURED
  A folder row covers the units DIRECTLY in that folder (no roll-up into parent folders).
  Nothing is estimated: a routine without a symbol_facts row has no routine row. }

interface

uses
  System.SysUtils, System.JSON;

const
  /// <summary>Value of the "schema" member of the JSON document; bumped only on a breaking change.</summary>
  METRICS_JSON_SCHEMA = 'metrics/1';
  /// <summary>A fan_in / fan_out that the level does not have (the total row). JSON writes null.</summary>
  METRIC_NOT_MEASURED = -1;
  /// <summary>How many parameters a repeated parameter group has at least (G-58).</summary>
  PARAM_GROUP_MIN_PARAMS = 3;
  /// <summary>Default of TMetricsOptions.ParamGroupMinRoutines.</summary>
  PARAM_GROUP_MIN_ROUTINES = 3;

type
  /// <summary>Raised by LoadMetrics when the index cannot be read.</summary>
  EMetricsError = class(Exception);

  /// <summary>The level of a metrics row.</summary>
  TMetricLevel = (mlRoutine, mlClass, mlUnit, mlFolder, mlTotal);
  /// <summary>A selection of levels.</summary>
  TMetricLevels = set of TMetricLevel;

  /// <summary>One metrics row. Every level uses the same fields; the unit header says what each
  /// number means at each level.</summary>
  /// <remarks>Plain value record; no ownership.</remarks>
  TMetricRow = record
    /// <summary>The row's level.</summary>
    Level: TMetricLevel;
    /// <summary>routine / class: qualified name. unit: unit name. folder: directory path without
    /// a trailing delimiter. total: ''.</summary>
    Name: string;
    /// <summary>routine: qualified name of the owning class or enclosing routine, else the unit
    /// name. class: unit name. unit: its folder. folder / total: ''.</summary>
    Parent: string;
    /// <summary>routine / class: symbols.kind. unit: the unit symbol's kind ('unit', 'program',
    /// ...) or 'file' when the file has no unit symbol. folder: 'folder'. total: 'total'.</summary>
    Kind: string;
    /// <summary>Path of the file as stored in files.path; '' for folder and total.</summary>
    FilePath: string;
    /// <summary>routine: first body line (declaration line when it has no body). class:
    /// declaration line. unit: 1. folder / total: 0.</summary>
    Line: Integer;
    /// <summary>symbols.id for routine and class; the unit symbol's id for unit (0 for 'file');
    /// 0 for folder and total. Valid for the index it was read from only.</summary>
    SymbolId: Int64;
    /// <summary>files.id; 0 for folder and total.</summary>
    FileId: Int64;
    /// <summary>routine level only: True when the routine is declared inside another routine.</summary>
    Nested: Boolean;
    /// <summary>Unit rows covered (unit: 1; routine / class: 0).</summary>
    Units: Integer;
    /// <summary>Class rows covered, interfaces included (class: 1; routine: 0).</summary>
    Classes: Integer;
    /// <summary>Of Classes, how many are interfaces.</summary>
    Interfaces: Integer;
    /// <summary>Routine rows covered (routine: 1).</summary>
    Routines: Integer;
    /// <summary>Cyclomatic complexity: own value, or the sum over covered routines.</summary>
    Cyclomatic: Integer;
    /// <summary>Largest cyclomatic complexity of one covered routine.</summary>
    CyclomaticMax: Integer;
    /// <summary>Body lines: own value, or the sum over covered routines that are not nested.</summary>
    BodyLoc: Integer;
    /// <summary>Largest body_loc of one covered routine.</summary>
    BodyLocMax: Integer;
    /// <summary>Source lines spanned (see the unit header).</summary>
    Lines: Integer;
    /// <summary>Comment lines inside the row's span.</summary>
    CommentLines: Integer;
    /// <summary>Declared parameters, or the largest count among covered routines.</summary>
    Params: Integer;
    /// <summary>Incoming coupling of the level, or METRIC_NOT_MEASURED.</summary>
    FanIn: Integer;
    /// <summary>Outgoing coupling of the level, or METRIC_NOT_MEASURED.</summary>
    FanOut: Integer;
  end;

  /// <summary>A named place in the source: what a section row points at.</summary>
  TMetricSite = record
    /// <summary>Qualified name.</summary>
    Name: string;
    /// <summary>files.path.</summary>
    FilePath: string;
    /// <summary>1-based line.</summary>
    Line: Integer;
  end;

  /// <summary>G-58: parameters (name and type) that occur together in several routines.</summary>
  /// <remarks>Params is sorted and has at least PARAM_GROUP_MIN_PARAMS entries, each
  /// 'name: type' in lower case. Routines is every routine carrying all of them, sorted by
  /// name; the routines have at least TMetricsOptions.ParamGroupMinRoutines DIFFERENT bare names
  /// (overloads, overrides and a declaration with its implementors count once).</remarks>
  TParamGroup = record
    Params: TArray<string>;
    Routines: TArray<TMetricSite>;
  end;

  /// <summary>G-59: an interface with exactly one implementor, or a class with exactly one
  /// direct descendant, counted inside this index.</summary>
  /// <remarks>Kind is 'interface' or 'class' (the kind of Base). Only ancestor references the
  /// index resolved are counted, so a heir in a unit outside the index is not seen.</remarks>
  TSingleHeir = record
    Kind: string;
    Base: TMetricSite;
    Heir: TMetricSite;
  end;

  /// <summary>What LoadMetrics reads.</summary>
  TMetricsOptions = record
    /// <summary>Keep only rows of files whose path starts with this text (case-insensitive);
    /// '' = every file. Fan values are still counted over the whole index.</summary>
    PathPrefix: string;
    /// <summary>G-58: how many differently named routines must share a group.</summary>
    ParamGroupMinRoutines: Integer;
  end;

  /// <summary>The answer of LoadMetrics.</summary>
  /// <remarks>Row order is fixed: Routines and Classes by file path, line, name; Units by name,
  /// then path; Folders by path (all case-insensitive). ParamGroups: most routines first, then
  /// most parameters, then the first parameter. SingleHeirs: by kind, then name.</remarks>
  TMetricsReport = record
    /// <summary>The index that was read.</summary>
    DbPath: string;
    /// <summary>schema_meta 'indexed_at_unix' (0 when absent).</summary>
    IndexedAtUnix: Int64;
    Routines: TArray<TMetricRow>;
    Classes: TArray<TMetricRow>;
    Units: TArray<TMetricRow>;
    Folders: TArray<TMetricRow>;
    /// <summary>One row over every unit row of the report.</summary>
    Total: TMetricRow;
    ParamGroups: TArray<TParamGroup>;
    SingleHeirs: TArray<TSingleHeir>;
  end;

/// <summary>The options of a plain run: every file, PARAM_GROUP_MIN_ROUTINES.</summary>
/// <returns>The default options.</returns>
function DefaultMetricsOptions: TMetricsOptions;

/// <summary>Reads the metrics rows and both sections from an index.</summary>
/// <param name="pDbPath">An existing .sqlite index; opened read-only, nothing is written.</param>
/// <param name="pOptions">Path filter and the G-58 threshold.</param>
/// <returns>The report; arrays are empty (never nil-checked by callers) when nothing matches.</returns>
/// <exception cref="EMetricsError">The file is missing, or the store cannot be opened or read
/// (old schema, not an index); the message names the path and the cause.</exception>
/// <remarks>Not thread-safe; opens its own store and closes it before returning.</remarks>
function LoadMetrics(const pDbPath: string; const pOptions: TMetricsOptions): TMetricsReport;

/// <summary>The JSON / command-line spelling of a level.</summary>
/// <param name="pLevel">The level.</param>
/// <returns>'routine', 'class', 'unit', 'folder' or 'total'.</returns>
function MetricLevelName(pLevel: TMetricLevel): string;  // dl:ok unused-public-symbol@2473 -- REVIEWED 2026-11-27 MET-1: part of the frozen S3 row API; the later consumers (ask hotspots / dependency-matrix / risk) spell levels with it

/// <summary>Parses a level name as MetricLevelName spells it.</summary>
/// <param name="pText">The name, any case.</param>
/// <param name="pLevel">The level on success.</param>
/// <returns>False for an unknown name.</returns>
function TryParseMetricLevel(const pText: string; out pLevel: TMetricLevel): Boolean;

/// <summary>One row as a JSON object.</summary>
/// <param name="pRow">The row.</param>
/// <returns>A new object the caller owns. Members: level, name, parent, kind, file, line,
/// symbol_id, nested, units, classes, interfaces, routines, cyclomatic, cyclomatic_max, body_loc,
/// body_loc_max, lines, comment_lines, params, fan_in, fan_out (null = not measured).</returns>
function MetricRowToJson(const pRow: TMetricRow): TJSONObject;

/// <summary>The report as the `metrics --json` document.</summary>
/// <param name="pReport">The report.</param>
/// <param name="pLevels">Which row arrays to write; mlTotal is always written.</param>
/// <returns>A new object the caller owns: schema (METRICS_JSON_SCHEMA), db, indexed_at_unix,
/// total (a row), then the arrays folders / units / classes / routines for the levels asked,
/// then param_groups ([{params: [..], routines: [{name, file, line}]}]) and single_heirs
/// ([{kind, name, file, line, heir, heir_file, heir_line}]).</returns>
function MetricsToJson(const pReport: TMetricsReport; pLevels: TMetricLevels): TJSONObject;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.Math,
  FireDAC.Stan.Option, FireDAC.Comp.Client,
  DRagLint.Storage.SQLite;

const
  LEVEL_NAMES: array[TMetricLevel] of string = ('routine', 'class', 'unit', 'folder', 'total');
  KIND_FILE = 'file';
  KIND_FOLDER = 'folder';
  KIND_TOTAL = 'total';
  KIND_INTERFACE = 'interface';
  KIND_CLASS = 'class';
  KIND_RECORD = 'record';
  { A routine with more parameters contributes its first PARAM_GROUP_SCAN_CAP (sorted) to G-58,
    so the 3-subsets of one routine stay at 220 at most. }
  PARAM_GROUP_SCAN_CAP = 12;
  KEY_SEP = #1;

  SQL_FILES = 'SELECT id, path FROM files';
  SQL_UNIT_SYMBOLS = 'SELECT file_id, id, name, kind, end_line FROM symbols ' +
    'WHERE kind IN (''unit'', ''program'', ''library'', ''package'') ORDER BY id';
  SQL_COMMENTS = 'SELECT file_id, line, end_line FROM comment_facts ORDER BY file_id, line';
  SQL_ROUTINES = 'SELECT s.id, s.file_id, s.parent_id, s.kind, s.qualified_name, s.name, s.start_line, ' +
    's.impl_start_line, s.impl_end_line, f.cyclomatic, f.body_loc ' +
    'FROM symbol_facts f JOIN symbols s ON s.id = f.symbol_id ' +
    'WHERE s.kind IN (''function'', ''procedure'', ''method'', ''constructor'', ''destructor'', ''operator'')';
  { column order of SQL_ROUTINES }
  RC_ID = 0;
  RC_FILE = 1;
  RC_PARENT = 2;
  RC_KIND = 3;
  RC_QNAME = 4;
  RC_NAME = 5;
  RC_START = 6;
  RC_IMPL_START = 7;
  RC_IMPL_END = 8;
  RC_CYCLO = 9;
  RC_BODY = 10;
  { column order of SQL_TYPES }
  TC_ID = 0;
  TC_FILE = 1;
  TC_KIND = 2;
  TC_QNAME = 3;
  TC_START = 4;
  TC_END = 5;
  SQL_TYPES = 'SELECT id, file_id, kind, qualified_name, start_line, end_line FROM symbols ' +
    'WHERE kind IN (''class'', ''interface'', ''record'') ORDER BY id';
  SQL_PARAMS = 'SELECT parent_id, name, signature FROM symbols WHERE kind = ''param'' ORDER BY parent_id, id';
  SQL_CALL_PAIRS = 'SELECT r.enclosing_symbol_id AS caller, e.target_symbol_id AS callee ' +
    'FROM call_edges e JOIN refs r ON r.id = e.ref_id ' +
    'WHERE e.confidence = ''certain'' AND r.enclosing_symbol_id IS NOT NULL ' +
    'AND r.enclosing_symbol_id <> e.target_symbol_id GROUP BY 1, 2';
  SQL_ANCESTORS = 'SELECT symbol_id, ancestor_symbol_id FROM type_ancestors ORDER BY symbol_id, ordinal';
  SQL_USES = 'SELECT file_id, unit_name_norm, target_file_id FROM unit_uses';
  SQL_INDEXED_AT = 'SELECT value FROM schema_meta WHERE key = ''indexed_at_unix''';

type
  TCommentSpan = record
    First, Last: Integer;
  end;

  { Everything LoadMetrics holds while it reads; rows are kept in lists of indexes into the
    arrays so a symbol id resolves to its row in one lookup. }
  TMetricsLoader = class  // dl:ok high-response@6e02 -- REVIEWED 2026-11-27 MET-1: one private loader, one method per table it reads; splitting it would only spread the shared row dictionaries over several classes
  private
    FStore: TSQLiteSymbolStore;
    FOptions: TMetricsOptions;
    FFilePath: TDictionary<Int64, string>;
    FComments: TObjectDictionary<Int64, TList<TCommentSpan>>;
    FUnits: TList<TMetricRow>;
    FUnitOfFile: TDictionary<Int64, Integer>;
    FRoutines: TList<TMetricRow>;
    FRoutineOfSymbol: TDictionary<Int64, Integer>;
    FRoutineParent: TList<Int64>;
    FRoutineBareName: TList<string>;
    FRoutineParams: TObjectList<TStringList>;
    FClasses: TList<TMetricRow>;
    FClassOfSymbol: TDictionary<Int64, Integer>;
    FClassHasRoutine: TList<Boolean>;
    function Open(const pSql: string): TFDQuery;
    function Included(const pPath: string): Boolean;
    function CommentLinesIn(pFileId: Int64; pFirst, pLast: Integer): Integer;
    function UnitIndexOf(pFileId: Int64): Integer;
    function OwnerClassOf(pRoutine: Integer): Integer;
    procedure LoadFiles;
    procedure LoadComments;
    procedure LoadRoutines;
    procedure LoadParams;
    procedure LoadCallFans;
    procedure LoadTypes;
    procedure LoadUnitFans(var pFolders: TArray<TMetricRow>);
    procedure Aggregate;
    function BuildFolders: TArray<TMetricRow>;
    function BuildParamGroups: TArray<TParamGroup>;
    function BuildSingleHeirs: TArray<TSingleHeir>;
    function SiteOfRow(const pRow: TMetricRow): TMetricSite;
  public
    constructor Create(const pDbPath: string; const pOptions: TMetricsOptions);
    destructor Destroy; override;
    function Run(const pDbPath: string): TMetricsReport;
  end;

function DefaultMetricsOptions: TMetricsOptions;
begin
  Result.PathPrefix:= '';
  Result.ParamGroupMinRoutines:= PARAM_GROUP_MIN_ROUTINES;
end;

function MetricLevelName(pLevel: TMetricLevel): string;
begin
  Result:= LEVEL_NAMES[pLevel];
end;

function TryParseMetricLevel(const pText: string; out pLevel: TMetricLevel): Boolean;
begin
  Result:= False;
  pLevel:= mlRoutine;
  for var L:= Low(TMetricLevel) to High(TMetricLevel) do
    if SameText(pText, LEVEL_NAMES[L]) then
    begin
      pLevel:= L;
      Exit(True);
    end;
end;

function FanJson(pValue: Integer): TJSONValue;
begin
  Result:= if pValue = METRIC_NOT_MEASURED then TJSONValue(TJSONNull.Create) else TJSONValue(TJSONNumber.Create(pValue));
end;

function MetricRowToJson(const pRow: TMetricRow): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('level', MetricLevelName(pRow.Level));
  Result.AddPair('name', pRow.Name);
  Result.AddPair('parent', pRow.Parent);
  Result.AddPair('kind', pRow.Kind);
  Result.AddPair('file', pRow.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pRow.Line));
  Result.AddPair('symbol_id', TJSONNumber.Create(pRow.SymbolId));
  Result.AddPair('nested', TJSONBool.Create(pRow.Nested));
  Result.AddPair('units', TJSONNumber.Create(pRow.Units));
  Result.AddPair('classes', TJSONNumber.Create(pRow.Classes));
  Result.AddPair('interfaces', TJSONNumber.Create(pRow.Interfaces));
  Result.AddPair('routines', TJSONNumber.Create(pRow.Routines));
  Result.AddPair('cyclomatic', TJSONNumber.Create(pRow.Cyclomatic));
  Result.AddPair('cyclomatic_max', TJSONNumber.Create(pRow.CyclomaticMax));
  Result.AddPair('body_loc', TJSONNumber.Create(pRow.BodyLoc));
  Result.AddPair('body_loc_max', TJSONNumber.Create(pRow.BodyLocMax));
  Result.AddPair('lines', TJSONNumber.Create(pRow.Lines));
  Result.AddPair('comment_lines', TJSONNumber.Create(pRow.CommentLines));
  Result.AddPair('params', TJSONNumber.Create(pRow.Params));
  Result.AddPair('fan_in', FanJson(pRow.FanIn));
  Result.AddPair('fan_out', FanJson(pRow.FanOut));
end;

function RowsJson(const pRows: TArray<TMetricRow>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var LRow in pRows do
    Result.AddElement(MetricRowToJson(LRow));
end;

function SiteJson(const pSite: TMetricSite): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name', pSite.Name);
  Result.AddPair('file', pSite.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pSite.Line));
end;

function ParamGroupsJson(const pGroups: TArray<TParamGroup>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var LGroup in pGroups do
  begin
    var LObj:= TJSONObject.Create;
    Result.AddElement(LObj);
    var LParams:= TJSONArray.Create;
    LObj.AddPair('params', LParams);
    for var LParam in LGroup.Params do
      LParams.Add(LParam);
    var LSites:= TJSONArray.Create;
    LObj.AddPair('routines', LSites);
    for var LSite in LGroup.Routines do
      LSites.AddElement(SiteJson(LSite));
  end;
end;

function SingleHeirsJson(const pHeirs: TArray<TSingleHeir>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var LHeir in pHeirs do
  begin
    var LObj:= TJSONObject.Create;
    Result.AddElement(LObj);
    LObj.AddPair('kind', LHeir.Kind);
    LObj.AddPair('name', LHeir.Base.Name);
    LObj.AddPair('file', LHeir.Base.FilePath);
    LObj.AddPair('line', TJSONNumber.Create(LHeir.Base.Line));
    LObj.AddPair('heir', LHeir.Heir.Name);
    LObj.AddPair('heir_file', LHeir.Heir.FilePath);
    LObj.AddPair('heir_line', TJSONNumber.Create(LHeir.Heir.Line));
  end;
end;

function MetricsToJson(const pReport: TMetricsReport; pLevels: TMetricLevels): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('schema', METRICS_JSON_SCHEMA);
  Result.AddPair('db', pReport.DbPath);
  Result.AddPair('indexed_at_unix', TJSONNumber.Create(pReport.IndexedAtUnix));
  Result.AddPair('total', MetricRowToJson(pReport.Total));
  if mlFolder in pLevels then
    Result.AddPair('folders', RowsJson(pReport.Folders));
  if mlUnit in pLevels then
    Result.AddPair('units', RowsJson(pReport.Units));
  if mlClass in pLevels then
    Result.AddPair('classes', RowsJson(pReport.Classes));
  if mlRoutine in pLevels then
    Result.AddPair('routines', RowsJson(pReport.Routines));
  Result.AddPair('param_groups', ParamGroupsJson(pReport.ParamGroups));
  Result.AddPair('single_heirs', SingleHeirsJson(pReport.SingleHeirs));
end;

function NewRow(pLevel: TMetricLevel; const pKind: string): TMetricRow;
begin
  Result:= Default(TMetricRow);
  Result.Level:= pLevel;
  Result.Kind:= pKind;
end;

{ Adds a routine row's numbers to the row that covers it. }
procedure Cover(var pInto: TMetricRow; const pRoutine: TMetricRow);
begin
  Inc(pInto.Routines);
  Inc(pInto.Cyclomatic, pRoutine.Cyclomatic);
  pInto.CyclomaticMax:= Max(pInto.CyclomaticMax, pRoutine.Cyclomatic);
  if not pRoutine.Nested then
    Inc(pInto.BodyLoc, pRoutine.BodyLoc);
  pInto.BodyLocMax:= Max(pInto.BodyLocMax, pRoutine.BodyLoc);
  pInto.Params:= Max(pInto.Params, pRoutine.Params);
end;

{ Adds a unit (or folder) row to the folder (or total) row above it. }
procedure Roll(var pInto: TMetricRow; const pUnit: TMetricRow);
begin
  Inc(pInto.Units, pUnit.Units);
  Inc(pInto.Classes, pUnit.Classes);
  Inc(pInto.Interfaces, pUnit.Interfaces);
  Inc(pInto.Routines, pUnit.Routines);
  Inc(pInto.Cyclomatic, pUnit.Cyclomatic);
  pInto.CyclomaticMax:= Max(pInto.CyclomaticMax, pUnit.CyclomaticMax);
  Inc(pInto.BodyLoc, pUnit.BodyLoc);
  pInto.BodyLocMax:= Max(pInto.BodyLocMax, pUnit.BodyLocMax);
  Inc(pInto.Lines, pUnit.Lines);
  Inc(pInto.CommentLines, pUnit.CommentLines);
  pInto.Params:= Max(pInto.Params, pUnit.Params);
end;

function CompareByPlace(const pLeft, pRight: TMetricRow): Integer;
begin
  Result:= CompareText(pLeft.FilePath, pRight.FilePath);
  if Result = 0 then
    Result:= pLeft.Line - pRight.Line;
  if Result = 0 then
    Result:= CompareText(pLeft.Name, pRight.Name);
  if Result = 0 then
    Result:= CompareValue(pLeft.SymbolId, pRight.SymbolId);
end;

function CompareByName(const pLeft, pRight: TMetricRow): Integer;
begin
  Result:= CompareText(pLeft.Name, pRight.Name);
  if Result = 0 then
    Result:= CompareText(pLeft.FilePath, pRight.FilePath);
end;

{ ---- TMetricsLoader ---- }

constructor TMetricsLoader.Create(const pDbPath: string; const pOptions: TMetricsOptions);
begin
  inherited Create;
  FOptions:= pOptions;
  FFilePath:= TDictionary<Int64, string>.Create;
  FComments:= TObjectDictionary<Int64, TList<TCommentSpan>>.Create([doOwnsValues]);
  FUnits:= TList<TMetricRow>.Create;
  FUnitOfFile:= TDictionary<Int64, Integer>.Create;
  FRoutines:= TList<TMetricRow>.Create;
  FRoutineOfSymbol:= TDictionary<Int64, Integer>.Create;
  FRoutineParent:= TList<Int64>.Create;
  FRoutineBareName:= TList<string>.Create;
  FRoutineParams:= TObjectList<TStringList>.Create(True);
  FClasses:= TList<TMetricRow>.Create;
  FClassOfSymbol:= TDictionary<Int64, Integer>.Create;
  FClassHasRoutine:= TList<Boolean>.Create;
  FStore:= TSQLiteSymbolStore.CreateReadable(pDbPath, True);
end;

destructor TMetricsLoader.Destroy;
begin
  FStore.Free;
  FClassHasRoutine.Free;
  FClassOfSymbol.Free;
  FClasses.Free;
  FRoutineParams.Free;
  FRoutineBareName.Free;
  FRoutineParent.Free;
  FRoutineOfSymbol.Free;
  FRoutines.Free;
  FUnitOfFile.Free;
  FUnits.Free;
  FComments.Free;
  FFilePath.Free;
  inherited Destroy;
end;

function TMetricsLoader.Open(const pSql: string): TFDQuery;
begin
  Result:= TFDQuery.Create(nil);
  try
    Result.Connection:= FStore.GetConnection;
    Result.FetchOptions.Mode:= fmAll;
    Result.FetchOptions.Unidirectional:= True;
    Result.SQL.Text:= pSql;
    Result.Open;  // dl:ok dataset-open-without-close@f8d5 -- REVIEWED 2026-11-27 MET-1: Open returns the opened query to its caller; the except arm frees it when Open raises, and every caller frees it in a finally
  except
    Result.Free;
    raise;
  end;
end;

function TMetricsLoader.Included(const pPath: string): Boolean;
begin
  Result:= (FOptions.PathPrefix = '') or
    SameText(Copy(pPath, 1, Length(FOptions.PathPrefix)), FOptions.PathPrefix);
end;

function TMetricsLoader.CommentLinesIn(pFileId: Int64; pFirst, pLast: Integer): Integer;
var
  LSpans: TList<TCommentSpan>;
  LLow, LHigh, LMid: Integer;
begin
  Result:= 0;
  if (pLast < pFirst) or not FComments.TryGetValue(pFileId, LSpans) then
    Exit;
  { first span that starts at or after pFirst (the list is sorted by First) }
  LLow:= 0;
  LHigh:= LSpans.Count;
  while LLow < LHigh do
  begin
    LMid:= (LLow + LHigh) div 2;
    if LSpans[LMid].First < pFirst then
      LLow:= LMid + 1
    else
      LHigh:= LMid;
  end;
  while (LLow < LSpans.Count) and (LSpans[LLow].First <= pLast) do
  begin
    Inc(Result, Min(LSpans[LLow].Last, pLast) - LSpans[LLow].First + 1);
    Inc(LLow);
  end;
end;

{ The unit row of a file; a file without a unit symbol gets a 'file' row on first use. }
function TMetricsLoader.UnitIndexOf(pFileId: Int64): Integer;
var
  LRow: TMetricRow;
  LPath: string;
begin
  if FUnitOfFile.TryGetValue(pFileId, Result) then
    Exit;
  FFilePath.TryGetValue(pFileId, LPath);
  LRow:= NewRow(mlUnit, KIND_FILE);
  LRow.Name:= ChangeFileExt(ExtractFileName(LPath), '');
  LRow.Parent:= ExcludeTrailingPathDelimiter(ExtractFilePath(LPath));
  LRow.FilePath:= LPath;
  LRow.Line:= 1;
  LRow.FileId:= pFileId;
  LRow.Units:= 1;
  Result:= FUnits.Add(LRow);
  FUnitOfFile.Add(pFileId, Result);
end;

{ The class row that covers a routine: its parent type, or the owner of the routine it is
  nested in; -1 for a routine of the unit. }
function TMetricsLoader.OwnerClassOf(pRoutine: Integer): Integer;
var
  LParent: Int64;
  LOuter, LGuard: Integer;
begin
  LGuard:= 0;
  while True do
  begin
    LParent:= FRoutineParent[pRoutine];
    if FClassOfSymbol.TryGetValue(LParent, Result) then
      Exit;
    Inc(LGuard);
    if (LGuard > FRoutines.Count) or not FRoutineOfSymbol.TryGetValue(LParent, LOuter) then
      Exit(-1);
    pRoutine:= LOuter;
  end;
end;

procedure TMetricsLoader.LoadFiles;
var
  Q: TFDQuery;
  LRow: TMetricRow;
  LFileId: Int64;
  LIndex: Integer;
begin
  Q:= Open(SQL_FILES);
  try
    while not Q.Eof do
    begin
      FFilePath.AddOrSetValue(Q.Fields[0].AsLargeInt, Q.Fields[1].AsString);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  Q:= Open(SQL_UNIT_SYMBOLS);
  try
    while not Q.Eof do
    begin
      LFileId:= Q.Fields[0].AsLargeInt;
      if not FUnitOfFile.ContainsKey(LFileId) then
      begin
        LIndex:= UnitIndexOf(LFileId);
        LRow:= FUnits[LIndex];
        LRow.SymbolId:= Q.Fields[1].AsLargeInt;
        LRow.Name:= Q.Fields[2].AsString;
        LRow.Kind:= Q.Fields[3].AsString;
        LRow.Lines:= Q.Fields[4].AsInteger;
        FUnits[LIndex]:= LRow;
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TMetricsLoader.LoadComments;
var
  Q: TFDQuery;
  LSpans: TList<TCommentSpan>;
  LSpan: TCommentSpan;
  LFileId: Int64;
begin
  Q:= Open(SQL_COMMENTS);
  try
    while not Q.Eof do
    begin
      LFileId:= Q.Fields[0].AsLargeInt;
      if not FComments.TryGetValue(LFileId, LSpans) then
      begin
        LSpans:= TList<TCommentSpan>.Create;
        FComments.Add(LFileId, LSpans);
      end;
      LSpan.First:= Q.Fields[1].AsInteger;
      LSpan.Last:= Max(LSpan.First, Q.Fields[2].AsInteger);
      LSpans.Add(LSpan);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TMetricsLoader.LoadRoutines;
var
  Q: TFDQuery;
  LRow: TMetricRow;
  LIndex, LOuter: Integer;
begin
  Q:= Open(SQL_ROUTINES);
  try
    while not Q.Eof do
    begin
      LRow:= NewRow(mlRoutine, Q.Fields[RC_KIND].AsString);
      LRow.SymbolId:= Q.Fields[RC_ID].AsLargeInt;
      LRow.FileId:= Q.Fields[RC_FILE].AsLargeInt;
      FFilePath.TryGetValue(LRow.FileId, LRow.FilePath);
      LRow.Name:= Q.Fields[RC_QNAME].AsString;
      LRow.Routines:= 1;
      LRow.Cyclomatic:= Q.Fields[RC_CYCLO].AsInteger;
      LRow.CyclomaticMax:= LRow.Cyclomatic;
      LRow.BodyLoc:= Q.Fields[RC_BODY].AsInteger;
      LRow.BodyLocMax:= LRow.BodyLoc;
      if Q.Fields[RC_IMPL_START].IsNull then
        LRow.Line:= Q.Fields[RC_START].AsInteger
      else
      begin
        LRow.Line:= Q.Fields[RC_IMPL_START].AsInteger;
        LRow.Lines:= Max(0, Q.Fields[RC_IMPL_END].AsInteger - LRow.Line + 1);
        LRow.CommentLines:= CommentLinesIn(LRow.FileId, LRow.Line, LRow.Line + LRow.Lines - 1);
      end;
      if not FRoutineOfSymbol.ContainsKey(LRow.SymbolId) then
      begin
        LIndex:= FRoutines.Add(LRow);
        FRoutineOfSymbol.Add(LRow.SymbolId, LIndex);
        FRoutineParent.Add(Q.Fields[RC_PARENT].AsLargeInt);
        FRoutineBareName.Add(LowerCase(Q.Fields[RC_NAME].AsString));
        FRoutineParams.Add(nil);
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
  for LIndex:= 0 to FRoutines.Count - 1 do
    if FRoutineOfSymbol.TryGetValue(FRoutineParent[LIndex], LOuter) then
    begin
      LRow:= FRoutines[LIndex];
      LRow.Nested:= True;
      LRow.Parent:= FRoutines[LOuter].Name;
      FRoutines[LIndex]:= LRow;
    end;
end;

procedure TMetricsLoader.LoadParams;
var
  Q: TFDQuery;
  LIndex: Integer;
  LRow: TMetricRow;
  LKey: string;
begin
  Q:= Open(SQL_PARAMS);
  try
    while not Q.Eof do
    begin
      if FRoutineOfSymbol.TryGetValue(Q.Fields[0].AsLargeInt, LIndex) then
      begin
        LRow:= FRoutines[LIndex];
        Inc(LRow.Params);
        FRoutines[LIndex]:= LRow;
        if FRoutineParams[LIndex] = nil then
        begin
          FRoutineParams[LIndex]:= TStringList.Create;
          FRoutineParams[LIndex].Sorted:= True;
          FRoutineParams[LIndex].Duplicates:= dupIgnore;
        end;
        LKey:= LowerCase(Q.Fields[1].AsString + ': ' + StringReplace(Q.Fields[2].AsString, ' ', '', [rfReplaceAll]));
        FRoutineParams[LIndex].Add(LKey);
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TMetricsLoader.LoadCallFans;
var
  Q: TFDQuery;
  LCaller, LCallee: Integer;
  LRow: TMetricRow;
begin
  Q:= Open(SQL_CALL_PAIRS);
  try
    while not Q.Eof do
    begin
      { both ends must be routine rows: a call from an initialization section or to a routine
        without facts is not a routine-to-routine coupling this table can show }
      if FRoutineOfSymbol.TryGetValue(Q.Fields[0].AsLargeInt, LCaller) and
         FRoutineOfSymbol.TryGetValue(Q.Fields[1].AsLargeInt, LCallee) then
      begin
        LRow:= FRoutines[LCaller];
        Inc(LRow.FanOut);
        FRoutines[LCaller]:= LRow;
        LRow:= FRoutines[LCallee];
        Inc(LRow.FanIn);
        FRoutines[LCallee]:= LRow;
      end;
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

procedure TMetricsLoader.LoadTypes;
var
  Q: TFDQuery;
  LRow: TMetricRow;
  LByName: TDictionary<string, Integer>;
  LKey: string;
  LIndex, LSpan, LDescendant, LAncestor: Integer;
  LSeen: TDictionary<string, Boolean>;
begin
  LByName:= TDictionary<string, Integer>.Create;
  try
    Q:= Open(SQL_TYPES);
    try
      while not Q.Eof do
      begin
        LRow:= NewRow(mlClass, Q.Fields[TC_KIND].AsString);
        LRow.SymbolId:= Q.Fields[TC_ID].AsLargeInt;
        LRow.FileId:= Q.Fields[TC_FILE].AsLargeInt;
        FFilePath.TryGetValue(LRow.FileId, LRow.FilePath);
        LRow.Name:= Q.Fields[TC_QNAME].AsString;
        LRow.Line:= Q.Fields[TC_START].AsInteger;
        LSpan:= Max(1, Q.Fields[TC_END].AsInteger - LRow.Line + 1);
        LRow.Lines:= LSpan;
        LRow.Classes:= 1;
        if LRow.Kind = KIND_INTERFACE then
          LRow.Interfaces:= 1;
        { a forward declaration and the full declaration are two symbols of one type: one row,
          placed at the longer declaration, reachable by both ids }
        LKey:= IntToStr(LRow.FileId) + KEY_SEP + LowerCase(LRow.Name);
        if LByName.TryGetValue(LKey, LIndex) then
        begin
          if LSpan > FClasses[LIndex].Lines then
            FClasses[LIndex]:= LRow;
        end
        else
        begin
          LIndex:= FClasses.Add(LRow);
          FClassHasRoutine.Add(False);
          LByName.Add(LKey, LIndex);
        end;
        FClassOfSymbol.AddOrSetValue(LRow.SymbolId, LIndex);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    LByName.Free;
  end;
  LSeen:= TDictionary<string, Boolean>.Create;
  try
    Q:= Open(SQL_ANCESTORS);
    try
      while not Q.Eof do
      begin
        if FClassOfSymbol.TryGetValue(Q.Fields[0].AsLargeInt, LDescendant) then
        begin
          LRow:= FClasses[LDescendant];
          Inc(LRow.FanOut);
          FClasses[LDescendant]:= LRow;
          if (not Q.Fields[1].IsNull) and FClassOfSymbol.TryGetValue(Q.Fields[1].AsLargeInt, LAncestor) and
             (LAncestor <> LDescendant) then
          begin
            LKey:= IntToStr(LAncestor) + KEY_SEP + IntToStr(LDescendant);
            if not LSeen.ContainsKey(LKey) then
            begin
              LSeen.Add(LKey, True);
              LRow:= FClasses[LAncestor];
              Inc(LRow.FanIn);
              FClasses[LAncestor]:= LRow;
            end;
          end;
        end;
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    LSeen.Free;
  end;
end;

{ Fills fan_in / fan_out of the unit rows and of pFolders (already built, sorted by path). }
procedure TMetricsLoader.LoadUnitFans(var pFolders: TArray<TMetricRow>);
var
  Q: TFDQuery;
  LUnitOut, LUnitIn, LFolderOut, LFolderIn: TDictionary<string, Boolean>;
  LFolderIndex: TDictionary<string, Integer>;
  LFrom, LTo, LFolder: Integer;
  LFromId, LToId: Int64;
  LFromDir, LToDir, LName: string;
  LRow: TMetricRow;
  LHasTarget: Boolean;

  function FirstTime(pSeen: TDictionary<string, Boolean>; const pKey: string): Boolean;
  begin
    Result:= not pSeen.ContainsKey(pKey);
    if Result then
      pSeen.Add(pKey, True);
  end;

begin
  LUnitOut:= TDictionary<string, Boolean>.Create;
  LUnitIn:= TDictionary<string, Boolean>.Create;
  LFolderOut:= TDictionary<string, Boolean>.Create;
  LFolderIn:= TDictionary<string, Boolean>.Create;
  LFolderIndex:= TDictionary<string, Integer>.Create;
  try
    for LFolder:= 0 to High(pFolders) do
      LFolderIndex.AddOrSetValue(LowerCase(pFolders[LFolder].Name), LFolder);
    Q:= Open(SQL_USES);
    try
      while not Q.Eof do
      begin
        LFromId:= Q.Fields[0].AsLargeInt;
        LName:= Q.Fields[1].AsString;
        LHasTarget:= not Q.Fields[2].IsNull;
        LToId:= if LHasTarget then Q.Fields[2].AsLargeInt else 0;
        if FUnitOfFile.TryGetValue(LFromId, LFrom) and not (LHasTarget and (LToId = LFromId)) then
        begin
          LFromDir:= LowerCase(FUnits[LFrom].Parent);
          if FirstTime(LUnitOut, IntToStr(LFromId) + KEY_SEP + LName) then
          begin
            LRow:= FUnits[LFrom];
            Inc(LRow.FanOut);
            FUnits[LFrom]:= LRow;
          end;
          LToDir:= '';
          if LHasTarget and FUnitOfFile.TryGetValue(LToId, LTo) then
          begin
            LToDir:= LowerCase(FUnits[LTo].Parent);
            if FirstTime(LUnitIn, IntToStr(LToId) + KEY_SEP + IntToStr(LFromId)) then
            begin
              LRow:= FUnits[LTo];
              Inc(LRow.FanIn);
              FUnits[LTo]:= LRow;
            end;
          end
          else
            LHasTarget:= False;
          { a use of a unit that is not in this index leaves the folder by definition }
          if (not LHasTarget) or (LToDir <> LFromDir) then
          begin
            if LFolderIndex.TryGetValue(LFromDir, LFolder) and
               FirstTime(LFolderOut, LFromDir + KEY_SEP + LName) then
              Inc(pFolders[LFolder].FanOut);
            if LHasTarget and LFolderIndex.TryGetValue(LToDir, LFolder) and
               FirstTime(LFolderIn, LToDir + KEY_SEP + IntToStr(LFromId)) then
              Inc(pFolders[LFolder].FanIn);
          end;
        end;
        Q.Next;
      end;
    finally
      Q.Free;
    end;
  finally
    LFolderIndex.Free;
    LFolderIn.Free;
    LFolderOut.Free;
    LUnitIn.Free;
    LUnitOut.Free;
  end;
end;

{ Rolls every routine into its class and its unit, every class into its unit. }
procedure TMetricsLoader.Aggregate;
var
  LIndex, LClass, LUnit: Integer;
  LRow, LInto: TMetricRow;
begin
  for LIndex:= 0 to FRoutines.Count - 1 do
  begin
    LRow:= FRoutines[LIndex];
    LUnit:= UnitIndexOf(LRow.FileId);
    LClass:= OwnerClassOf(LIndex);
    if LClass >= 0 then
    begin
      LInto:= FClasses[LClass];
      Cover(LInto, LRow);
      Inc(LInto.CommentLines, LRow.CommentLines);
      FClasses[LClass]:= LInto;
      FClassHasRoutine[LClass]:= True;
    end;
    if LRow.Parent = '' then
    begin
      LRow.Parent:= if LClass >= 0 then FClasses[LClass].Name else FUnits[LUnit].Name;
      FRoutines[LIndex]:= LRow;
    end;
    LInto:= FUnits[LUnit];
    Cover(LInto, LRow);
    FUnits[LUnit]:= LInto;
  end;
  for LIndex:= 0 to FClasses.Count - 1 do
  begin
    LRow:= FClasses[LIndex];
    { a plain data record is not a class row; a record with routines is }
    if (LRow.Kind = KIND_RECORD) and not FClassHasRoutine[LIndex] then
      Continue;
    LUnit:= UnitIndexOf(LRow.FileId);
    LRow.Parent:= FUnits[LUnit].Name;
    Inc(LRow.CommentLines, CommentLinesIn(LRow.FileId, LRow.Line, LRow.Line + LRow.Lines - 1));
    FClasses[LIndex]:= LRow;
    LInto:= FUnits[LUnit];
    Inc(LInto.Classes);
    Inc(LInto.Interfaces, LRow.Interfaces);
    FUnits[LUnit]:= LInto;
  end;
  for LIndex:= 0 to FUnits.Count - 1 do
  begin
    LRow:= FUnits[LIndex];
    LRow.CommentLines:= CommentLinesIn(LRow.FileId, 1, MaxInt - 1);
    FUnits[LIndex]:= LRow;
  end;
end;

{ One row per folder that holds an included unit, sorted by path. }
function TMetricsLoader.BuildFolders: TArray<TMetricRow>;
var
  LIndexOf: TDictionary<string, Integer>;
  LUnit, LRow: TMetricRow;
  LIndex: Integer;
begin
  Result:= nil;
  LIndexOf:= TDictionary<string, Integer>.Create;
  try
    for LUnit in FUnits do
      if Included(LUnit.FilePath) then
      begin
        if not LIndexOf.TryGetValue(LowerCase(LUnit.Parent), LIndex) then
        begin
          LRow:= NewRow(mlFolder, KIND_FOLDER);
          LRow.Name:= LUnit.Parent;
          LIndex:= Length(Result);
          Result:= Result + [LRow];
          LIndexOf.Add(LowerCase(LUnit.Parent), LIndex);
        end;
        Roll(Result[LIndex], LUnit);
      end;
  finally
    LIndexOf.Free;
  end;
  TArray.Sort<TMetricRow>(Result, TComparer<TMetricRow>.Construct(CompareByName));
end;

function TMetricsLoader.SiteOfRow(const pRow: TMetricRow): TMetricSite;
begin
  Result.Name:= pRow.Name;
  Result.FilePath:= pRow.FilePath;
  Result.Line:= pRow.Line;
end;

function CompareSites(const pLeft, pRight: TMetricSite): Integer;
begin
  Result:= CompareText(pLeft.Name, pRight.Name);
  if Result = 0 then
    Result:= CompareText(pLeft.FilePath, pRight.FilePath);
  if Result = 0 then
    Result:= pLeft.Line - pRight.Line;
end;

function CompareParamGroups(const pLeft, pRight: TParamGroup): Integer;
begin
  Result:= Length(pRight.Routines) - Length(pLeft.Routines);
  if Result = 0 then
    Result:= Length(pRight.Params) - Length(pLeft.Params);
  if Result = 0 then
    Result:= CompareStr(string.Join(KEY_SEP, pLeft.Params), string.Join(KEY_SEP, pRight.Params));
end;

{ G-58. Every 3-subset of a routine's parameters is a key; a key carried by routines of enough
  different bare names is repeated. Keys with the SAME routine set are one group whose parameters
  are their union, so a clump of four shows as one row of four, not as four rows of three. }
function TMetricsLoader.BuildParamGroups: TArray<TParamGroup>;
var
  LByTriple: TObjectDictionary<string, TList<Integer>>;
  LBySet: TObjectDictionary<string, TStringList>;
  LParams, LUnion: TStringList;
  LCarriers: TList<Integer>;
  LNames: TDictionary<string, Boolean>;
  LKey, LSetKey: string;
  LRoutine, LCount, A, B, C: Integer;
  LGroup: TParamGroup;
  LIds: TArray<string>;
begin
  Result:= nil;
  LByTriple:= TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  LBySet:= TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  LNames:= TDictionary<string, Boolean>.Create;
  try
    for LRoutine:= 0 to FRoutines.Count - 1 do
    begin
      LParams:= FRoutineParams[LRoutine];
      if (LParams = nil) or (LParams.Count < PARAM_GROUP_MIN_PARAMS) or
         not Included(FRoutines[LRoutine].FilePath) then
        Continue;
      LCount:= Min(LParams.Count, PARAM_GROUP_SCAN_CAP);
      for A:= 0 to LCount - PARAM_GROUP_MIN_PARAMS do
        for B:= A + 1 to LCount - PARAM_GROUP_MIN_PARAMS + 1 do
          for C:= B + 1 to LCount - 1 do
          begin
            LKey:= LParams[A] + KEY_SEP + LParams[B] + KEY_SEP + LParams[C];
            if not LByTriple.TryGetValue(LKey, LCarriers) then
            begin
              LCarriers:= TList<Integer>.Create;
              LByTriple.Add(LKey, LCarriers);
            end;
            LCarriers.Add(LRoutine);
          end;
    end;
    for var LPair in LByTriple do
    begin
      LNames.Clear;
      for LRoutine in LPair.Value do
        LNames.AddOrSetValue(FRoutineBareName[LRoutine], True);
      if LNames.Count < FOptions.ParamGroupMinRoutines then
        Continue;
      { routines were appended in ascending index order, so the joined list is canonical }
      SetLength(LIds, LPair.Value.Count);
      for A:= 0 to LPair.Value.Count - 1 do
        LIds[A]:= IntToStr(LPair.Value[A]);
      LSetKey:= string.Join(',', LIds);
      if not LBySet.TryGetValue(LSetKey, LUnion) then
      begin
        LUnion:= TStringList.Create;
        LUnion.Sorted:= True;
        LUnion.Duplicates:= dupIgnore;
        LBySet.Add(LSetKey, LUnion);
      end;
      for var LParam in LPair.Key.Split([KEY_SEP]) do
        LUnion.Add(LParam);
    end;
    for var LSet in LBySet do
    begin
      LGroup.Params:= LSet.Value.ToStringArray;
      LGroup.Routines:= nil;
      for var LId in LSet.Key.Split([',']) do
        LGroup.Routines:= LGroup.Routines + [SiteOfRow(FRoutines[StrToInt(LId)])];
      TArray.Sort<TMetricSite>(LGroup.Routines, TComparer<TMetricSite>.Construct(CompareSites));
      Result:= Result + [LGroup];
    end;
  finally
    LNames.Free;
    LBySet.Free;
    LByTriple.Free;
  end;
  TArray.Sort<TParamGroup>(Result, TComparer<TParamGroup>.Construct(CompareParamGroups));
end;

function CompareSingleHeirs(const pLeft, pRight: TSingleHeir): Integer;
begin
  Result:= CompareStr(pRight.Kind, pLeft.Kind); { 'interface' before 'class' }
  if Result = 0 then
    Result:= CompareSites(pLeft.Base, pRight.Base);
end;

{ G-59. fan_in of a class row is already "distinct direct heirs in this index"; a row with
  exactly one names that heir. }
function TMetricsLoader.BuildSingleHeirs: TArray<TSingleHeir>;
var
  Q: TFDQuery;
  LHeirOf: TDictionary<Integer, Integer>;
  LDescendant, LAncestor: Integer;
  LItem: TSingleHeir;
begin
  Result:= nil;
  LHeirOf:= TDictionary<Integer, Integer>.Create;
  try
    Q:= Open(SQL_ANCESTORS);
    try
      while not Q.Eof do
      begin
        if (not Q.Fields[1].IsNull) and FClassOfSymbol.TryGetValue(Q.Fields[0].AsLargeInt, LDescendant) and
           FClassOfSymbol.TryGetValue(Q.Fields[1].AsLargeInt, LAncestor) and (LAncestor <> LDescendant) then
          LHeirOf.AddOrSetValue(LAncestor, LDescendant);
        Q.Next;
      end;
    finally
      Q.Free;
    end;
    for var LPair in LHeirOf do
      if (FClasses[LPair.Key].FanIn = 1) and Included(FClasses[LPair.Key].FilePath) and
         ((FClasses[LPair.Key].Kind = KIND_INTERFACE) or (FClasses[LPair.Key].Kind = KIND_CLASS)) then
      begin
        LItem.Kind:= FClasses[LPair.Key].Kind;
        LItem.Base:= SiteOfRow(FClasses[LPair.Key]);
        LItem.Heir:= SiteOfRow(FClasses[LPair.Value]);
        Result:= Result + [LItem];
      end;
  finally
    LHeirOf.Free;
  end;
  TArray.Sort<TSingleHeir>(Result, TComparer<TSingleHeir>.Construct(CompareSingleHeirs));
end;

function TMetricsLoader.Run(const pDbPath: string): TMetricsReport;
var
  Q: TFDQuery;
  LRow: TMetricRow;
  LIndex: Integer;
begin
  Result:= Default(TMetricsReport);
  Result.DbPath:= pDbPath;
  Q:= Open(SQL_INDEXED_AT);
  try
    if not Q.Eof then
      Result.IndexedAtUnix:= StrToInt64Def(Q.Fields[0].AsString, 0);
  finally
    Q.Free;
  end;
  LoadFiles;
  LoadComments;
  LoadRoutines;
  LoadParams;
  LoadCallFans;
  LoadTypes;
  Aggregate;
  Result.Folders:= BuildFolders;
  LoadUnitFans(Result.Folders);
  for LRow in FRoutines do
    if Included(LRow.FilePath) then
      Result.Routines:= Result.Routines + [LRow];
  for LIndex:= 0 to FClasses.Count - 1 do
  begin
    LRow:= FClasses[LIndex];
    if Included(LRow.FilePath) and ((LRow.Kind <> KIND_RECORD) or FClassHasRoutine[LIndex]) then
      Result.Classes:= Result.Classes + [LRow];
  end;
  Result.Total:= NewRow(mlTotal, KIND_TOTAL);
  Result.Total.FanIn:= METRIC_NOT_MEASURED;
  Result.Total.FanOut:= METRIC_NOT_MEASURED;
  for LRow in FUnits do
    if Included(LRow.FilePath) then
    begin
      Result.Units:= Result.Units + [LRow];
      Roll(Result.Total, LRow);
    end;
  TArray.Sort<TMetricRow>(Result.Routines, TComparer<TMetricRow>.Construct(CompareByPlace));
  TArray.Sort<TMetricRow>(Result.Classes, TComparer<TMetricRow>.Construct(CompareByPlace));
  TArray.Sort<TMetricRow>(Result.Units, TComparer<TMetricRow>.Construct(CompareByName));
  Result.ParamGroups:= BuildParamGroups;
  Result.SingleHeirs:= BuildSingleHeirs;
end;

function LoadMetrics(const pDbPath: string; const pOptions: TMetricsOptions): TMetricsReport;
var
  LLoader: TMetricsLoader;
begin
  if not FileExists(pDbPath) then
    raise EMetricsError.Create('index not found: ' + pDbPath);
  try
    LLoader:= TMetricsLoader.Create(pDbPath, pOptions);
    try
      Result:= LLoader.Run(pDbPath);
    finally
      LLoader.Free;
    end;
  except
    on E: EMetricsError do
      raise;
    on E: Exception do
      raise EMetricsError.Create('cannot read index ' + pDbPath + ': ' + E.Message);
  end;
end;

end.
