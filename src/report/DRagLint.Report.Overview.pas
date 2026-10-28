unit DRagLint.Report.Overview;

// ---------------------------------------------------------------------------
// `drag-lint overview --db <db> [--max-rows N] [--json]` -- the ONE bounded call
// for an agent's first turn (XERJ item 6). Six sections in a fixed order, each
// a pure reader of the index, each capped, each reporting its own cap:
//
//   freshness    what the index is and how old (schema_meta, files, symbols)
//   counts       symbols per kind
//   layers       units by dependency layer (unit_uses); a unit in or above a
//                cycle is listed in the final `cyclic` row
//   fanin        the most-referenced names (the same SQL as `top`)
//   entrypoints  program files, initialization/finalization, dfm event handlers
//   forms        symbols of kind 'form'
//
// The cap reporting (ReportSectionCap) is deliberately LOCAL: gaps/xj-1 adds a
// shared "N omitted by cap" helper to the CLI; once both are merged this one
// procedure can be replaced by a call to it (same shape: shown, total, cap,
// flag, optional JSON object).
// ---------------------------------------------------------------------------

interface

const
  /// <summary>Rows each section shows when `--max-rows` is not given.</summary>
  OVERVIEW_DEFAULT_MAX_ROWS = 20;

/// <summary>Prints the six-section project overview of the index at ADbPath.</summary>
/// <param name="ADbPath">An existing project index (.sqlite); opened read-only.</param>
/// <param name="AMaxRows">Row cap applied to every section; values below 1 mean
/// OVERVIEW_DEFAULT_MAX_ROWS.</param>
/// <param name="AJson">True prints one JSON object with one key per section
/// (freshness, counts, layers, fanin, entrypoints, forms), each holding
/// `total`, `cap`, `omitted` and `rows`; False prints text.</param>
/// <returns>0 on success, 2 when ADbPath is empty or does not exist. A capped
/// section never changes the exit code.</returns>
/// <remarks>Never writes to the DB. Output is bounded: at most 6 sections x
/// AMaxRows rows, plus the first CNamesPerLayer unit names of each layer row.</remarks>
function RunOverview(const ADbPath: string; AMaxRows: Integer; AJson: Boolean): Integer;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils,
  System.DateUtils, System.Math, System.JSON,
  Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Param,
  DRagLint.Storage.FileMembership;

