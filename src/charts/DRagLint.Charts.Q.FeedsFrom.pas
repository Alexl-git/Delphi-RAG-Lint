unit DRagLint.Charts.Q.FeedsFrom;

(* The `feeds-from` question in-process: a port of charts\src\Emit-FeedsFrom.ps1 (spec s11;
  the PS output is the reference, P3). Which database TABLE.COLUMN a data-aware CONTROL
  shows, drawn hop by hop, every hop graded:

    control --DataSource--> TDataSource --DataSet--> memtable --owner--> view model
            --literal--> TABLE --exists--> TABLE.COLUMN

  Every hop comes from TChainWalker (DRagLint.Charts.Chain, the port of Get-DataSourceChain),
  the one walk consumers' column form and lands-where also use. Past a DANGLING designer
  datasource the owner's code re-point is followed (Resolve-RePointTable). A chain that
  cannot be followed ends in a grey "chain stops here" node; it never guesses a table. The
  focus box prints the index-wide coverage per datasource AND per control
  (Get-FieldBindingChains).

  The PS -SourceOverride test hook is not ported: New-DiagramArtifact never passes it. The
  PS local functions New-Row, Get-GradeTag, Add-Hop, Get-RoutineShort, Add-TableHop and
  Add-RePointHops are private routines of TFeedsFromChart below; the script's numbered
  sections are its Select / Read / Follow / Count / Draw methods.

  PS traps closed: `-eq`, `-ne`, `-in` and `switch` are case-insensitive; Sort-Object is not
  stable (TPsSort); [Math]::Round(x, 1) rounds half to even, and "$pct" prints a whole double
  without a fraction while ConvertTo-Json writes it with '.0' (the int 0 of an empty index
  stays 0); a $null ResolvedTable is JSON null; `-replace '^Self\.'` is case-insensitive;
  String.Equals(OrdinalIgnoreCase) folds case invariantly. *)

interface

const
  /// <summary>The registered question id.</summary>
  FEEDS_FROM_ID = 'feeds-from';

implementation

uses
  System.SysUtils, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Source, DRagLint.Charts.Sql, DRagLint.Charts.Columns, DRagLint.Charts.Chain,
  DRagLint.Charts.Tools, DRagLint.Charts.PsSort;

