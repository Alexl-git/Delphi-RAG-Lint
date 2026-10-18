unit DRagLint.Charts.Q.RoundTrip;

(* The `round-trip` question in-process: a port of charts\src\Emit-RoundTrip.ps1 (spec s11; the PS output is the
  reference, P3; the trace core is the DRagLint.Charts.Trace units). From ONE selection to its data anchor and then both
  ways through the pipe: WRITE (the dataset's AfterPost handler -> sender -> CROSSES -> server dispatch ->
  handler -> apply -> column -> response) and READ (the routine that fills the dataset with the table literal ->
  CROSSES -> server -> query -> back), then ALSO (every other route the index holds). The answer is the Form A
  document (trace.dlgraph, charts\form-a-grammar-spec.md section 8) and its CHART, drawn from the SAME bytes.

  Three clones, queried SEPARATELY (RT3): -DbPath (CLIENT: the anchor, the client half of both walks, ALSO),
  -ServerDbPath (SERVER: the dispatch and the database facts) and -SqlDbPath (the SQL scripts). The side each
  phase runs on is explicit in the TTraceWalker calls, where the PS rebound $DbPath with Invoke-OnDb. The three
  file counts of the proof (OnDbProof) are the CLIENT and SERVER counts.

  This run's outputs are REMOVED FIRST (RT8, R5 A-R5-STALE), so a refusal (a stale file: AC-14) leaves neither
  an old text nor an old picture behind; the text is written LAST, after the chart (a dot failure still delivers
  the text and sets ChartError, owner answer 3, RT9). The chart is drawn from ReadFormA of the written bytes,
  never from a second walk (RT9): the in-memory model drawn for the A-R5-FROMTEXT gate is a unit test of
  DRagLint.Charts.Trace.Chart, not emitter work.

  NOT PORTED: Write-Host (progress lines and the echoed text), -SourceOverride / -ChartCaps / -BoundaryPattern as
  question arguments (unit-level consts: BOUNDARY_PATTERN and the default caps), Get-CloneDb (GuardedDb /
  CloneDb), Invoke-OnDb (the explicit sides), the ChartManifest / ChartModelDot properties (the meta excludes them).
  A missing -ServerDbPath / -SqlDbPath refuses with New-DiagramArtifact's own message, the layer that checks
  them before the PS emitter is reached.

  PS traps closed: `$A.Items[-1]` is the LAST item of a non-empty list (the entry step always exists);
  `@($wiring | Select-Object -Skip 1)` is every wiring after the first; `$notes` are written AFTER the walk so
  each STOPS has its final number; `[Math]::Min` / `Max` order the two stop numbers; Get-RegenerateCommand
  double-quotes the --target and each index path; `$chartOut` names are deleted when dot fails; `-eq` /
  `-ne` / `-in` are case-insensitive (SameText); `Select-Object -Unique` keeps first-seen order (SkipIds, the
  anchor leaves: case-SENSITIVE) while a hashtable keyed by leaf is case-INSENSITIVE; a STOP is not a refusal
  (AC-13): a control that is not data-bound is a one-step trace. *)

interface

const
  /// <summary>The question id: the key RegisterChartQuestion files the emitter under.</summary>
  ROUND_TRIP_ID = 'round-trip';

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot, DRagLint.Charts.Source,
  DRagLint.Charts.Sql, DRagLint.Charts.Chain, DRagLint.Charts.Tools, DRagLint.Charts.Trace.FormA, DRagLint.Charts.Trace.Shim,
  DRagLint.Charts.Trace.Anchor, // dl:unit DRagLint.Charts.Trace.Anchor accepted -- RT_EVENTS, the write events, travel with the wiring reader and the anchor result this unit already uses
  DRagLint.Charts.Trace.Calc, // dl:unit DRagLint.Charts.Trace.Calc accepted -- CALC_KIND_CALCULATED travels with the calc decision (TCalcInfo) this unit reads
  DRagLint.Charts.Trace.Walk, DRagLint.Charts.Trace.Chart;