const
  CNamesPerLayer = 8;
  CCyclicLayer   = 'cyclic';
  CNumericMark   = '#';
  CLayersName    = 'layers';
  CFlag          = '--max-rows';
  CSectionNames: array[0..5] of string = ('freshness', 'counts', 'layers', 'fanin', 'entrypoints', 'forms');
  CEntrySql =
    'SELECT *, COUNT(*) OVER () AS total FROM (' +
    'SELECT 1 AS ord, ''program'' AS kind, f.path AS name, '''' AS path FROM files f ' +
    '  WHERE f.id IN (SELECT file_id FROM unit_uses WHERE section = ''program'') ' +
    'UNION ALL ' +
    'SELECT 2, s.kind, s.qualified_name, f.path FROM symbols s JOIN files f ON f.id = s.file_id ' +
    '  WHERE s.kind IN (''initialization'', ''finalization'') ' +
    'UNION ALL ' +
    'SELECT 3, ''dfm_event'', sf.dfm_event, f.path FROM symbol_facts sf JOIN symbols s ON s.id = sf.symbol_id ' +
    '  JOIN files f ON f.id = s.file_id WHERE sf.dfm_event IS NOT NULL' +
    ') ORDER BY ord, name, path LIMIT :lim';

type
  TRow = TArray<string>;

  /// <summary>One section: column names (a leading '#' marks a numeric column),
  /// the shown rows and the true total.</summary>
  TSection = class
  strict private
    FColumns: TArray<string>;
    FRows   : TList<TRow>;
    FTotal  : Integer;
    FCap    : Integer;
  public
    constructor Create(const AColumns: TArray<string>; ACap: Integer);
    destructor Destroy; override;
    property Columns: TArray<string> read FColumns;
    property Rows   : TList<TRow>    read FRows   ;
    property Total  : Integer        read FTotal write FTotal;
    property Cap    : Integer        read FCap   ;
  end;

  TBuilder = function(AQ: TFDQuery; ACap: Integer): TSection;

constructor TSection.Create(const AColumns: TArray<string>; ACap: Integer);
begin
  inherited Create;
  FColumns:= AColumns;
  FCap    := ACap;
  FRows   := TList<TRow>.Create;
end;

destructor TSection.Destroy;
begin
  FRows.Free;
  inherited Destroy;
end;

/// <summary>Reports a section cap: text prints the line, JSON gets the keys.</summary>
/// <remarks>Local twin of the CLI-wide helper gaps/xj-1 adds; same shape so the
/// merge replaces this body with a call. Prints nothing when nothing was cut.</remarks>
procedure ReportSectionCap(AShown, ATotal, ACap: Integer; const AFlag: string; AJson: TJSONObject);
var
  Omitted: Integer;
begin
  Omitted:= ATotal - AShown;
  if Omitted < 0 then Omitted:= 0;
  if AJson <> nil then
  begin
    AJson.AddPair('total'  , TJSONNumber.Create(ATotal));
    AJson.AddPair('cap'    , TJSONNumber.Create(ACap));
    AJson.AddPair('omitted', TJSONNumber.Create(Omitted));
  end
  else if Omitted > 0 then
    Writeln(Format('-- %d omitted by cap %d; rerun with %s %d', [Omitted, ACap, AFlag, ACap + Omitted]));
end;

/// <summary>Runs ASql on AQ (binding :lim to ALimit when the SQL has it), calls
/// AOnRow for every row and closes the dataset again, also on an exception.</summary>
procedure ReadRows(AQ: TFDQuery; const ASql: string; ALimit: Integer; const AOnRow: TProc);
begin
  AQ.Close;
  AQ.Sql.Text:= ASql;
  if AQ.Params.FindParam('lim') <> nil then AQ.ParamByName('lim').AsInteger:= ALimit;
  AQ.Open;
  try
    while not AQ.Eof do
    begin
      AOnRow();
      AQ.Next;
    end;
  finally
    AQ.Close;
  end;
end;

function ScalarInt(AQ: TFDQuery; const ASql: string): Integer;
var
  N: Integer;
begin
  N:= 0;
  ReadRows(AQ, ASql, 0, procedure begin N:= AQ.Fields[0].AsInteger; end);
  Result:= N;
end;

function BaseName(const APath: string): string;
begin
  Result:= ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll]));
end;

function UnitStem(const APath: string): string;
begin
  Result:= ChangeFileExt(BaseName(APath), '');
end;

function BuildFreshness(AQ: TFDQuery; ACap: Integer): TSection;
const
  CUnixKey = 'indexed_at_unix';
var
  Sect: TSection;
  Unix: Int64;
begin
  Sect:= TSection.Create(['key', 'value'], ACap);
  Result:= Sect;
  ReadRows(AQ, 'SELECT key, value FROM schema_meta WHERE key IN (''project_tag'', ''scan_type'', ''schema_version'', ''indexed_at_unix'') ORDER BY key DESC', 0,
    procedure
    begin
      if AQ.Fields[0].AsString = CUnixKey then
      begin
        Unix:= StrToInt64Def(AQ.Fields[1].AsString, 0);
        if Unix > 0 then
          Sect.Rows.Add(TRow.Create('indexed_at', FormatDateTime('yyyy-mm-dd hh:nn', UnixToDateTime(Unix, False)) + ' UTC'));
      end
      else
        Sect.Rows.Add(TRow.Create(AQ.Fields[0].AsString, AQ.Fields[1].AsString));
    end);
  Sect.Rows.Add(TRow.Create('files'  , IntToStr(ScalarInt(AQ, 'SELECT COUNT(*) FROM files'))));
  Sect.Rows.Add(TRow.Create('symbols', IntToStr(ScalarInt(AQ, 'SELECT COUNT(*) FROM symbols'))));
  Sect.Total:= Sect.Rows.Count;
end;

function BuildCounts(AQ: TFDQuery; ACap: Integer): TSection;
var
  Sect: TSection;
begin
  Sect:= TSection.Create(['kind', CNumericMark + 'count'], ACap);
  Result:= Sect;
  Sect.Total:= ScalarInt(AQ, 'SELECT COUNT(DISTINCT kind) FROM symbols');
  ReadRows(AQ, 'SELECT kind, COUNT(*) AS n FROM symbols GROUP BY kind ORDER BY n DESC, kind LIMIT :lim', ACap,
    procedure begin Sect.Rows.Add(TRow.Create(AQ.Fields[0].AsString, AQ.Fields[1].AsString)); end);
end;

/// <summary>Layers the unit graph: layer 0 = units that use no other project
/// unit; layer n = units whose project dependencies all sit in layers below n.
/// What never clears (a cycle and everything above it) is the final `cyclic` row.</summary>
function BuildLayers(AQ: TFDQuery; ACap: Integer): TSection;
var
  Sect     : TSection;
  Names    : TDictionary<Int64, string>;
  Deps     : TDictionary<Int64, TList<Int64>>;
  Remaining: TList<Int64>;
  Layer    : TList<Int64>;
  Labels   : TStringList;
  Members  : TObjectList<TStringList>;
  Id, Dep  : Int64;
  List     : TList<Int64>;
  Ready    : Boolean;
  LayerNo  : Integer;
  i        : Integer;

  procedure AddRow(const ALabel: string; AIds: TList<Int64>);
  var
    Sorted: TStringList;
    N     : Integer;
  begin
    Sorted:= TStringList.Create;
    Sorted.Sorted:= True;
    Sorted.Duplicates:= dupIgnore;
    for N:= 0 to AIds.Count - 1 do Sorted.Add(Names[AIds[N]]);
    Labels.Add(ALabel);
    Members.Add(Sorted);
  end;

begin
  Sect  := TSection.Create(['layer', CNumericMark + 'count', 'units'], ACap);
  Result:= Sect;
  Names    := TDictionary<Int64, string>.Create;
  Deps     := TDictionary<Int64, TList<Int64>>.Create;
  Remaining:= TList<Int64>.Create;
  Layer    := TList<Int64>.Create;
  Labels   := TStringList.Create;
  Members  := TObjectList<TStringList>.Create;
  try
    ReadRows(AQ, 'SELECT id, path FROM files WHERE lower(path) LIKE ''%.pas'' OR lower(path) LIKE ''%.dpr'' OR lower(path) LIKE ''%.dpk''', 0,
      procedure
      begin
        Id:= AQ.Fields[0].AsLargeInt;
        Names.Add(Id, UnitStem(AQ.Fields[1].AsString));
        Deps.Add(Id, TList<Int64>.Create);
        Remaining.Add(Id);
      end);
    ReadRows(AQ, 'SELECT DISTINCT file_id, target_file_id FROM unit_uses WHERE target_file_id IS NOT NULL AND file_id <> target_file_id', 0,
      procedure
      begin
        if Deps.TryGetValue(AQ.Fields[0].AsLargeInt, List) and Names.ContainsKey(AQ.Fields[1].AsLargeInt) then
          List.Add(AQ.Fields[1].AsLargeInt);
      end);

    LayerNo:= 0;
    while Remaining.Count > 0 do
    begin
      Layer.Clear;
      for Id in Remaining do
      begin
        Ready:= True;
        for Dep in Deps[Id] do
          if Remaining.Contains(Dep) then
          begin
            Ready:= False;
            Break;
          end;
        if Ready then Layer.Add(Id);
      end;
      if Layer.Count = 0 then Break;
      for Id in Layer do Remaining.Remove(Id);
      AddRow(IntToStr(LayerNo), Layer);
      Inc(LayerNo);
    end;
    if Remaining.Count > 0 then AddRow(CCyclicLayer, Remaining);

    Sect.Total:= Labels.Count;
    for i:= 0 to Min(Labels.Count, ACap) - 1 do
      Sect.Rows.Add(TRow.Create(Labels[i], IntToStr(Members[i].Count), Members[i].CommaText));
  finally
    for List in Deps.Values do List.Free;
    Members.Free;
    Labels.Free;
    Layer.Free;
    Remaining.Free;
    Deps.Free;
    Names.Free;
  end;