const
  CTL_BORDER = '#7C3AED';
  CTL_FILL = '#F3EEFF';
  CTL_HDR = '#7C3AED';
  DS_BORDER = '#0F766E';
  DS_FILL = '#E2F1EF';
  DS_HDR = '#0F766E';
  SET_BORDER = '#3B5BDB';
  SET_FILL = '#EDF2FF';
  SET_HDR = '#3B5BDB';
  TYPE_BORDER = '#475569';
  TYPE_FILL = '#F1F5F9';
  TYPE_HDR = '#475569';
  DB_BORDER = '#BE185D';
  DB_FILL = '#FDF2F8';
  DB_HDR = '#BE185D';
  CODE_BORDER = '#C2410C';
  CODE_FILL = '#FFF4E6';
  CODE_HDR = '#C2410C';
  WARN_BORDER = '#B45309';
  WARN_FILL = '#FEF3C7';
  WARN_HDR = '#B45309';
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
  DASHED_STYLE = 'rounded,filled,dashed';
  G_CERTAIN = 'certain';
  G_INFERRED = 'inferred';
  G_BY_NAME = 'by name';
  G_DANGLING = 'dangling';
  G_STOP = 'stop';
  K_DFM = 'dfm';
  FIELD_NAME_PROP = 'FieldName';
  NO_DS = 'no-ds';
  DFM_DATASET = 'dfm-dataset';
  STALE = 'stale';
  STOP_TITLE = 'chain stops here';
  COLUMN_OUTCOME = 'column';
  NOT_COLUMN_OUTCOME = 'not-column';
  { [Math]::Round(x, 1): one decimal }
  PCT_SCALE = 10;
  PERCENT = 100.0;
  SELECTION_RX = '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$';
  { a selection of more than <Form>.<Control> is a full qualified name }
  FORM_CONTROL_SEGMENTS = 2;
  { nearest first: the control itself, its parent, its grandparent (Get-ControlDataSourceSql) }
  RANK_OWN = 0;
  RANK_PARENT = 1;
  RANK_GRANDPARENT = 2;
  { Emit-FeedsFrom's $RP_ORDER: the index-wide split of the controls under a dangling datasource }
  RP_ORDER: array[0..7] of string = ('table', 'no-table', 'stops', 'walk-limit', 'multi-rhs', 'no-site', 'stale', '');

type
  TChainNode = record
    Nid, Grade, Title: string;
  end;

  { the selected control (the PS $C) }
  TControl = record
    Id, Fid, Line, Pid: Integer;
    QName, CType, Dfm, PName: string;
  end;

  { one DataSource property naming the datasource (a PS $own row; $dsProp is the nearest) }
  TDsProp = record
    Present: Boolean;
    Rank, Sid, Line: Integer;
    Prop, Owner, OSig: string;
  end;

  TLookup = record
    Prop, Ds: string;
    Line: Integer;
  end;

  { the index-wide coverage (the PS $stat, $oc, $rpc) }
  TStats = record
    Ds, DsDfm, DsCode, DsOne, DsByCol, DsMany, DsNone, DsOther: Integer;
    CtlTotal, CtlTable, DanglingAll: Integer;
    Pct, PctCol: Double;
  end;

  { One feeds-from chart being drawn: the PS script-scope state ($sb, $nodeId, $anchored,
    $chainNodes, $stop, $stopRows, $tableCol, $columnState, $rtNote) and its local functions.
    Owns both indexes, their readers, the SQL catalogue and the walker. }
  TFeedsFromChart = class  // dl:ok god-class@cdfc, high-response@cdfc -- REVIEWED 2026-10-14: the class IS Emit-FeedsFrom.ps1 (one script, one chart): its fields are the script-scope state the PS local functions share, its methods one per script section and local function; splitting it would break the line-for-line port the parity harness checks
  private
    FIndex      : TChartsIndex;
    FReader     : TSourceReader;
    FSqlDb      : string;
    FSqlIndex   : TChartsIndex;
    FSqlReader  : TSourceReader;
    FCatalog    : TSqlCatalog;
    FWalker     : TChainWalker;
    FSb         : TStringBuilder;
    FOutcome    : TDictionary<string, Integer>;
    FRpc        : TDictionary<string, Integer>;
    FCap        : Integer;
    FNodeId     : Integer;
    FAnchored   : Integer;
    FNodes      : TArray<TChainNode>;
    FSel        : string;
    FCtlName    : string;
    FCtl        : TControl;
    FHasField   : Boolean;
    FFieldProp  : string;
    FFieldCol   : string;
    FFieldLine  : Integer;
    FDsText     : string;
    FDsProp     : TDsProp;
    FLookups    : TArray<TLookup>;
    FPas        : string;
    FUnitName   : string;
    FOwner      : string;
    FHasChain   : Boolean;
    FChain      : TDataSourceChain;
    FRePoint    : TArray<TRePointSite>;
    FRebound    : TArray<TRePointSite>;
    FHasRpr     : Boolean;
    FRpr        : TRePointTable;
    FStats      : TStats;
    FCtlNid     : string;
    FStop       : string;
    FStopRows   : TArray<TDotRow>;
    FTableCol   : string;
    FColumnState: string;
    FRtNote     : string;
    function NewRow(const pCaption, pFile: string; pLine: Integer; const pTip, pNote: string): TDotRow;
    function AddHop(const pTitle, pGrade: string; const pRows: TArray<TDotRow>; const pBorder, pFill, pHdr: string;
      pSide: Boolean = False): string;
    function RoutineShort(const pRoutine, pFile: string): string;
    procedure AddTableHop(const pTable, pFile: string; pLine: Integer; const pTip, pNote, pCandNote: string);
    procedure AddRePointHops(const pRp: TRePointTable);
    function Outcome(const pKey: string): Integer;
    function RePointCount(const pKey: string): Integer;
    procedure SelectControl(const pTarget: string);
    procedure ReadBinding;
    procedure FollowChain;
    procedure CountCoverage;
    procedure DrawControl;
    procedure DrawCode;
    procedure DrawDataSourceHop(const pHop: TChainHop);
    procedure DrawDataSetHop(const pHop: TChainHop; pLast: Boolean);
    procedure DrawTableHop(const pHop: TChainHop);
    procedure DrawChain;
    procedure DrawStopAndEdges;
    procedure DrawFocus;
    function ResultFields: TArray<TMetaField>;
  public
    constructor Create(const pArgs: TQuestionArgs);
    destructor Destroy; override;
    function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
  end;

function GradeTag(const pGrade: string): string;
begin
  Result:= '[' + pGrade + ']';
end;

function IsDashedGrade(const pGrade: string): Boolean;
begin
  Result:= SameText(pGrade, G_INFERRED) or SameText(pGrade, G_BY_NAME);
end;

{ "$pct" of a [double]: a whole value prints without a fraction }
function PctText(pValue: Double): string;
begin
  Result:= FloatToStr(pValue, TFormatSettings.Invariant);
end;

{ [Math]::Round(pValue, 1): scale, round half to even, unscale }
function RoundOneDecimal(pValue: Double): Double;
begin
  Result:= Round(pValue * PCT_SCALE) / PCT_SCALE;
end;

{ the look of a Get-RePointChain hop ($RP_HOP) }
procedure RePointHopLook(const pHop: string; out pTitle, pBorder, pFill, pHdr: string);
begin
  if SameText(pHop, 're-point') then
  begin
    pTitle:= 're-pointed in code';
    pBorder:= CODE_BORDER;
    pFill:= CODE_FILL;
    pHdr:= CODE_HDR;
  end
  else if SameText(pHop, 'member') or SameText(pHop, 'accessor') then
  begin
    pTitle:= if SameText(pHop, 'member') then 'view-model member' else 'read accessor';
    pBorder:= TYPE_BORDER;
    pFill:= TYPE_FILL;
    pHdr:= TYPE_HDR;
  end
  else if SameText(pHop, 'field') then
  begin
    pTitle:= 'datasource field';
    pBorder:= DS_BORDER;
    pFill:= DS_FILL;
    pHdr:= DS_HDR;
  end
  else if SameText(pHop, 'dataset') then
  begin
    pTitle:= 'dataset';
    pBorder:= SET_BORDER;
    pFill:= SET_FILL;
    pHdr:= SET_HDR;
  end
  else
    raise EChartsQuestion.CreateFmt('feeds-from: re-point hop ''%s'' has no drawing', [pHop]);
end;

constructor TFeedsFromChart.Create(const pArgs: TQuestionArgs);
var
  Note: string;
begin
  inherited Create;
  FIndex:= TChartsIndex.Create(pArgs.GuardedDb);
  FReader:= TSourceReader.Create(FIndex);
  FSqlDb:= CloneDb(pArgs.SqlDbPath, pArgs.CloneRoot, Note);
  FSqlIndex:= TChartsIndex.Create(FSqlDb);
  FSqlReader:= TSourceReader.Create(FSqlIndex);
  FCatalog:= TSqlCatalog.Create(FSqlIndex, FSqlReader);
  FWalker:= TChainWalker.Create(FIndex, FReader, FCatalog, FCatalog.TableSet);
  FSb:= TStringBuilder.Create;
  FOutcome:= TDictionary<string, Integer>.Create;
  FRpc:= TDictionary<string, Integer>.Create;
  FCap:= pArgs.Cap;
  FColumnState:= 'n/a';
end;

destructor TFeedsFromChart.Destroy;
begin
  FRpc.Free;
  FOutcome.Free;
  FSb.Free;
  FWalker.Free;
  FCatalog.Free;
  FSqlReader.Free;
  FSqlIndex.Free;
  FReader.Free;
  FIndex.Free;
  inherited Destroy;
end;

function TFeedsFromChart.Outcome(const pKey: string): Integer;
begin
  if not FOutcome.TryGetValue(pKey, Result) then
    Result:= 0;
end;

function TFeedsFromChart.RePointCount(const pKey: string): Integer;
begin
  if not FRpc.TryGetValue(pKey, Result) then
    Result:= 0;
end;

{ New-Row: every anchored row counts toward Expected, shown or not }
function TFeedsFromChart.NewRow(const pCaption, pFile: string; pLine: Integer; const pTip, pNote: string): TDotRow;
begin
  Inc(FAnchored);
  Result:= TDotRow.Anchored(pCaption, pLine, RowHref(pFile, pLine), pTip, pNote);
end;

{ Add-Hop: one graded cluster; a chain hop (not -Side) joins the chain's edge list }
function TFeedsFromChart.AddHop(const pTitle, pGrade: string; const pRows: TArray<TDotRow>; const pBorder, pFill,
  pHdr: string; pSide: Boolean): string;
begin
  Inc(FNodeId);
  Result:= 'n' + IntToStr(FNodeId);
  var Style:= TClusterStyle.Make(pBorder, pFill, pHdr);
  Style.RowInk:= ROW_INK;
  Style.LineInk:= LINE_INK;
  Style.FontSans:= FONT_SANS;
  if IsDashedGrade(pGrade) then
    Style.Style:= DASHED_STYLE;
  AddRowCluster(FSb, 'cluster_hop_' + IntToStr(FNodeId), Result, pTitle, GradeTag(pGrade), pRows, Style);
  if not pSide then
  begin
    var N:= Default(TChainNode);
    N.Nid:= Result;
    N.Grade:= pGrade;
    N.Title:= pTitle;
    FNodes:= FNodes + [N];
  end;
end;

{ Get-RoutineShort }
function TFeedsFromChart.RoutineShort(const pRoutine, pFile: string): string;
begin
  Result:= ShortName(pRoutine, UnitNameOf(pFile));
  if Result = '' then
    Result:= '(unit level)';
end;

{ Add-TableHop: the TABLE hop and its column row -- the chain's table or the one beside a re-pointed dataset }
procedure TFeedsFromChart.AddTableHop(const pTable, pFile: string; pLine: Integer; const pTip, pNote, pCandNote: string);
var
  Title: string;
begin
  var Rows: TArray<TDotRow>:= [NewRow('table ' + pTable, pFile, pLine, pTip, pNote)];
  if pCandNote <> '' then
    Rows:= Rows + [NoteRow(pCandNote)];
  if FHasField then
  begin
    FTableCol:= pTable + '.' + FFieldCol.ToUpperInvariant;
    { the SHARED column state: the label says what was read -- "not extracted as a column by
      the SQL index", never "not in the scripts" }
    var Cs:= SqlColumnState(FCatalog, FCatalog.TableSet, pTable, FFieldCol, TServerSqlHit.None, '');
    FColumnState:= Cs.State;
    if Cs.IsColumn then
      Rows:= Rows + [NewRow(ColumnHopLabel(Cs), Cs.Path, Cs.Line, Format('%s -- %s:%d', [FTableCol, FileNameOf(Cs.Path), Cs.Line]),
        Cs.Caption)]
    else if SameText(FColumnState, STALE) then
      Rows:= Rows + [NoteRow(Cs.Column + ': ' + Cs.Caption)]
    else
      Rows:= Rows + [NoteRow(Cs.Column + ' is ' + Cs.Caption + ' -- computed, UI-only, or the scripts lag the schema')];
    if FRtNote <> '' then
      Rows:= Rows + [NoteRow(FRtNote)];
    if SameText(FColumnState, 'no') then
      Title:= pTable + ' (column not extracted)'
    else if SameText(FColumnState, STALE) then
      Title:= FTableCol + ' [stale source]'
    else
      Title:= FTableCol;
  end
  else
  begin
    Rows:= Rows + [NoteRow('the control binds no column itself')];
    Title:= pTable;
  end;
  AddHop(Title, G_INFERRED, Rows, DB_BORDER, DB_FILL, DB_HDR);
end;

{ Add-RePointHops: the hops Get-RePointChain walked, each graded as the round-trip grades it }
procedure TFeedsFromChart.AddRePointHops(const pRp: TRePointTable);
var
  Title, Border, Fill, Hdr: string;
begin
  for var Rh in pRp.Hops do
  begin
    RePointHopLook(Rh.Hop, Title, Border, Fill, Hdr);
    var Notes: TArray<string>:= [];
    if Rh.Routine <> '' then
      Notes:= Notes + ['in ' + Rh.Routine];
    if Rh.Reason <> '' then
      Notes:= Notes + [Rh.Reason];
    var Row:= NewRow(Rh.Caption, Rh.Path, Rh.Line, Format('%s -- %s:%d', [Rh.Caption, FileNameOf(Rh.Path), Rh.Line]),
      string.Join('; ', Notes));
    AddHop(Title, Rh.Grade, [Row], Border, Fill, Hdr);
  end;
  if pRp.DataSet.Present then
  begin
    var D:= pRp.DataSet;
    AddHop('dataset field', G_CERTAIN, [NewRow(D.Name + ' : ' + D.TypeName, D.Path, D.Line,
      Format('%s : %s -- %s:%d', [D.Name, D.TypeName, FileNameOf(D.Path), D.Line]), 'the dataset the re-pointed datasource is given')],
      SET_BORDER, SET_FILL, SET_HDR);
  end;
end;

{ ---- 1. the selection: <Form>.<Control> or the component's full qualified name ---- }
procedure TFeedsFromChart.SelectControl(const pTarget: string);
begin
  FSel:= PsTrim(pTarget);
  if not TRegEx.IsMatch(FSel, SELECTION_RX, [roIgnoreCase]) then
    raise EChartsQuestion.CreateFmt('feeds-from: -Control takes <Form>.<Control> (e.g. frmCausFail.colREASON), got ''%s''', [pTarget]);
  var Segs:= FSel.Split(['.']);
  var FormName:= Segs[0];
  FCtlName:= Segs[High(Segs)];
  var Fids: TArray<string>:= [];
  var FormFiles: TArray<string>:= [];
  var Forms:= FIndex.Query(
    'SELECT s.file_id AS fid, f.path AS path FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +  // dl:ok sql-injection-concat@3492 -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
    Format(' WHERE s.kind = ''form'' AND UPPER(s.name) = UPPER(''%s'')', [TChartsIndex.SqlText(FormName)]));
  try
    for var R in Forms do
    begin
      Fids:= Fids + [IntToStr(R.I('fid'))];
      FormFiles:= FormFiles + [FileNameOf(R.S('path'))];
    end;
  finally
    Forms.Free;
  end;
  if Length(Fids) = 0 then
    raise EChartsQuestion.CreateFmt('feeds-from: no form or data module named %s in this index', [FormName]);
  var Found: TArray<TControl>:= [];
  var Cands:= FIndex.Query(
    'SELECT c.id AS id, c.name AS name, c.qualified_name AS q, c.signature AS sig, c.parent_id AS pid,' + sLineBreak +
    '       c.start_line AS line, c.file_id AS fid, f.path AS path, p.name AS pname, p.signature AS psig' + sLineBreak +
    '  FROM symbols c JOIN files f ON f.id = c.file_id LEFT JOIN symbols p ON p.id = c.parent_id' + sLineBreak +
    Format(' WHERE c.kind = ''component'' AND c.file_id IN (%s)', [string.Join(',', Fids)]) + sLineBreak +
    Format('   AND UPPER(c.name) = UPPER(''%s'')', [TChartsIndex.SqlText(FCtlName)]));
  try
    for var R in Cands do
    begin
      if (Length(Segs) > FORM_CONTROL_SEGMENTS) and (R.S('q').ToUpperInvariant <> FSel.ToUpperInvariant) then
        Continue;
      var C:= Default(TControl);
      C.Id:= R.I('id');
      C.QName:= R.S('q');
      C.CType:= R.S('sig');
      C.Pid:= R.I('pid');
      C.Line:= R.I('line');
      C.Fid:= R.I('fid');
      C.Dfm:= R.S('path');
      C.PName:= R.S('pname');
      Found:= Found + [C];
    end;
  finally
    Cands.Free;
  end;
  if Length(Found) = 0 then
    raise EChartsQuestion.CreateFmt('feeds-from: no component named %s on %s (%s)', [FCtlName, FormName, string.Join(', ', FormFiles)]);
  if Length(Found) > 1 then
  begin
    var Names: TArray<string>:= [];
    for var C in Found do
      Names:= Names + [C.QName];
    raise EChartsQuestion.CreateFmt('feeds-from: %s names %d components (%s) -- pass the full qualified name',
      [FSel, Length(Found), string.Join(', ', Names)]);
  end;
  FCtl:= Found[0];
  if SameText(FCtl.CType, 'TDataSource') then
    raise EChartsQuestion.CreateFmt('feeds-from selects a data-aware CONTROL, not a datasource -- ask consumers/shown-where. ' +
      '%s is a TDataSource; pick a control bound to it (a grid column, an edit) to see its chain.', [FCtl.QName]);
end;

{ the control's own field binding, its datasource by the SHARED rule, its lookup lists }
procedure TFeedsFromChart.ReadBinding;
begin
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
      begin
        if not HasOther then
        begin
          FHasField:= True;
          FFieldProp:= R.S('prop');
          FFieldCol:= R.S('col');
          FFieldLine:= R.I('line');
        end;
        HasOther:= True;
      end;
  finally
    Fb.Free;
  end;
  if HasFieldName and not HasOther then
    raise EChartsQuestion.CreateFmt('feeds-from: %s is a persistent FIELD (%s) of the dataset %s, not a control -- ' +
      'its FieldName names the dataset column it maps. Ask shown-where for the controls that display that column.',
      [FCtl.QName, FCtl.CType, FCtl.PName]);

  var DsRow:= FIndex.Query(Format('SELECT %s AS ds' + sLineBreak + '  FROM symbols c JOIN (SELECT %d AS file_id) sl' + sLineBreak +
    ' WHERE c.id = %d', [ControlDataSourceSql('sl', 'c'), FCtl.Fid, FCtl.Id]));
  try
    FDsText:= if DsRow.Count > 0 then DsRow[0].S('ds') else '';
  finally
    DsRow.Free;
  end;
  if FDsText <> '' then
  begin
    var Own: TArray<TDsProp>:= [];
    var Rows:= FIndex.Query(
      'SELECT d.symbol_id AS sid, d.owner_name AS prop, d.start_line AS line, s.name AS owner, s.signature AS osig' + sLineBreak +
      '  FROM string_literals d JOIN symbols s ON s.id = d.symbol_id' + sLineBreak +
      Format(' WHERE d.kind = ''dfm-prop'' AND d.file_id = %d AND d.owner_name IN (%s)',
        [FCtl.Fid, TChartsIndex.SqlInList(['DataSource', 'DataBinding.DataSource', 'DataController.DataSource'])]) + sLineBreak +
      Format('   AND d.text = ''%s''', [TChartsIndex.SqlText(FDsText)]) + sLineBreak +
      Format('   AND d.symbol_id IN (%d, %d, (SELECT g.parent_id FROM symbols g WHERE g.id = %d))', [FCtl.Id, FCtl.Pid, FCtl.Pid]) + sLineBreak +
      ' ORDER BY d.start_line');
    try
      for var R in Rows do
      begin
        var P:= Default(TDsProp);
        P.Present:= True;
        P.Sid:= R.I('sid');
        P.Prop:= R.S('prop');
        P.Line:= R.I('line');
        P.Owner:= R.S('owner');
        P.OSig:= R.S('osig');
        P.Rank:= if P.Sid = FCtl.Id then RANK_OWN else if (FCtl.Pid <> 0) and (P.Sid = FCtl.Pid) then RANK_PARENT else RANK_GRANDPARENT;
        Own:= Own + [P];
      end;
    finally
      Rows.Free;
    end;
    { nearest first, the same order Get-ControlDataSourceSql applies }
    TPsSort<TDsProp>.Sort(Own,
      function(const pA, pB: TDsProp): Integer
      begin
        Result:= if pA.Rank <> pB.Rank then pA.Rank - pB.Rank else pA.Line - pB.Line;
      end);
    if Length(Own) > 0 then
      FDsProp:= Own[0];
  end;
  var Look:= FIndex.Query('SELECT owner_name AS prop, text AS ds, start_line AS line FROM string_literals' + sLineBreak +  // dl:ok sql-injection-concat@28b8 -- REVIEWED 2026-10-14: read-only index query; every text value goes through SqlText / SqlInList, every other value is an Integer
    Format(' WHERE kind = ''dfm-prop'' AND symbol_id = %d AND owner_name IN (''ListSource'',''Properties.ListSource'')', [FCtl.Id]));
  try
    for var R in Look do
    begin
      var L:= Default(TLookup);
      L.Prop:= R.S('prop');
      L.Ds:= R.S('ds');
      L.Line:= R.I('line');
      FLookups:= FLookups + [L];
    end;
  finally
    Look.Free;
  end;
  if not FHasField and (FDsText = '') then
    raise EChartsQuestion.CreateFmt('feeds-from: %s (%s) is not data-aware: no DataSource and no field binding on it or its two ' +
      'enclosing components in the DFM. feeds-from selects a data-aware CONTROL.', [FCtl.QName, FCtl.CType]);

  var PasGuess:= ChangeFileExt(FCtl.Dfm, '.pas').ToUpperInvariant;
  FPas:= '';
  for var K in FReader.IndexedFileShas.Keys do
    if K.ToUpperInvariant = PasGuess then
    begin
      FPas:= K;
      Break;
    end;
  FUnitName:= UnitNameOf(FPas);
end;

{ ---- 2. the chain, the code re-points, and the re-point past a dangling datasource ---- }
procedure TFeedsFromChart.FollowChain;
begin
  FHasChain:= FDsText <> '';
  if FHasChain then
    FChain:= FWalker.DataSourceChain(FCtl.Dfm, FDsText);
  FOwner:= if FDsProp.Present then FDsProp.Owner else FCtlName;
  if FHasChain then
  begin
    for var R in FChain.RePointedAt do
      if SameText(R.Control, FOwner) then
        FRePoint:= FRePoint + [R];
  end
  else if FPas <> '' then
    FRePoint:= FWalker.RePointSites(FPas, [FCtlName], ['DataSource']);
  if (FPas <> '') and FHasField then
    FRebound:= FWalker.RePointSites(FPas, [FCtlName], ['DataField', FIELD_NAME_PROP]);
  FHasRpr:= FHasChain and SameText(FChain.Grade, G_DANGLING);
  if FHasRpr then
    FRpr:= FWalker.ResolveRePointTable(FChain, FOwner);
end;

{ ---- 3. index-wide coverage, per datasource AND per control (R9) ---- }
procedure TFeedsFromChart.CountCoverage;
begin
  var Ix:= FWalker.FieldBindingChains;
  for var C in Ix.DataSources do
  begin
    Inc(FStats.Ds);
    var InDfm:= False;
    var InCode:= False;
    for var S in C.DataSetSites do
      if SameText(S.Kind, K_DFM) then
        InDfm:= True
      else
        InCode:= True;
    if InDfm then
      Inc(FStats.DsDfm);
    if InCode then
      Inc(FStats.DsCode);
    if SameText(C.Grade, 'one-table') then
      Inc(FStats.DsOne)
    else if SameText(C.Grade, 'by-columns') then
      Inc(FStats.DsByCol)
    else if SameText(C.Grade, 'many') then
      Inc(FStats.DsMany)
    else if SameText(C.Grade, 'none') then
      Inc(FStats.DsNone);
  end;
  FStats.DsOther:= FStats.Ds - FStats.DsOne - FStats.DsByCol - FStats.DsMany - FStats.DsNone;
  for var B in Ix.Bindings do
  begin
    FOutcome.AddOrSetValue(B.Outcome, Outcome(B.Outcome) + 1);
    if B.Dangling then
    begin
      { the controls under a DANGLING designer datasource, by where their code re-point went }
      Inc(FStats.DanglingAll);
      FRpc.AddOrSetValue(B.RePoint, RePointCount(B.RePoint) + 1);
    end;
  end;
  FStats.CtlTotal:= Length(Ix.Bindings);
  FStats.CtlTable:= Outcome(COLUMN_OUTCOME) + Outcome(NOT_COLUMN_OUTCOME);
  if FStats.CtlTotal > 0 then
  begin
    FStats.Pct:= RoundOneDecimal(PERCENT * FStats.CtlTable / FStats.CtlTotal);
    FStats.PctCol:= RoundOneDecimal(PERCENT * Outcome(COLUMN_OUTCOME) / FStats.CtlTotal);
  end;
end;

{ -- hop: the control -- }
procedure TFeedsFromChart.DrawControl;
begin
  var Rows: TArray<TDotRow>:= [];
  var DfmName:= FileNameOf(FCtl.Dfm);
  if FHasField then
    Rows:= Rows + [NewRow(FCtlName + ' : ' + FCtl.CType, FCtl.Dfm, FFieldLine,
      Format('%s.%s = ''%s'' -- %s:%d', [FCtl.QName, FFieldProp, FFieldCol, DfmName, FFieldLine]), FFieldProp + ' = ' + FFieldCol)]
  else
    Rows:= Rows + [NewRow(FCtlName + ' : ' + FCtl.CType, FCtl.Dfm, FCtl.Line, Format('%s -- %s:%d', [FCtl.QName, DfmName, FCtl.Line]),
      'binds no column itself')];
  if FDsProp.Present then
  begin
    var Via:= if FDsProp.Sid <> FCtl.Id then FDsProp.Owner + '.' + FDsProp.Prop else FDsProp.Prop;
    Rows:= Rows + [NewRow(Via + ' = ' + FDsText, FCtl.Dfm, FDsProp.Line, Format('%s = %s -- %s:%d', [Via, FDsText, DfmName, FDsProp.Line]),
      if FDsProp.Sid <> FCtl.Id then 'via its ' + FDsProp.OSig else 'DFM')];
  end
  else
    Rows:= Rows + [NoteRow('no DataSource on it or its two enclosing components in the DFM')];
  for var L in FLookups do
    Rows:= Rows + [NewRow(L.Prop + ' = ' + L.Ds, FCtl.Dfm, L.Line, Format('%s = %s -- a lookup list, a different binding', [L.Prop, L.Ds]),
      'lookup list; not followed')];
  FCtlNid:= AddHop('control', G_CERTAIN, Rows, CTL_BORDER, CTL_FILL, CTL_HDR);
end;

{ -- side: re-pointed / re-bound in code -- }
procedure TFeedsFromChart.DrawCode;
begin
  var Rows: TArray<TDotRow>:= [];
  for var R in FRePoint + FRebound do
  begin
    var What:= if SameText(R.Prop, 'DataSource') or SameText(R.Prop, 'ListSource') or (R.Prop = '') then 're-pointed' else 're-bound';
    var Rtn:= RoutineShort(R.Routine, R.Path);
    { the receiver as written (`edtF1.DataBinding`), or the recovered control plus the
      receiver_text the index kept (`.DataBinding`) when the control was lost (P29) }
    var Recv: string;
    if R.Receiver = '' then
      Recv:= R.Control
    else if R.Receiver.StartsWith('.') then
      Recv:= R.Control + R.Receiver
    else
      Recv:= TRegEx.Replace(R.Receiver, '^Self\.', '', [roIgnoreCase]);
    var Lbl:= Format('[%s at %s:%d] %s.%s := %s', [What, Rtn, R.Line, Recv, R.Prop, if R.Stale then '?' else R.Rhs]);
    var Notes: TArray<string>:= [];
    if SameText(R.ControlFrom, 'source') then
      Notes:= Notes + [Format('control read from source (receiver_text ''%s'')', [R.Receiver])];
    if R.Stale then
      Notes:= Notes + ['[stale source]'];
    Rows:= Rows + [NewRow(Lbl, R.Path, R.Line, Format('%s.%s assigned in %s -- %s:%d', [R.Control, R.Prop, R.Routine, FileNameOf(R.Path), R.Line]),
      string.Join('; ', Notes))];
  end;
  if Length(Rows) = 0 then
    Exit;
  var Shown:= Copy(Rows, 0, FCap);
  if Length(Rows) > FCap then
    Shown:= Shown + [NoteRow(DisclosureText(Length(Rows) - FCap, 0, 'sites'))];
  var CodeNid:= AddHop('in code (' + FUnitName + ')', G_CERTAIN, Shown, CODE_BORDER, CODE_FILL, CODE_HDR, True);
  FSb.AppendLine(Format('  %s -> %s [color="%s", label=" runtime ", fontcolor="%s"];', [FCtlNid, CodeNid, CODE_BORDER, CODE_BORDER]));
  if (Length(FRebound) > 0) and FHasField then
    FRtNote:= Format('%s is re-assigned in code -- the DFM column %s may not be the one shown at runtime', [FFieldProp, FFieldCol]);
end;

procedure TFeedsFromChart.DrawDataSourceHop(const pHop: TChainHop);
begin
  if SameText(pHop.Grade, G_DANGLING) then
  begin
    AddHop('datasource', G_DANGLING, [NewRow(FChain.DsName, FCtl.Dfm, pHop.Line,
      Format('%s -- %s:%d', [FChain.DsName, FileNameOf(FCtl.Dfm), pHop.Line]),
      Format('the DFM names %s, which is not in this project', [FChain.Module]))], WARN_BORDER, WARN_FILL, WARN_HDR);
    { Task 2: the runtime re-point is FOLLOWED (Resolve-RePointTable); what it cannot do is a named stop }
    var DangWhy:= Format('the designer datasource %s is dangling (module %s is declared nowhere in this index)', [FChain.DsName, FChain.Module]);
    if not FHasRpr then
    begin
      FStop:= DangWhy;
      Exit;
    end;
    AddRePointHops(FRpr);
    var Status:= FRpr.Status;
    if SameText(Status, 'table') then
      AddTableHop(FRpr.Table, FRpr.DataSet.Path, FRpr.TableLine,
        Format('''%s'' literal -- %s:%d', [FRpr.Table, FileNameOf(FRpr.DataSet.Path), FRpr.TableLine]),
        Format('[inferred] the table literal beside %s on %d line(s)', [FRpr.DataSet.Name, FRpr.TableLines]), '')
    else if SameText(Status, STALE) then
      FStop:= '[stale source] ' + FRpr.Stop
    else if SameText(Status, 'no-site') or SameText(Status, 'multi-rhs') then
      FStop:= DangWhy + '; ' + FRpr.Stop
    else if SameText(Status, 'walk-limit') then
      FStop:= 'the code re-point was followed to a shape this walk does not follow: ' + FRpr.Stop
    else
      FStop:= 'the code re-point was followed and stops: ' + FRpr.Stop;
  end
  else if SameText(pHop.Grade, G_CERTAIN) or SameText(pHop.Grade, G_BY_NAME) then
    AddHop('datasource', pHop.Grade, [NewRow(pHop.Caption, pHop.Path, pHop.Line,
      Format('%s -- %s:%d', [pHop.Caption, FileNameOf(pHop.Path), pHop.Line]),
      if pHop.Reason <> '' then pHop.Reason else 'declared in ' + FileNameOf(pHop.Path))], DS_BORDER, DS_FILL, DS_HDR)
  else
    FStop:= pHop.Reason;
end;

procedure TFeedsFromChart.DrawDataSetHop(const pHop: TChainHop; pLast: Boolean);
begin
  var Tip:= Format('%s -- %s:%d', [pHop.Caption, FileNameOf(pHop.Path), pHop.Line]);
  if (SameText(pHop.Grade, G_CERTAIN) or SameText(pHop.Grade, G_INFERRED)) and not (pLast and SameText(FChain.Grade, DFM_DATASET)) then
  begin
    var Rtn:= '';
    for var S in FChain.DataSetSites do
      if (S.Line = pHop.Line) and SameText(S.Kind, 'assign') then
      begin
        Rtn:= RoutineShort(S.Routine, pHop.Path);
        Break;
      end;
    var N:= 0;
    for var S in FChain.DataSetSites do
      if not SameText(S.Kind, K_DFM) then
        Inc(N);
    var Note:= Format('in %s; %d DataSet site(s) in the unit scanned', [Rtn, N]) + (if pHop.Reason <> '' then '; ' + pHop.Reason else '');
    AddHop('dataset', pHop.Grade, [NewRow(pHop.Caption, pHop.Path, pHop.Line, Tip, Note)], SET_BORDER, SET_FILL, SET_HDR);
  end
  else if SameText(FChain.Grade, DFM_DATASET) then
  begin
    AddHop('dataset', G_CERTAIN, [NewRow(pHop.Caption, pHop.Path, pHop.Line, Tip, 'set in the DFM')], SET_BORDER, SET_FILL, SET_HDR);
    FStop:= pHop.Reason;
  end
  else
    FStop:= pHop.Reason;
end;

procedure TFeedsFromChart.DrawTableHop(const pHop: TChainHop);
begin
  var Ch:= FChain;
  if Ch.ResolvedTable <> '' then
  begin
    var CandNote:= if SameText(Ch.Grade, 'by-columns') then Format('candidates: %s -- tie broken by %d bound column(s)',
      [string.Join(', ', Ch.CandidateTables), Length(Ch.BoundColumns)]) else '';
    AddTableHop(Ch.ResolvedTable, pHop.Path, pHop.Line, Format('''%s'' literal -- %s:%d', [Ch.ResolvedTable, FileNameOf(pHop.Path), pHop.Line]),
      '[inferred] ' + pHop.Reason, CandNote);
    Exit;
  end;
  FStop:= pHop.Reason;
  var Many:= SameText(Ch.Grade, 'many');
  var ByMatch:= (Length(Ch.BoundColumns) > 0) and (Length(Ch.ColumnMatch) > 1);
  var List:= if Many and ByMatch then Ch.ColumnMatch else Ch.CandidateTables;
  if Many then
  begin
    if ByMatch then
      FStop:= Format('ambiguous: %s share every bound column (%s)', [string.Join(', ', Ch.ColumnMatch), string.Join(', ', Ch.BoundColumns)])
    else if Length(Ch.BoundColumns) > 0 then
      FStop:= Format('ambiguous: %d candidate tables and none holds all %d bound column(s)', [Length(Ch.CandidateTables), Length(Ch.BoundColumns)])
    else
      FStop:= Format('ambiguous: %d candidate tables and no column is bound through %s to tell them apart', [Length(Ch.CandidateTables), Ch.DsName]);
  end
  else if Ch.RhsType.Present and SameText(Ch.RhsType.TypeKind, 'interface') then
    FStop:= '[unresolved -- interface-typed view-model] ' + pHop.Reason;
  for var K:= 0 to Length(List) - 1 do
  begin
    if K >= FCap then
      Break;
    var T:= List[K];
    var LineText:= '';
    var Line:= 0;
    for var J:= 0 to Length(Ch.CandidateTables) - 1 do
      if SameText(Ch.CandidateTables[J], T) then
      begin
        Line:= Ch.CandidateLines[J];
        LineText:= IntToStr(Line);
        Break;
      end;
    FStopRows:= FStopRows + [NewRow('candidate ' + T, Ch.RhsType.TypePath, Line,
      Format('''%s'' literal -- %s:%s', [T, FileNameOf(Ch.RhsType.TypePath), LineText]), '')];
  end;
  if Length(List) > FCap then
    FStopRows:= FStopRows + [NoteRow(DisclosureText(Length(List) - FCap, 0, 'candidates'))];
end;

{ -- hops from the chain -- }
procedure TFeedsFromChart.DrawChain;
begin
  if not FHasChain then
    FStop:= 'no datasource in the DFM for ' + FCtlName +
      (if Length(FRePoint) > 0 then '; it is re-pointed in code (see the code rows) -- that right-hand side is not followed' else '')
  else
    for var I:= 0 to High(FChain.Hops) do
    begin
      var H:= FChain.Hops[I];
      if SameText(H.Hop, 'datasource') then
        DrawDataSourceHop(H)
      else if SameText(H.Hop, 'dataset') then
        DrawDataSetHop(H, I = High(FChain.Hops))
      else if SameText(H.Hop, 'rhs-type') then
      begin
        if SameText(H.Grade, G_BY_NAME) then
        begin
          var Kind:= FChain.RhsType.TypeKind;
          AddHop('view model', G_BY_NAME, [NewRow(H.Caption, H.Path, H.Line,
            Format('%s (%s) -- %s:%d', [H.Caption, Kind, FileNameOf(H.Path), H.Line]),
            Format('%s found by its name; %s is a %s', [Kind, FChain.RhsType.Root, FChain.RhsType.RootKind]))], TYPE_BORDER, TYPE_FILL, TYPE_HDR);
        end
        else
          FStop:= H.Reason;
      end
      else if SameText(H.Hop, 'table') then
        DrawTableHop(H);
    end;
  if FHasChain and SameText(FChain.Grade, 'stale source') then
    FStop:= '[stale source] ' + FChain.StopReason;
end;

{ the stop node, then the chain edges: dashed into anything that is not certain }
procedure TFeedsFromChart.DrawStopAndEdges;
begin
  if FStop <> '' then
  begin
    Inc(FNodeId);
    var N:= Default(TChainNode);
    N.Nid:= 'n' + IntToStr(FNodeId);
    N.Grade:= G_STOP;
    N.Title:= STOP_TITLE;
    var Style:= TClusterStyle.Make(STOP_BORDER, STOP_FILL, STOP_HDR);
    Style.RowInk:= ROW_INK;
    Style.LineInk:= LINE_INK;
    Style.FontSans:= FONT_SANS;
    AddRowCluster(FSb, 'cluster_stop_' + IntToStr(FNodeId), N.Nid, STOP_TITLE, '', [NoteRow(FStop)] + FStopRows, Style);
    FNodes:= FNodes + [N];
  end;
  for var I:= 1 to High(FNodes) do
  begin
    var G:= FNodes[I].Grade;
    var St:= if SameText(G, G_STOP) then 'dotted' else if IsDashedGrade(G) then 'dashed' else 'solid';
    var Lb:= if IsDashedGrade(G) or SameText(G, G_DANGLING) then Format(' label=" [%s] ",', [G]) else '';
    FSb.AppendLine(Format('  %s -> %s [style=%s,%s color="%s"];', [FNodes[I - 1].Nid, FNodes[I].Nid, St, Lb, LINE_INK]));
  end;
end;

{ -- the focus box: what was asked, and how much of the index this chain can see -- }
procedure TFeedsFromChart.DrawFocus;
begin
  Inc(FNodeId);
  var FNid:= 'n' + IntToStr(FNodeId);
  var S:= FStats;
  var FTbl:= TStringBuilder.Create;
  try
    FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> feeds-from &#183; %s </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS, XmlText(FSel)]));
    AddDisclosureRow(FTbl, Format('datasources in this index: %d (%d wired in DFM, %d in code); one table: %d; many: %d (%d broken by bound columns); ' +
      'none: %d; chain stops before the table: %d -- measured per datasource',
      [S.Ds, S.DsDfm, S.DsCode, S.DsOne, S.DsMany + S.DsByCol, S.DsByCol, S.DsNone, S.DsOther]), LINE_INK);
    AddDisclosureRow(FTbl, Format('per control: %d field-bound controls; %d resolve to one table (%s%%), %d of them to a column ' +
      'that table has (%s%%); ambiguous %d, chain stops %d, dangling %d, no datasource in the DFM %d',
      [S.CtlTotal, S.CtlTable, PctText(S.Pct), Outcome(COLUMN_OUTCOME), PctText(S.PctCol), Outcome('ambiguous'), Outcome('stops'),
       Outcome(G_DANGLING), Outcome(NO_DS)]) +
      (if Outcome(STALE) > 0 then Format(', stale source %d', [Outcome(STALE)]) else '') +
      (if Outcome(NOT_COLUMN_OUTCOME) > 0 then Format('; %d resolve to a table the SQL index extracts no such column from (not quoted there either)',
        [Outcome(NOT_COLUMN_OUTCOME)]) else ''), LINE_INK);
    AddDisclosureRow(FTbl, Format('past a dangling designer datasource the code re-point is followed (as the round-trip trace follows it): of %d such controls ' +
      '%d reach a table, %d the dataset only, %d stop on the way, %d reach a shape the walk does not follow, ' +
      '%d are re-pointed with several different right-hand sides (not chosen), %d have no re-point site',
      [S.DanglingAll, RePointCount('table'), RePointCount('no-table'), RePointCount('stops'), RePointCount('walk-limit'),
       RePointCount('multi-rhs'), RePointCount('no-site')]) +
      (if RePointCount(STALE) > 0 then Format(', %d cross a stale file', [RePointCount(STALE)]) else '') +
      (if RePointCount('') > 0 then Format(', %d have no owner in the DFM', [RePointCount('')]) else ''), LINE_INK);
    AddDisclosureRow(FTbl, 'the table comes from string literals in the view model''s unit (past a re-point: the literal beside the dataset) -- ' +
      '[inferred], dashed; never a fact', LINE_INK);
    AddDisclosureRow(FTbl, Format('the column is checked against the SQL scripts (%d tables) -- a script-derived schema, not the live one',
      [Length(FCatalog.TableSet.Names)]), LINE_INK);
    if FHasChain and FChain.Dangling then
      AddDisclosureRow(FTbl, Format('the DFM names %s, which is not in this project', [FChain.Module]), LINE_INK);
    FTbl.Append('</TABLE>');
    FSb.AppendLine(Format('  subgraph cluster_focus_%d {', [FNodeId]));
    FSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
    FSb.AppendLine('    label=""; margin=10;');
    FSb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
    FSb.AppendLine('  }');
    FSb.AppendLine(Format('  %s -> %s [style=invis];', [FNid, FCtlNid]));
    FSb.AppendLine('}');
  finally
    FTbl.Free;
  end;
end;

{ the emitter object's properties, in the PS order (the file paths excluded) }
function TFeedsFromChart.ResultFields: TArray<TMetaField>;
begin
  var Grades: TArray<string>:= [];
  for var N in FNodes do
    Grades:= Grades + [N.Grade];
  var Resolved:= if FHasRpr and (FRpr.Table <> '') then FRpr.Table else if FHasChain then FChain.ResolvedTable else '';
  var ResolvedField:= TMetaField.Str('ResolvedTable', Resolved);
  if Resolved = '' then
    ResolvedField.Json:= 'null';
  var Agg: TArray<string>:= [];
  for var K in RP_ORDER do
    Agg:= Agg + [IntToStr(RePointCount(K))];
  var At: TArray<string>:= [];
  for var R in FRePoint do
    At:= At + [Format('%s:%d', [FileNameOf(R.Path), R.Line])];
  var S:= FStats;
  var Pct: TMetaField;
  if S.CtlTotal > 0 then
    Pct:= TMetaField.Real('CoveragePct', S.Pct)
  else
    Pct:= TMetaField.Int('CoveragePct', 0);
  var FieldCol, Grade, RePoint, Candidates: string;
  var AfterTie, Bound: Integer;
  FieldCol:= '';
  if FHasField then
    FieldCol:= FFieldCol;
  Grade:= NO_DS;
  Candidates:= '';
  AfterTie:= 0;
  Bound:= 0;
  if FHasChain then
  begin
    Grade:= FChain.Grade;
    Candidates:= string.Join(',', FChain.CandidateTables);
    AfterTie:= Length(FChain.ColumnMatch);
    Bound:= Length(FChain.BoundColumns);
  end;
  RePoint:= '';
  if FHasRpr then
    RePoint:= FRpr.Status;
  var Dangling:= FHasChain and FChain.Dangling;
  Result:= [TMetaField.Str('Control', FCtl.QName), TMetaField.Str('ControlType', FCtl.CType),
    TMetaField.Str('Field', FieldCol), TMetaField.Str('DataSource', FDsText),
    TMetaField.Str('DsOwner', FOwner), TMetaField.Str('Grade', Grade),
    TMetaField.Str('HopGrades', string.Join('>', Grades)), TMetaField.Int('ChainRows', Length(FNodes)), ResolvedField,
    TMetaField.Str('RePoint', RePoint), TMetaField.Int('CtlDanglingAll', S.DanglingAll),
    TMetaField.Str('CtlRePoint', string.Join('/', Agg)), TMetaField.Str('TableColumn', FTableCol),
    TMetaField.Str('ColumnExists', FColumnState), TMetaField.Str('Candidates', Candidates),
    TMetaField.Int('AfterTieBreak', AfterTie), TMetaField.Int('BoundColumns', Bound),
    TMetaField.Str('StopReason', FStop), TMetaField.Bool('Dangling', Dangling)];
  Result:= Result + [TMetaField.Int('RePointed', Length(FRePoint)), TMetaField.Str('RePointedAt', string.Join(',', At)),
    TMetaField.Int('Rebound', Length(FRebound)), TMetaField.Int('IndexDs', S.Ds), TMetaField.Int('IndexDsDfm', S.DsDfm),
    TMetaField.Int('IndexDsCode', S.DsCode), TMetaField.Int('IndexDsOne', S.DsOne), TMetaField.Int('IndexDsMany', S.DsMany + S.DsByCol),
    TMetaField.Int('IndexDsByCol', S.DsByCol), TMetaField.Int('IndexDsNone', S.DsNone), TMetaField.Int('IndexDsOther', S.DsOther)];
  Result:= Result + [TMetaField.Int('Controls', S.CtlTotal), TMetaField.Int('CtlTable', S.CtlTable), TMetaField.Int('CtlColumn', Outcome(COLUMN_OUTCOME)),
    TMetaField.Int('CtlNotColumn', Outcome(NOT_COLUMN_OUTCOME)), TMetaField.Int('CtlAmbiguous', Outcome('ambiguous')),
    TMetaField.Int('CtlStops', Outcome('stops')), TMetaField.Int('CtlDangling', Outcome(G_DANGLING)), TMetaField.Int('CtlNoDs', Outcome(NO_DS)),
    TMetaField.Int('CtlStale', Outcome(STALE)), Pct];
end;

function TFeedsFromChart.Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  { ---- 0. the SQL index role (a swapped pair must not render) ---- }
  if Length(FCatalog.TableSet.Names) = 0 then
    raise EChartsQuestion.CreateFmt('feeds-from: %s is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone, ' +
      '-DbPath the Delphi project clone', [FSqlDb]);
  SelectControl(pArgs.Target);
  ReadBinding;
  FollowChain;
  CountCoverage;

  { ---- 4. dot ---- }
  FSb.AppendLine('digraph feedsfrom {');
  FSb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;');
  FSb.AppendLine('  nodesep=0.5; ranksep=0.55; splines=spline;');
  FSb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
  FSb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
  FSb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
  FSb.AppendLine('');
  DrawControl;
  DrawCode;
  DrawChain;
  DrawStopAndEdges;
  DrawFocus;

  var Msgs: TArray<string>;
  Result.Layout:= DotLayout(pArgs.Dot, FSb.ToString, pOutDir, 'feedsfrom_' + TRegEx.Replace(FSel, '[^A-Za-z0-9]', '_'), Msgs);
  Result.LeftCount:= Length(FNodes);
  Result.RightCount:= FStats.CtlTable;
  Result.ClickTargets:= Result.Layout.Anchors;
  Result.AllClickable:= Result.Layout.Anchors >= FAnchored;
  Result.Fields:= ResultFields + [TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', FAnchored),
    TMetaField.Bool('AllClickable', Result.AllClickable)];
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Chart:= TFeedsFromChart.Create(pArgs);
  try
    Result:= Chart.Emit(pArgs, pOutDir);
  finally
    Chart.Free;
  end;
end;

initialization
  RegisterChartQuestion(FEEDS_FROM_ID, Emit);

end.