const
  { Emit-RoundTrip.ps1:53 -BoundaryPattern, split on '|' into one LIKE per part (RT7) }
  BOUNDARY_PATTERN = 'Pipes.%|uPipe%|uBroadcast%';
  { the tiers line (PS :119) }
  TIERS = 'client -> pipe -> server -> database';
  KIND_STEP = 'step';
  KIND_STOPS = 'stops';
  KIND_CROSSES = 'crosses';
  KIND_FACET = 'facet';
  HEAD_REGENERATE = 'REGENERATE';
  SEC_ANCHOR = 'ANCHOR';
  SEC_DERIVED = 'DERIVED';
  SEC_WRITE = 'WRITE';
  SEC_SERVER = 'SERVER';
  SEC_DATABASE = 'DATABASE';
  SEC_RESPONSE = 'RESPONSE';
  SEC_READ = 'READ';
  SEC_ALSO = 'ALSO';
  ACTOR_CLIENT = 'CLIENT';
  ACTOR_SERVER = 'SERVER';
  ACTOR_DATABASE = 'DATABASE';
  ASK_E3 = 'E3';
  OUT_PREFIX = 'roundtrip_';
  TRACE_EXT = '.dlgraph';
  TRACE_BUNDLE_NAME = 'trace.dlgraph';
  GRAPH_PREFIX = 'graph.';
  CHART_EXTS: array[0..4] of string = ('dot', 'svg', 'png', 'pdf', 'plain');
  UNKNOWN_RSP = 'unknown, no server handler was reached';
  NO_RSP = 'no rsp* constant read in the handler';
  NO_ALSO = 'no other route to this anchor in the index';
  NOTE_FAR_SIDE = 'the far side, from the counterpart index';
  NOTE_RESPONSE_FRAME = 'the response frame';
  NOTE_ROWS_BACK = 'the rows come back';
  NOTE_PROCESS_BOUNDARY = 'process boundary';
  NOTE_OTHER_WIRING = 'another wiring on the same dataset';
  NOTE_OTHER_ROUTE = 'another fill route';
  NOTE_FILL_CALL = 'the fill call carrying the table literal';
  NOTE_HANDLER_NAMED = 'handler named on the wiring line';
  NOTE_FROM_SERVER = 'server index';
  NOTE_FROM_CLIENT = 'client index';
  FACET_FROM = 'FROM';
  FACET_TO = 'TO';
  FACET_WITH = 'WITH';
  FACET_CONTRACT = 'CONTRACT';
  MODE_WRITE = 'write';
  MODE_READ = 'read';
  DIR_WRITE = 'write';
  DIR_READ = 'read';
  NO_ANCHOR = 'index:0';
  UNKNOWN_ANCHOR = 'unknown:0';
  CLIENT_PREFIX_RX = '^CLIENT-';
  SERVER_PREFIX_RX = '^SERVER-';
  { PS :296: every ` @<leaf>.<pas|dfm|dpr|inc|sql>:<line>` the text anchors, IgnoreCase }
  ANCHOR_LEAF_RX = ' @([A-Za-z0-9_$.\-]+\.(?:pas|dfm|dpr|inc|sql)):[1-9]\d*';
  { PS :360: the field a DERIVED row's REGENERATE traces -- its --target, double-quoted (a qualified name holds no ") }
  TARGET_RX = '--target "([^"]*)"';
  SQL_FILES_COUNT = 'SELECT COUNT(*) AS n FROM files';
  SQL_ANCHOR_PATHS = 'SELECT DISTINCT path AS p FROM files WHERE %s';
  TITLE_REACHES = 'How %s reaches %s and goes back';
  TITLE_CANNOT = 'Why %s cannot be traced';
  TITLE_CALCULATED = 'Why %s cannot be traced -- it is calculated';
  TITLE_BOTH_STOP = 'Where the trace between %s and %s stops (steps %d and %d)';
  TITLE_WRITE_STOPS = 'How %s reaches %s (the way back stops at step %d)';
  TITLE_READ_STOPS = 'How %s goes back to %s (the way there stops at step %d)';

type
  { one Add-NotWalked record: the section, the STOPS that ended the direction, and the direction's name }
  TNotWalked = record
    Sec : TTraceSection;
    Stop: TTraceItem;
    Dir : string;
  end;

  { one run of the question: the three clones, the trace core, the model being built }
  TRoundTripRun = class  // dl:ok god-class@38c2, high-response@38c2 -- REVIEWED 2026-10-18: the state of ONE run of Emit-RoundTrip.ps1 (its script-level variables) and one method per numbered PS section; splitting it would pass that state between classes and lose the line-for-line map to the script
  private
    FArgs      : TQuestionArgs;
    FOutDir    : string;
    FTarget    : string;
    FBase      : string;
    FDepth     : Integer;
    FCliDb     : string;
    FSrvDb     : string;
    FSqlDb     : string;
    FCli       : TChartsIndex;
    FSrv       : TChartsIndex;
    FSql       : TChartsIndex;
    FCliReader : TSourceReader;
    FSrvReader : TSourceReader;
    FSqlReader : TSourceReader;
    FCatalog   : TSqlCatalog;
    FChain     : TChainWalker;
    FResolver  : TTraceAnchorResolver;
    FCalcReader: TCalcFactsReader;
    FWalker    : TTraceWalker;
    FCliName   : string;
    FSrvName   : string;
    FName      : string;
    FTrace     : TTrace;
    FAnchor    : TAnchorResult;
    FCtx       : TTraceContext;
    FSecA      : TTraceSection;
    FSecDv     : TTraceSection;
    FSecW      : TTraceSection;
    FSecS      : TTraceSection;
    FSecD      : TTraceSection;
    FSecR      : TTraceSection;
    FSecRd     : TTraceSection;
    FSecAl     : TTraceSection;
    FAlsoRows  : TObjectList<TTraceItem>;
    FNotes     : TList<TNotWalked>;
    FWiring    : TArray<TEventWiring>;
    FWStop     : TTraceItem;
    FRStop     : TTraceItem;
    FWrite     : Integer;
    FRead      : Integer;
    FAlso      : Integer;
    procedure RemoveOutputs;
    procedure CheckSqlIndex;
    function Regenerate(const pFor: string): string;
    function AsOf: string;
    procedure BuildAnchor;
    procedure AddNotWalked(pSec: TTraceSection; pStop: TTraceItem; const pDir: string);
    function ItemNumber(pItem: TTraceItem): Integer;
    function WithText(pSrv: TServerHandling): string;
    function BackStep(pXing: TTraceItem; pSrv: TServerHandling; const pNote: string): TTraceItem;
    procedure PlaceServerItems(pSrv: TServerHandling; pSec: TTraceSection);
    procedure WalkWrite;
    procedure WriteThroughCrossing(pClient: TObjectList<TTraceItem>; pXi: Integer);
    procedure WalkRead(pRoutes: TObjectList<TFillRoute>);
    procedure ReadThroughRoute(pRoute: TFillRoute);
    procedure WalkAlso(pRoutes: TObjectList<TFillRoute>);
    procedure WriteNotesAndTitle;
    function AnchorPathsOf(const pText: string): TDictionary<string, string>;
    procedure RemoveChartFiles;
    function ResultFields(const pChartError: string; pChartNodes, pClickTargets: Integer;
      pAllClickable: Boolean): TArray<TMetaField>;
    function DerivedRows: TArray<string>;
    function DerivedCommands: TArray<string>;
  public
    constructor Create(const pArgs: TQuestionArgs; const pOutDir: string);
    destructor Destroy; override;
    function Emit: TChartResult;
  end;

{ hands the items of a returned list to their new owner: the list forgets them without freeing }
procedure Disown(pList: TObjectList<TTraceItem>); overload;
begin
  pList.OwnsObjects:= False;
  try
    pList.Clear;
  finally
    pList.OwnsObjects:= True;
  end;
end;

{ the first pCount items have a new owner: the list forgets them without freeing and keeps owning the rest (an error
  past this point frees only what the list still holds) }
procedure Disown(pList: TObjectList<TTraceItem>; pCount: Integer); overload;
begin
  pList.OwnsObjects:= False;
  try
    pList.DeleteRange(0, pCount);
  finally
    pList.OwnsObjects:= True;
  end;
end;

procedure Disown(pList: TObjectList<TTraceChild>); overload;
begin
  pList.OwnsObjects:= False;
  try
    pList.Clear;
  finally
    pList.OwnsObjects:= True;
  end;
end;

{ ---- construction ---- }

constructor TRoundTripRun.Create(const pArgs: TQuestionArgs; const pOutDir: string);
var
  Note: string;
begin
  inherited Create;
  FArgs:= pArgs;
  FOutDir:= pOutDir;
  FTarget:= pArgs.Target;
  FDepth:= pArgs.Depth;
  FBase:= OUT_PREFIX + TRegEx.Replace(FTarget, '[^A-Za-z0-9]', '_');
  FCliDb:= pArgs.GuardedDb;
  FSrvDb:= CloneDb(pArgs.ServerDbPath, pArgs.CloneRoot, Note);
  FSqlDb:= CloneDb(pArgs.SqlDbPath, pArgs.CloneRoot, Note);
  FCli:= TChartsIndex.Create(FCliDb);
  FCliReader:= TSourceReader.Create(FCli);
  FSrv:= TChartsIndex.Create(FSrvDb);
  FSrvReader:= TSourceReader.Create(FSrv);
  FSql:= TChartsIndex.Create(FSqlDb);
  FSqlReader:= TSourceReader.Create(FSql);
  FCatalog:= TSqlCatalog.Create(FSql, FSqlReader);
  FChain:= TChainWalker.Create(FCli, FCliReader, FCatalog, FCatalog.TableSet);
  FResolver:= TTraceAnchorResolver.Create(FCli, FCliReader, FChain, FCatalog, FCatalog.TableSet);
  FCalcReader:= TCalcFactsReader.Create(FCli, FCliReader, FResolver, FCatalog, FCatalog.TableSet);
  FWalker:= TTraceWalker.Create(FCli, FSrv, FCliReader, FSrvReader, FCatalog, FCatalog.TableSet);
  FAlsoRows:= TObjectList<TTraceItem>.Create;
  FNotes:= TList<TNotWalked>.Create;
end;

destructor TRoundTripRun.Destroy;
begin
  FNotes.Free;
  FAlsoRows.Free;
  FCtx.Free;
  FAnchor.Free;
  FTrace.Free;
  FWalker.Free;
  FCalcReader.Free;
  FResolver.Free;
  FChain.Free;
  FCatalog.Free;
  FSqlReader.Free;
  FSql.Free;
  FSrvReader.Free;
  FSrv.Free;
  FCliReader.Free;
  FCli.Free;
  inherited Destroy;
end;

{ ---- 0. outputs first, the role check, the header ---- }

{ PS :72-79: this run's own names and the names the bundler gives them in a bundle folder }
procedure TRoundTripRun.RemoveOutputs;
begin
  ForceDirectories(FOutDir);
  var Names: TArray<string>:= [FBase + TRACE_EXT, TRACE_BUNDLE_NAME];
  for var X in CHART_EXTS do
    Names:= Names + [FBase + '.' + X, GRAPH_PREFIX + X];
  for var N in Names do
    System.SysUtils.DeleteFile(TPath.Combine(FOutDir, N));
end;

{ PS :88-89 }
procedure TRoundTripRun.CheckSqlIndex;
begin
  if Length(FCatalog.TableSet.Names) = 0 then
    raise EChartsQuestion.CreateFmt('round-trip: %s is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone', [FSqlDb]);
end;

{ PS :105: the command that traces a target on these three indexes at this depth }
function TRoundTripRun.Regenerate(const pFor: string): string;
begin
  Result:= Format('drag-lint ask round-trip --target "%s" --db "%s" --server-db "%s" --sql-db "%s" --depth %d',
    [pFor, FCliDb, FSrvDb, FSqlDb, FDepth]);
end;

{ PS :93-99: each index's own last-indexed stamp, in the order the INDEX line names them }
function TRoundTripRun.AsOf: string;
begin
  Result:= string.Join('/', [TTraceWalker.IndexStamp(FCli), TTraceWalker.IndexStamp(FSrv), TTraceWalker.IndexStamp(FSql)]);
end;

{ ---- 1. the anchor ---- }

{ PS :108-150: the anchor, the title, the ANCHOR and DERIVED sections, the context, the other sections }
procedure TRoundTripRun.BuildAnchor;
var
  Calc: TCalcFieldItems;
  HasCalc: Boolean;
begin
  try
    FAnchor:= FResolver.ResolveTraceAnchor(FTarget);
    FCalcReader.Apply(FAnchor, FAnchor.FieldName);
  except
    on E: EChartsTrace do
      raise EChartsQuestion.Create(E.Message);
  end;
  if FAnchor.StaleFile <> '' then
    raise EChartsQuestion.CreateFmt('round-trip: %s differs from the indexed copy (sha256) -- refusing to follow the anchor chain through it. ' +
      'Reindex the project, then re-run.', [ExtractFileName(FAnchor.StaleFile)]);
  FName:= if FAnchor.TableColumn <> '' then FAnchor.TableColumn else FTarget;
  var Info:= TCalcInfo(FAnchor.Calc);
  HasCalc:= (Info <> nil) and SameText(Info.Kind, CALC_KIND_CALCULATED);
  Calc:= Default(TCalcFieldItems);
  if HasCalc then
    Calc:= NewCalcFieldItems(Info, function(pTarget: string): string
      begin
        Result:= Regenerate(pTarget);
      end);
  var Title:= if HasCalc then Format(TITLE_CALCULATED, [FTarget]) else if FAnchor.Stop <> '' then Format(TITLE_CANNOT, [FTarget])
    else Format(TITLE_REACHES, [FName, FTarget]);
  FTrace:= NewTrace(FName, Title, FTarget, Format('%s + %s + SQL', [FCliName, FSrvName]), AsOf, Regenerate(FTarget), TIERS);
  FSecA:= AddTraceSection(FTrace, SEC_ANCHOR);
  var StopAnchor:= if (FAnchor.StopAnchor <> '') and not SameText(FAnchor.StopAnchor, UNKNOWN_ANCHOR) then FAnchor.StopAnchor
    else if FAnchor.Items.Count > 0 then FAnchor.Items.Last.Anchor else NO_ANCHOR;
  for var I in FAnchor.Items do
    FSecA.Items.Add(I);
  Disown(FAnchor.Items);
  if HasCalc then
    FSecA.Items.Add(Calc.Stop)
  else if FAnchor.Stop <> '' then
    FSecA.Items.Add(NewTraceStep(KIND_STOPS, TraceStopText(FAnchor.Stop), StopAnchor));
  FSecDv:= nil;
  if HasCalc then
  begin
    FSecDv:= AddTraceSection(FTrace, SEC_DERIVED);
    FSecDv.Note:= TraceNoteText(Calc.Note);
    for var R in Calc.Rows do
      FSecDv.Items.Add(R);
    Disown(Calc.Rows);
    Calc.Rows.Free;
  end;
  FCtx:= TTraceContext.Create;
  FCtx.Table:= FAnchor.Table;
  FCtx.Column:= FAnchor.Column;
  FCtx.TableColumn:= FAnchor.TableColumn;
  FCtx.DataSet:= FAnchor.DataSet;
  FCtx.HasDataSet:= FAnchor.HasDataSet;
  FCtx.Likes:= BoundaryLikes(BOUNDARY_PATTERN);
  FCtx.NearIndex:= FCliName;
  FCtx.FarIndex:= FSrvName;
  FSecW:= AddTraceSection(FTrace, SEC_WRITE);
  FSecS:= AddTraceSection(FTrace, SEC_SERVER);
  FSecD:= AddTraceSection(FTrace, SEC_DATABASE);
  FSecR:= AddTraceSection(FTrace, SEC_RESPONSE);
  FSecRd:= AddTraceSection(FTrace, SEC_READ);
  FSecAl:= AddTraceSection(FTrace, SEC_ALSO);
  if FAnchor.Stop <> '' then
  begin
    var NotWalked:= TraceNoteText(Format('not walked: the trace stopped at [%.2d]', [FSecA.Items.Count]));
    for var S in [FSecW, FSecS, FSecD, FSecR, FSecRd, FSecAl] do
      S.Note:= NotWalked;
  end;
end;

procedure TRoundTripRun.AddNotWalked(pSec: TTraceSection; pStop: TTraceItem; const pDir: string);
begin
  var Rec: TNotWalked;
  Rec.Sec:= pSec;
  Rec.Stop:= pStop;
  Rec.Dir:= pDir;
  FNotes.Add(Rec);
end;

{ PS :162: the number Write-FormA will give an item: its place across the sections }
function TRoundTripRun.ItemNumber(pItem: TTraceItem): Integer;
begin
  Result:= 0;
  for var S in FTrace.Sections do
    for var I in S.Items do
    begin
      Inc(Result);
      if I = pItem then
        Exit;
    end;
  raise EChartsTrace.Create('Get-TraceItemNumber: the item is not in the trace');
end;

{ ---- the shared pieces of the two halves ---- }

{ the WITH facet of a response: what the server handler answers, or why that is unknown (PS :212, :260) }
function TRoundTripRun.WithText(pSrv: TServerHandling): string;
begin
  if not pSrv.Walked then
    Result:= UNKNOWN_RSP
  else if Length(pSrv.Responses) > 0 then
    Result:= string.Join(' or ', pSrv.Responses)
  else
    Result:= NO_RSP;
end;

{ the second CROSSES, at the SAME anchor as the request (ruling P4: one ExecuteCommand call sends and returns) }
function TRoundTripRun.BackStep(pXing: TTraceItem; pSrv: TServerHandling; const pNote: string): TTraceItem;
begin
  Result:= NewTraceStep(KIND_CROSSES, NOTE_PROCESS_BOUNDARY, pXing.Anchor, '', pXing.Routine, pNote);
  Result.Children.Add(NewTraceFacet(FACET_FROM, FSrvName, '', NOTE_FROM_SERVER));
  Result.Children.Add(NewTraceFacet(FACET_TO, FCliName, '', NOTE_FROM_CLIENT));
  Result.Children.Add(NewTraceFacet(FACET_WITH, WithText(pSrv), pXing.Anchor, ''));
end;

{ the server's items into a section, the CONTRACT facet already on the crossing; the server result keeps no item }
procedure TRoundTripRun.PlaceServerItems(pSrv: TServerHandling; pSec: TTraceSection);
begin
  for var I in pSrv.Items do
    pSec.Items.Add(I);
  Disown(pSrv.Items);
end;

{ ---- 2-5. WRITE, SERVER, DATABASE, RESPONSE ---- }

{ PS :169-220 }
procedure TRoundTripRun.WalkWrite;
begin
  var Ds:= FAnchor.DataSet;
  FWiring:= FResolver.EventWiring(Ds);
  if Length(FWiring) = 0 then
  begin
    FWStop:= NewTraceStep(KIND_STOPS, Format('no %s handler is wired on %s in %s', [string.Join('/', RT_EVENTS), Ds.Name, UnitNameOf(Ds.FileName)]),
      TraceAnchorText(Ds.FileName, Ds.Line), '', '', '', ASK_E3);
    FSecW.Items.Add(FWStop);
    for var S in [FSecS, FSecD, FSecR] do
      AddNotWalked(S, FWStop, DIR_WRITE);
    Exit;
  end;
  var W0:= FWiring[0];
  FSecW.Items.Add(NewTraceStep(KIND_STEP, Format('FIRES %s.%s -> %s', [Ds.Name, W0.Event, W0.Handler]), TraceAnchorText(Ds.FileName, W0.Line),
    W0.Grade, W0.Routine, NOTE_HANDLER_NAMED, ASK_E3));
  var Visited:= TDictionary<Integer, Byte>.Create;
  var Client:= TObjectList<TTraceItem>.Create;
  try
    var Sub:= FWalker.WalkRoutine(tsClient, W0.HandlerId, FDepth, Visited, FCtx);
    try
      { the handler runs ON the event -- the routine that wires it (Create) does not call it }
      var Entry:= NewTraceStep(KIND_STEP, 'CALLS ' + W0.HandlerShort, TraceAnchorText(W0.HandlerPath, W0.HandlerImpl), '', '',
        Format('on %s.%s, wired at :%d in %s', [Ds.Name, W0.Event, W0.Line, W0.Routine]));
      for var C in Sub.Conds do
        Entry.Children.Add(C);
      Disown(Sub.Conds);
      Client.Add(Entry);
      for var I in Sub.Items do
        Client.Add(I);
      Disown(Sub.Items);
    finally
      Sub.Free;
    end;
    var Xi:= -1;
    for var K:= 0 to Client.Count - 1 do
      if Client[K].Kind = KIND_CROSSES then
      begin
        Xi:= K;
        Break;
      end;
    if Xi < 0 then
    begin
      for var I in Client do
        FSecW.Items.Add(I);
      var LastAnchor:= Client.Last.Anchor;
      Disown(Client);
      FWStop:= NewTraceStep(KIND_STOPS, Format('%s never reaches a transport call carrying a protocol constant within %d call levels',
        [W0.HandlerShort, FDepth]), LastAnchor, '', W0.HandlerShort, '', '');
      FSecW.Items.Add(FWStop);
      for var S in [FSecS, FSecD, FSecR] do
        AddNotWalked(S, FWStop, DIR_WRITE);
    end
    else
      WriteThroughCrossing(Client, Xi);
  finally
    Client.Free;
    Visited.Free;
  end;
  { the other wirings converge on the same sender: ALSO }
  for var K:= 1 to High(FWiring) do
    FAlsoRows.Add(NewTraceStep(KIND_STEP, Format('FIRES %s.%s -> %s', [Ds.Name, FWiring[K].Event, FWiring[K].Handler]),
      TraceAnchorText(Ds.FileName, FWiring[K].Line), FWiring[K].Grade, FWiring[K].Routine, NOTE_OTHER_WIRING, ASK_E3));
  { one OMITS disclosure per section, whichever routines the walk left them in }
  for var Sec in [FSecW, FSecS, FSecD, FSecR] do
    FWalker.MergeTraceOmits(Sec);
  FWrite:= FSecW.Items.Count + FSecS.Items.Count + FSecD.Items.Count + FSecR.Items.Count;
end;

{ PS :192-214: the client items to the crossing, the server on its own index, the database, the response and the rest }
procedure TRoundTripRun.WriteThroughCrossing(pClient: TObjectList<TTraceItem>; pXi: Integer);
begin
  var Xing:= pClient[pXi];
  for var K:= 0 to pXi do
    FSecW.Items.Add(pClient[K]);
  Disown(pClient, pXi + 1);
  var Srv:= FWalker.ServerHandling(Xing.Command, FCtx, FDepth);
  try
    if Srv.HasContract then
      Xing.Children.Add(NewTraceFacet(FACET_CONTRACT, Srv.ContractText, Srv.ContractAnchor, NOTE_FAR_SIDE));
    PlaceServerItems(Srv, FSecS);
    { only below a server handler that was walked: a list holding just the server's STOPS has no statement to name }
    if Srv.Walked then
    begin
      var Db:= FWalker.DatabaseSteps(FSecS.Items.ToArray, FCtx, MODE_WRITE);
      try
        for var I in Db.Items do
          FSecD.Items.Add(I);
        Disown(Db.Items);
      finally
        Db.Free;
      end;
    end
    else
    begin
      FWStop:= Srv.Stop;
      AddNotWalked(FSecD, Srv.Stop, DIR_WRITE);
    end;
    FSecR.Items.Add(BackStep(Xing, Srv, NOTE_RESPONSE_FRAME));
  finally
    Srv.Free;
  end;
  for var I in pClient do
    FSecR.Items.Add(I);
  Disown(pClient);
end;

{ ---- 6. READ ---- }

{ PS :227-263 }
procedure TRoundTripRun.WalkRead(pRoutes: TObjectList<TFillRoute>);
begin
  var Ds:= FAnchor.DataSet;
  if pRoutes.Count = 0 then
  begin
    FRStop:= NewTraceStep(KIND_STOPS, TraceStopText(Format('no bound call on a line naming ''%s'' beside %s in %s reaches a transport call ' +
      'carrying a protocol constant within %d call levels', [FAnchor.Table, Ds.Name, UnitNameOf(Ds.FileName), FDepth])),
      TraceAnchorText(Ds.FileName, Ds.Line));
    FSecRd.Items.Add(FRStop);
  end
  else
    ReadThroughRoute(pRoutes[0]);
end;

{ PS :232-263: the first fill route, its callee to the send, the server, and back }
procedure TRoundTripRun.ReadThroughRoute(pRoute: TFillRoute);
begin
  var Ds:= FAnchor.DataSet;
  FSecRd.Items.Add(NewTraceStep(KIND_STEP, Format('LOADS %s VIA %s%s', [Ds.Name, pRoute.TargetShort, pRoute.Lits]),
    TraceAnchorText(Ds.FileName, pRoute.Line), '', pRoute.Routine, NOTE_FILL_CALL));
  var Entry:= NewTraceStep(KIND_STEP, 'CALLS ' + pRoute.TargetShort + pRoute.Lits, TraceAnchorText(pRoute.TargetPath, pRoute.TargetImpl), '',
    pRoute.Routine, Format('from :%d', [pRoute.Line]));
  for var C in pRoute.Walk.Conds do
    Entry.Children.Add(C);
  Disown(pRoute.Walk.Conds);
  var Ri:= TObjectList<TTraceItem>.Create;
  try
    Ri.Add(Entry);
    for var I in pRoute.Walk.Items do
      Ri.Add(I);
    Disown(pRoute.Walk.Items);
    var Xi:= -1;
    for var K:= 0 to Ri.Count - 1 do
      if Ri[K].Kind = KIND_CROSSES then
      begin
        Xi:= K;
        Break;
      end;
    var Xr:= Ri[Xi];
    for var K:= 0 to Xi do
      FSecRd.Items.Add(Ri[K]);
    Disown(Ri, Xi + 1);
    { the far side on the SERVER index, then its DATABASE facts, still on the SERVER index (AC-9) }
    var Srv:= FWalker.ServerHandling(Xr.Command, pRoute.Ctx, FDepth);
    try
      if Srv.HasContract then
        Xr.Children.Add(NewTraceFacet(FACET_CONTRACT, Srv.ContractText, Srv.ContractAnchor, NOTE_FAR_SIDE));
      var Db: TDatabaseSteps:= nil;
      try
        { no DATABASE steps below a server side that stopped (READ is one section: nothing to note) }
        if Srv.Walked then
          Db:= FWalker.DatabaseSteps(Srv.Items.ToArray, pRoute.Ctx, MODE_READ)
        else
          FRStop:= Srv.Stop;
        if Db <> nil then
          for var I in Db.Items do
            I.Actor:= ACTOR_DATABASE;
        { the DATABASE steps stand right after the SERVER step that RUNS the query (the stop's After), in source order }
        var DbPlaced:= False;
        for var I in Srv.Items do
        begin
          I.Actor:= ACTOR_SERVER;
          FSecRd.Items.Add(I);
          if (not DbPlaced) and (Db <> nil) and (Db.After <> nil) and (I = Db.After) then
          begin
            for var D in Db.Items do
              FSecRd.Items.Add(D);
            DbPlaced:= True;
          end;
        end;
        Disown(Srv.Items);
        if (not DbPlaced) and (Db <> nil) then
          for var D in Db.Items do
            FSecRd.Items.Add(D);
        if Db <> nil then
          Disown(Db.Items);
      finally
        Db.Free;
      end;
      { the rows come back on the SAME ExecuteCommand call (ruling P4: request and response share its anchor) }
      FSecRd.Items.Add(BackStep(Xr, Srv, NOTE_ROWS_BACK));
    finally
      Srv.Free;
    end;
    for var I in Ri do
    begin
      I.Actor:= ACTOR_CLIENT;
      FSecRd.Items.Add(I);
    end;
    Disown(Ri);
  finally
    Ri.Free;
  end;
  FWalker.MergeTraceOmits(FSecRd);
end;

{ ---- ALSO ---- }

{ PS :265-278: every other route to the anchor the index holds, minus the traced ones }
procedure TRoundTripRun.WalkAlso(pRoutes: TObjectList<TFillRoute>);
begin
  var Ds:= FAnchor.DataSet;
  var Traced:= TTraceWalker.TracedRouteIds([FSecW.Items.ToArray, FSecRd.Items.ToArray]);
  var Skip:= TList<Integer>.Create;
  try
    for var Id in Traced.Callers do
      if not Skip.Contains(Id) then
        Skip.Add(Id);
    for var W in FWiring do
      if not Skip.Contains(W.HandlerId) then
        Skip.Add(W.HandlerId);
    var Others:= FWalker.AlsoRoutes(Traced.Senders, Skip.ToArray, FCtx);
    try
      for var R in Others do
        FAlsoRows.Add(R);
      Disown(Others);
    finally
      Others.Free;
    end;
  finally
    Skip.Free;
  end;
  for var K:= 1 to pRoutes.Count - 1 do
    FAlsoRows.Add(NewTraceStep(KIND_STEP, Format('LOADS %s VIA %s%s', [Ds.Name, pRoutes[K].TargetShort, pRoutes[K].Lits]),
      TraceAnchorText(Ds.FileName, pRoutes[K].Line), '', pRoutes[K].Routine, NOTE_OTHER_ROUTE));
  for var R in FAlsoRows do
    FSecAl.Items.Add(R);
  Disown(FAlsoRows);
  { an empty ALSO is not a hop that failed: no STOPS, nothing unresolved; the section says so in a note }
  if FSecAl.Items.Count = 0 then
    FSecAl.Note:= NO_ALSO;
  FRead:= FSecRd.Items.Count;
  FAlso:= FSecAl.Items.Count;
end;

{ ---- 7. the not-walked notes and the title, now that every step has its final number ---- }

procedure TRoundTripRun.WriteNotesAndTitle;
begin
  for var X in FNotes do
    X.Sec.Note:= TraceNoteText(Format('not walked: the %s direction stopped at [%.2d]', [X.Dir, ItemNumber(X.Stop)]));
  if (FAnchor.Stop <> '') or ((FWStop = nil) and (FRStop = nil)) then
    Exit;
  var NW:= if FWStop <> nil then ItemNumber(FWStop) else 0;
  var NR:= if FRStop <> nil then ItemNumber(FRStop) else 0;
  if (FWStop <> nil) and (FRStop <> nil) then
    FTrace.Title:= Format(TITLE_BOTH_STOP, [FTarget, FName, Min(NW, NR), Max(NW, NR)])
  else if FWStop <> nil then
    FTrace.Title:= Format(TITLE_WRITE_STOPS, [FName, FTarget, NW])
  else
    FTrace.Title:= Format(TITLE_READ_STOPS, [FTarget, FName, NR]);
end;

{ ---- 7b. the full path of every anchor leaf (DOC-R1, PS :293-310) ---- }

function TRoundTripRun.AnchorPathsOf(const pText: string): TDictionary<string, string>;
begin
  Result:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  var Leaves: TArray<string>:= [];
  for var M in TRegEx.Matches(pText, ANCHOR_LEAF_RX, [roIgnoreCase]) do
  begin
    var Leaf:= M.Groups[1].Value;
    var Seen:= False;
    for var L in Leaves do
      if L = Leaf then
        Seen:= True;
    if not Seen then
      Leaves:= Leaves + [Leaf];
  end;
  if Length(Leaves) = 0 then
    Exit;
  var Wheres: TArray<string>:= [];
  for var L in Leaves do
    Wheres:= Wheres + [Format('path LIKE ''%%\%s''', [TChartsIndex.SqlText(L)])];
  var Sql:= Format(SQL_ANCHOR_PATHS, [string.Join(' OR ', Wheres)]);
  var Order:= TList<string>.Create;
  var PathsOf:= TObjectDictionary<string, TDictionary<string, string>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  try
    for var Idx in [FCli, FSrv, FSql] do
    begin
      var Rows:= Idx.Query(Sql);
      try
        for var Row in Rows do
        begin
          var Path:= Row.S('p');
          var Leaf:= ExtractFileName(Path);
          var Known:= False;
          for var L in Leaves do
            if SameText(L, Leaf) then
              Known:= True;
          if not Known then
            Continue;
          if not PathsOf.ContainsKey(Leaf) then
          begin
            PathsOf.Add(Leaf, TDictionary<string, string>.Create);
            Order.Add(Leaf);
          end;
          PathsOf[Leaf].AddOrSetValue(LowerCase(Path), Path);
        end;
      finally
        Rows.Free;
      end;
    end;
    { kept only when the three indexes name exactly ONE path for the leaf: an ambiguous leaf stays text }
    for var K in Order do
      if PathsOf[K].Count = 1 then
        for var V in PathsOf[K].Values do
          Result.Add(K, V);
  finally
    PathsOf.Free;
    Order.Free;
  end;
end;

procedure TRoundTripRun.RemoveChartFiles;
begin
  for var X in CHART_EXTS do
    System.SysUtils.DeleteFile(TPath.Combine(FOutDir, FBase + '.' + X));
end;

{ ---- 9. the emitter object's properties, in the PS order (the file paths and the chart objects excluded) ---- }

{ PS :363: each DERIVED row as `<text> => <target>`, the target parsed from its REGENERATE facet ('' when none) }
function TRoundTripRun.DerivedRows: TArray<string>;
begin
  Result:= [];
  if FSecDv = nil then
    Exit;
  for var Item in FSecDv.Items do
  begin
    var Targets: TArray<string>:= [];
    for var C in Item.Children do
      if (C.Kind = KIND_FACET) and (C.Head = HEAD_REGENERATE) then
      begin
        var M:= TRegEx.Match(C.Text, TARGET_RX, [roIgnoreCase]);
        if M.Success then
          Targets:= Targets + [M.Groups[1].Value];
      end;
    Result:= Result + [Item.Text + ' => ' + string.Join('', Targets)];
  end;
end;

{ PS :364 }
function TRoundTripRun.DerivedCommands: TArray<string>;
begin
  Result:= [];
  if FSecDv = nil then
    Exit;
  for var Item in FSecDv.Items do
    for var C in Item.Children do
      if (C.Kind = KIND_FACET) and (C.Head = HEAD_REGENERATE) then
        Result:= Result + [C.Text];
end;

function TRoundTripRun.ResultFields(const pChartError: string; pChartNodes, pClickTargets: Integer;
  pAllClickable: Boolean): TArray<TMetaField>;
begin
  var C:= TraceCounts(FTrace);
  var Notes: TArray<string>:= [];
  var Names: TArray<string>:= [];
  var AlsoTexts: TArray<string>:= [];
  for var S in FTrace.Sections do
  begin
    Names:= Names + [S.Name];
    if S.Note <> '' then
      Notes:= Notes + [S.Name + '=' + S.Note];
  end;
  for var I in FSecAl.Items do
    AlsoTexts:= AlsoTexts + [I.Text];
  var DsName:= if FAnchor.HasDataSet then FAnchor.DataSet.Name else '';
  var DerivedNote:= if FSecDv <> nil then FSecDv.Note else '';
  Result:= [TMetaField.Str('ChartError', pChartError), TMetaField.Int('ChartNodes', pChartNodes), TMetaField.Str('Title', FTrace.Title),
    TMetaField.Str('Notes', string.Join(' | ', Notes)), TMetaField.Str('Anchor', FName), TMetaField.Str('DataSet', DsName),
    TMetaField.Str('Table', FAnchor.Table), TMetaField.Str('Column', FAnchor.Column), TMetaField.Str('TableColumn', FAnchor.TableColumn),
    TMetaField.Str('Stop', FAnchor.Stop), TMetaField.Int('Steps', C.Steps), TMetaField.Int('Conditions', C.Conditions),
    TMetaField.Int('Crossings', C.Crossings), TMetaField.Int('Unresolved', C.Unresolved), TMetaField.Int('WriteSteps', FWrite),
    TMetaField.Int('ReadSteps', FRead), TMetaField.Int('AlsoSteps', FAlso), TMetaField.StrList('Also', AlsoTexts),
    TMetaField.Str('DerivedNote', DerivedNote), TMetaField.StrList('Derived', DerivedRows),
    TMetaField.StrList('DerivedCommands', DerivedCommands), TMetaField.Str('Sections', string.Join(',', Names)),
    TMetaField.Str('OnDbProof', Format('%d/%d', [FWalker.FilesCount(tsClient), FWalker.FilesCount(tsServer)])),
    TMetaField.Int('ClickTargets', pClickTargets), TMetaField.Int('Expected', pClickTargets),
    TMetaField.Bool('AllClickable', pAllClickable)];
end;

{ ---- the question ---- }

function TRoundTripRun.Emit: TChartResult;
begin
  Result:= Default(TChartResult);
  FCliName:= TRegEx.Replace(ChangeFileExt(ExtractFileName(FCliDb), ''), CLIENT_PREFIX_RX, '', [roIgnoreCase]);
  FSrvName:= TRegEx.Replace(ChangeFileExt(ExtractFileName(FSrvDb), ''), SERVER_PREFIX_RX, '', [roIgnoreCase]);
  RemoveOutputs;
  CheckSqlIndex;
  BuildAnchor;
  if FAnchor.Stop = '' then
  begin
    try
      WalkWrite;
      var Routes := FWalker.FillRoutes(FAnchor.DataSet, FCtx, FDepth);
      try
        WalkRead(Routes);
        WalkAlso(Routes);
      finally
        Routes.Free;
      end;
    except
      on E: EChartsTrace do
        raise EChartsQuestion.Create(E.Message);
    end;
  end;
  WriteNotesAndTitle;
  var Text:= WriteFormA(FTrace);
  var TracePath:= TPath.Combine(FOutDir, FBase + TRACE_EXT);
  var Paths:= AnchorPathsOf(Text);
  try
    { the chart is drawn from the BYTES just written, never from a second walk (R5); a renderer throw is loud }
    var Reread:= ReadFormA(Text);
    var Chart: TTraceChart;
    try
      Chart:= TraceChart(Reread, Paths, TChartCaps.Default);
    finally
      Reread.Free;
    end;
    var ChartError:= '';
    var ChartNodes:= Chart.Manifest.Nodes;
    Chart.Manifest.Free;
    try
      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(FArgs.Dot, Chart.Dot, FOutDir, FBase, Msgs);
    except
      on E: Exception do
      begin
        ChartError:= E.Message;
        RemoveChartFiles;
        Result.Layout:= Default(TDotLayout);
      end;
    end;
    { the text LAST, so a refusal anywhere above leaves nothing behind }
    TFile.WriteAllText(TracePath, Text, TEncoding.ASCII);
    var Anchors:= TraceAnchors(FTrace);
    var Clickable:= Length(TraceUnclickable(Text)) = 0;
    var C:= TraceCounts(FTrace);
    Result.TracePath:= TracePath;
    Result.ChartError:= ChartError;
    var Aps:= TList<TAnchorPath>.Create;
    try
      for var Pair in Paths do
      begin
        var AP: TAnchorPath;
        AP.Leaf:= Pair.Key;
        AP.Path:= Pair.Value;
        Aps.Add(AP);
      end;
      Result.AnchorPaths:= Aps.ToArray;
    finally
      Aps.Free;
    end;
    Result.LeftCount:= C.Steps;
    Result.RightCount:= C.Unresolved;
    Result.ClickTargets:= Anchors;
    Result.AllClickable:= Clickable;
    Result.Fields:= ResultFields(ChartError, ChartNodes, Anchors, Clickable);
  finally
    Paths.Free;
  end;
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  { New-DiagramArtifact refuses before the PS emitter is reached }
  if (pArgs.ServerDbPath = '') or (pArgs.SqlDbPath = '') then
    raise EChartsQuestion.Create('round-trip needs -ServerDbPath (the SERVER clone) and -SqlDbPath (the SQL-script clone); ' +
      '-DbPath is the CLIENT clone');
  var Run:= TRoundTripRun.Create(pArgs, pOutDir);
  try
    Result:= Run.Emit;
  finally
    Run.Free;
  end;
end;

initialization
  RegisterChartQuestion(ROUND_TRIP_ID, Emit);

end.