end;

function BuildFanin(AQ: TFDQuery; ACap: Integer): TSection;
var
  Sect: TSection;
begin
  Sect:= TSection.Create([CNumericMark + 'fanin', 'name', 'kind', 'qualified_name'], ACap);
  Result:= Sect;
  Sect.Total:= ScalarInt(AQ, 'SELECT COUNT(DISTINCT name_text) FROM refs');
  { the same aggregation as `top --by fanin`: refs grouped by name, one sample symbol per name }
  ReadRows(AQ,
    'WITH ref_counts AS (SELECT name_text, COUNT(*) AS fanin FROM refs GROUP BY name_text ORDER BY fanin DESC LIMIT :lim) ' +
    'SELECT rc.fanin AS fanin, rc.name_text AS name, (SELECT kind FROM symbols WHERE name = rc.name_text LIMIT 1) AS kind, ' +
    '(SELECT qualified_name FROM symbols WHERE name = rc.name_text ORDER BY id LIMIT 1) AS sample_qname ' +
    'FROM ref_counts rc ORDER BY rc.fanin DESC, rc.name_text', ACap,
    procedure
    begin
      Sect.Rows.Add(TRow.Create(AQ.FieldByName('fanin').AsString, AQ.FieldByName('name').AsString,
        AQ.FieldByName('kind').AsString, AQ.FieldByName('sample_qname').AsString));
    end);
end;

function BuildEntrypoints(AQ: TFDQuery; ACap: Integer): TSection;
var
  Sect: TSection;
begin
  Sect:= TSection.Create(['kind', 'name', 'file'], ACap);
  Result:= Sect;
  ReadRows(AQ, CEntrySql, ACap,
    procedure
    var
      Kind, Name, Path: string;
    begin
      Sect.Total:= AQ.FieldByName('total').AsInteger;
      Kind:= AQ.FieldByName('kind').AsString;
      Name:= AQ.FieldByName('name').AsString;
      Path:= AQ.FieldByName('path').AsString;
      if Kind = 'program' then
      begin
        Name:= UnitStem(Name);
        Path:= '';
      end
      else
        Path:= BaseName(Path);
      Sect.Rows.Add(TRow.Create(Kind, Name, Path));
    end);
end;

function BuildForms(AQ: TFDQuery; ACap: Integer): TSection;
var
  Sect: TSection;
begin
  Sect:= TSection.Create(['name', 'file'], ACap);
  Result:= Sect;
  Sect.Total:= ScalarInt(AQ, 'SELECT COUNT(*) FROM symbols WHERE kind = ''form''');
  ReadRows(AQ, 'SELECT s.name, f.path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''form'' ORDER BY s.name, f.path LIMIT :lim', ACap,
    procedure begin Sect.Rows.Add(TRow.Create(AQ.Fields[0].AsString, BaseName(AQ.Fields[1].AsString))); end);
end;

function ColumnName(const AColumn: string): string;
begin
  Result:= if AColumn.StartsWith(CNumericMark) then Copy(AColumn, 2, MaxInt) else AColumn;
end;

/// <summary>The unit names of a layers row, split back out of the comma text.</summary>
function LayerNames(const AText: string): TArray<string>;
begin
  Result:= AText.Split([',']);
end;

procedure EmitText(const AName: string; ASection: TSection);
var
  Row  : TRow;
  Parts: TStringList;
  Names: TArray<string>;
  i    : Integer;
begin
  Writeln(Format('== %s: %d ==', [AName, ASection.Total]));
  Parts:= TStringList.Create;
  try
    Parts.Delimiter:= ' ';
    Parts.StrictDelimiter:= True;
    for Row in ASection.Rows do
    begin
      Parts.Clear;
      for i:= 0 to High(Row) do
        if (AName = CLayersName) and (i = High(Row)) then
        begin
          Names:= LayerNames(Row[i]);
          Parts.Add(string.Join(' ', Copy(Names, 0, CNamesPerLayer)));
          if Length(Names) > CNamesPerLayer then Parts.Add(Format('(+%d more)', [Length(Names) - CNamesPerLayer]));
        end
        else
          Parts.Add(Row[i]);
      Writeln(TrimRight('  ' + string.Join('  ', Parts.ToStringArray)));
    end;
  finally
    Parts.Free;
  end;
  ReportSectionCap(ASection.Rows.Count, ASection.Total, ASection.Cap, CFlag, nil);
end;

function SectionToJson(const AName: string; ASection: TSection): TJSONObject;
var
  Arr  : TJSONArray;
  Obj  : TJSONObject;
  Row  : TRow;
  Names: TArray<string>;
  Units: TJSONArray;
  Nm   : string;
  Shown: Integer;
  i    : Integer;
begin
  Result:= TJSONObject.Create;
  ReportSectionCap(ASection.Rows.Count, ASection.Total, ASection.Cap, CFlag, Result);
  Arr:= TJSONArray.Create;
  for Row in ASection.Rows do
  begin
    Obj:= TJSONObject.Create;
    for i:= 0 to High(Row) do
      if (AName = CLayersName) and (i = High(Row)) then
      begin
        Names:= LayerNames(Row[i]);
        Shown:= Min(Length(Names), CNamesPerLayer);
        Units:= TJSONArray.Create;
        for Nm in Copy(Names, 0, Shown) do Units.Add(Nm);
        Obj.AddPair('units', Units);
        Obj.AddPair('more', TJSONNumber.Create(Length(Names) - Shown));
      end
      else if ASection.Columns[i].StartsWith(CNumericMark) then
        Obj.AddPair(ColumnName(ASection.Columns[i]), TJSONNumber.Create(StrToInt64Def(Row[i], 0)))
      else
        Obj.AddPair(ColumnName(ASection.Columns[i]), Row[i]);
    Arr.AddElement(Obj);
  end;
  Result.AddPair('rows', Arr);
end;

function RunOverview(const ADbPath: string; AMaxRows: Integer; AJson: Boolean): Integer;
const
  CBuilders: array[0..5] of TBuilder = (BuildFreshness, BuildCounts, BuildLayers, BuildFanin, BuildEntrypoints, BuildForms);
var
  Conn    : TFDConnection;
  Q       : TFDQuery;
  Sections: TObjectList<TSection>;
  Cap, i  : Integer;
  Root    : TJSONObject;
begin
  if ADbPath = '' then
  begin
    Writeln('ERROR: overview requires --db');
    Exit(2);
  end;
  if not TFile.Exists(ADbPath) then
  begin
    Writeln('ERROR: database not found: ', ADbPath);
    Exit(2);
  end;
  Cap:= if AMaxRows > 0 then AMaxRows else OVERVIEW_DEFAULT_MAX_ROWS;

  Sections:= TObjectList<TSection>.Create;
  Conn    := TFDConnection.Create(nil);
  Q       := TFDQuery.Create(nil);
  try
    ConnectReadOnly(Conn, ADbPath);
    Q.Connection:= Conn;
    for i:= Low(CBuilders) to High(CBuilders) do Sections.Add(CBuilders[i](Q, Cap));
    if AJson then
    begin
      Root:= TJSONObject.Create;
      try
        for i:= 0 to Sections.Count - 1 do Root.AddPair(CSectionNames[i], SectionToJson(CSectionNames[i], Sections[i]));
        Writeln(Root.Format(2));
      finally
        Root.Free;
      end;
    end
    else
      for i:= 0 to Sections.Count - 1 do EmitText(CSectionNames[i], Sections[i]);
  finally
    Q.Free;
    Conn.Free;
    Sections.Free;
  end;
  Result:= 0;
end;

end.
