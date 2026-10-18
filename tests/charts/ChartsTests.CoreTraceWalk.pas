unit ChartsTests.CoreTraceWalk;

(* Cases for DRagLint.Charts.Trace.Walk, the round-trip walk (a port of charts\src\Trace.Walk.ps1 Parts
  3-5; task-6-harvest.txt of the d1 ledger holds what the PowerShell printed for the same calls on the
  same clones, and the PS output is the reference). The expectations are rows of text, one per item
  (Kind|Actor|Text|Grade|Anchor|Routine|Note|Ask|Line|Owner) and one per child line, so a regression
  names the row.

  The cases run on the CLIENT, SERVER and SQL clones (charts\scratch\db, found like CoreChain finds
  them) and pass vacuously when the clones are missing. The walk reads FRESH source (AC-14): the cases
  need the ORM3 files the clones were indexed from; the stale case registers a changed copy of the
  handler's file as the override of its indexed path and is refused by name. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreTraceWalkTests = class
  public
    [Test] procedure HandlerWalkMatchesPowerShell;
    [Test] procedure ServerHandlingRoutesCmdDelta;
    [Test] procedure WriteDatabaseStepsStopOnTheStatement;
    [Test] procedure FillRoutesOfFmtOperation;
    [Test] procedure ReadSelectStopIsAssembledHere;
    [Test] procedure AlsoRoutesSkipTheTraced;
    [Test] procedure FtrsAnchorWalksTheOtherSender;
    [Test] procedure StaleFileRefusesByName;
    [Test] procedure IndexFactsAndBoundaryLikes;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, DRagLint.Charts.Index, DRagLint.Charts.Source,
  DRagLint.Charts.Sql, DRagLint.Charts.Chain, DRagLint.Charts.Trace.FormA, DRagLint.Charts.Trace.Anchor,
  DRagLint.Charts.Trace.Walk;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLIENT_REL = 'charts\scratch\db\CLIENT-Micronite2027.sqlite';
  SERVER_REL = 'charts\scratch\db\SERVER-MicroniteMW1Service.sqlite';
  SQL_REL = 'charts\scratch\db\SQL-drag-lint-sql.sqlite';
  BOUNDARY = 'Pipes.%|uPipe%|uBroadcast%';
  NEAR_NAME = 'Micronite2027';
  FAR_NAME = 'MicroniteMW1Service';
  WALK_DEPTH = 4;
  CTL_OPERAT = 'frmBlueprint4.dxDBGrid1OperationVName';
  CTL_FTRS = 'frmBlueprint4.dxDBGrid1FtrsVNum';
  SENDER_OPERAT = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation';
  FACTS_HANDLER = '144234|TBlueprint_ViewModel.DoAfterPostOperation|3948|3952|refs=5|lits=1|pid=144036|decl=277|sqlr=|sqlw=';
  FACTS_SENDER = '144238|TBlueprint_ViewModel.SendDeltaOperation|3960|4016|refs=129|lits=5';
  COND_OPERAT = '  COND|UNLESS|FSuppressEvents|Blueprint4.ViewModel.pas:3950||E1|';
  COND_FTRS = '  COND|UNLESS|FSuppressEvents|Blueprint4.ViewModel.pas:3555||E1|';
  ROUTE0_COND = '  COND|UNLESS|not (Assigned(FConn) and FConn.Connected)|Blueprint4.ViewModel.pas:1133||E1|';
  SERVER_ITEMS_OPERAT = 24;
  SERVER_ITEMS_FTRS = 28;
  READ_SERVER_ITEMS = 15;
  ROUTES_FTRS = 15;
  ALSO_FTRS = 17;
  AFTER_INDEX = 11;
  RESPONSES_WRITE = 'rspError,rspOK';
  RESPONSES_READ = 'rspData,rspError';
  CONTRACT_DELTA = 'Pipes.Protocol.IPipeSessionBuilder.HandleDelta|Pipes.Protocol.pas:392';
  CONTRACT_LOAD = 'Pipes.Protocol.IPipeSessionBuilder.HandleTableLoad|Pipes.Protocol.pas:378';
  ROUTES_OPERAT: array[0..1] of string = (
    '1207|TBlueprint_ViewModel.LoadAllForFolder|144218|TBlueprint_ViewModel.LoadOneTable|Blueprint4.ViewModel.pas|1123| ''OPERAT''|items=4|conds=1',
    '4306|TBlueprint_ViewModel.VerifyAll|144218|TBlueprint_ViewModel.LoadOneTable|Blueprint4.ViewModel.pas|1123| ''OPERAT''|items=4|conds=1');
  AFTER_ROW = 'RUNS Qry.Open|uPipeSessionBuilder.pas:594';
  TRACED_OPERAT = 'senders=144238:3985,144218:1136 callers=144234,144238';
  TRACED_FTRS = 'senders=144226:3594,144218:1136 callers=144222,144226';
  LIKES = 'u.qualified_name LIKE ''Pipes.%'' OR u.qualified_name LIKE ''uPipe%'' OR u.qualified_name LIKE ''uBroadcast%''';
  FILES_CLIENT = 625;
  FILES_SERVER = 471;
  STAMPS = '2026-10-05T16:25Z/2026-10-05T16:21Z/2026-10-05T16:11Z';
  STALE_TEXT = 'round-trip: Blueprint4.ViewModel.pas differs from the indexed copy (sha256) -- refusing to read it. Reindex the ' +
    'project, then re-run.';
  BYTE_LF = 10;
  BYTE_SPACE = 32;
  WALK_OPERAT: array[0..12] of string = (
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation ''AfterPost''||Blueprint4.ViewModel.pas:3960|TBl' +
      'ueprint_ViewModel.DoAfterPostOperation|from :3951||3951|144234',
    '  COND|UNLESS|FMTOperation.ChangeCount = 0|Blueprint4.ViewModel.pas:3973|else Exit(True)|E1|',
    '  COND|UNLESS|not (Assigned(FConn) and FConn.Connected)|Blueprint4.ViewModel.pas:3974||E1|',
    'step||SERIALIZES FMTOperation.SaveToStream||Blueprint4.ViewModel.pas:3978|TBlueprint_ViewModel.SendD' +
      'eltaOperation|||3978|144238',
    'crosses||process boundary||Blueprint4.ViewModel.pas:3985|TBlueprint_ViewModel.SendDeltaOperation|cmd' +
      'Delta via ExecuteCommand||3985|144238',
    '  FACET|FROM|Micronite2027||the index this side was read from',
    '  FACET|TO|MicroniteMW1Service||the counterpart index, queried separately',
    '  FACET|OVER|uPipeClientConnection.ExecuteCommand|uPipeClientConnection.pas:460|transport unit match' +
      'ed by naming convention',
    '  FACET|WITH|cmdDelta ''TABLE=OPERAT|'' + sfBinary stream|Blueprint4.ViewModel.pas:3985|payload infe' +
      'rred from the literals before the send',
    '  FACET|CONTRACT|Pipes.Protocol.TCommandID.cmdDelta|Pipes.Protocol.pas:55|',
    'step||RECEIVES rspOK||Blueprint4.ViewModel.pas:3990|TBlueprint_ViewModel.SendDeltaOperation|||3990|1' +
      '44238',
    '  COND|UNLESS|(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK)|Blueprint4.ViewModel' +
      '.pas:3990|else FMTOperation.CancelUpdates @Blueprint4.ViewModel.pas:3999|E1|',
    'step||APPLIES FMTOperation.CommitUpdates||Blueprint4.ViewModel.pas:4010|TBlueprint_ViewModel.SendDel' +
      'taOperation|||4010|144238');
  SERVER_OPERAT: array[0..40] of string = (
    'step||ROUTES cmdDelta TO IPipeSessionBuilder.HandleDelta||Pipes.Commands.pas:173|DispatchCommand|the' +
      ' first cross-unit call after the constant, at :177|E2|173|0',
    'step||CALLS TPipeSessionBuilder.HandleDelta|by name|uPipeSessionBuilder.pas:1209|DispatchCommand|fro' +
      'm :177, the interface method resolved to its one implementation|E2|177|0',
    'step||CALLS TGenericTableRoute.HandleDelta||uGenericTableRoute.pas:389|TPipeSessionBuilder.HandleDel' +
      'ta|from :1213||1213|106963',
    'step||CALLS SplitPayload||uGenericTableRoute.pas:244|TGenericTableRoute.HandleDelta|from :409||409|1' +
      '07777',
    '  COND|UNLESS|BarPos < 0|uGenericTableRoute.pas:254||E1|',
    '  COND|UNLESS|TableName = ''''|uGenericTableRoute.pas:411|else ''cmdDelta: TABLE= prefix missing'', ' +
      'responds rspError, the default set at :405|E1|TGenericTableRoute.HandleDelta',
    '  COND|UNLESS|Length(StreamBytes) = 0|uGenericTableRoute.pas:421|else ''cmdDelta: empty delta stream' +
      ' for '', responds rspError, the default set at :405|E1|TGenericTableRoute.HandleDelta',
    'step||CALLS TDatasetsDef.EnsureLoaded||uDatasetsDef.pas:92|TGenericTableRoute.HandleDelta|from :429|' +
      '|429|107777',
    '  COND|WHEN|not GDatasetsDef.Loaded|uGenericTableRoute.pas:429||E1|TGenericTableRoute.HandleDelta',
    '  COND|UNLESS|FLoaded|uDatasetsDef.pas:94||E1|',
    'step||CALLS TDatasetsDef.LoadFromInternal||uDatasetsDef.pas:115|TDatasetsDef.EnsureLoaded|from :97||' +
      '97|107694',
    '  COND|WHEN|not FLoaded|uDatasetsDef.pas:97||E1|TDatasetsDef.EnsureLoaded',
    'step||READS FROM FIB$DATASETS_INFO|inferred|uDatasetsDef.pas:130|TDatasetsDef.LoadFromInternal|a FIB' +
      '$ literal in the body|E4|130|107689',
    'step||RUNS Q.Open||uDatasetsDef.pas:131|TDatasetsDef.LoadFromInternal|||131|107689',
    'step||READS FROM FIB$FIELDS_INFO|inferred|uDatasetsDef.pas:167|TDatasetsDef.LoadFromInternal|a FIB$ ' +
      'literal in the body|E4|167|107689',
    'step||RUNS Q.Open||uDatasetsDef.pas:169|TDatasetsDef.LoadFromInternal|||169|107689',
    'step||CALLS TDatasetsDef.GetTable||uDatasetsDef.pas:199|TGenericTableRoute.HandleDelta|from :431||43' +
      '1|107777',
    '  COND|UNLESS|not GDatasetsDef.GetTable(TableName, Def)|uGenericTableRoute.pas:431|else a literal at' +
      ' :434, responds rspError, the default set at :405|E1|TGenericTableRoute.HandleDelta',
    'step||DESERIALIZES Mem.LoadFromStream||uGenericTableRoute.pas:445|TGenericTableRoute.HandleDelta|||4' +
      '45|107777',
    '  COND|UNLESS|Mem.LoadFromStream(MS, sfBinary) raises|uGenericTableRoute.pas:446|else ''cmdDelta: Lo' +
      'adFromStream failed for %s: %s'', responds rspError, the default set at :405|E1|',
    'step||OMITS 11 step(s) in branches for other tables, every enclosing if read up to a loop or case ar' +
      'm||uGenericTableRoute.pas:468|TGenericTableRoute.HandleDelta|not walked, the branch conditions: WHEN' +
      ' TableName = ''MSCLIST'' @uGenericTableRoute.pas:468 / WHEN TableName = ''OPTRLIST'' @uGenericTableR' +
      'oute.pas:476 / WHEN (TableName = ''MSCLIST'') and (Ctx.AppliedIns > 0) @uGenericTableRoute.pas:515 /' +
      ' WHEN (TableName = ''OPTRLIST'') and (Length(RoleSyncItems) > 0) @uGenericTableRoute.pas:540|E1|469|' +
      '107777',
    'step||ATTACHES Mem.OnUpdateRecord -> TGenericApplyContext.HandleUpdateRecord||uGenericTableRoute.pas' +
      ':479|TGenericTableRoute.HandleDelta|||479|107777',
    'step||OPENS AThreadStorage.UpdateTransaction.StartTransaction||uGenericTableRoute.pas:492|TGenericTa' +
      'bleRoute.HandleDelta|||492|107777',
    '  COND|WHEN|not WasTxn|uGenericTableRoute.pas:492||E1|',
    'step||APPLIES Mem.ApplyUpdates||uGenericTableRoute.pas:494|TGenericTableRoute.HandleDelta|||494|1077' +
      '77',
    '  COND|UNLESS|ApplyResult:= Mem.ApplyUpdates(0) ... raises|uGenericTableRoute.pas:570|else AThreadSt' +
      'orage.UpdateTransaction.Rollback @uGenericTableRoute.pas:573, rspError, ''cmdDelta %s: %s''|E1|',
    'step||CALLS TGenericApplyContext.HandleUpdateRecord||uGenericTableRoute.pas:183|TGenericTableRoute.H' +
      'andleDelta|fired by Mem.ApplyUpdates at :494, attached as Mem.OnUpdateRecord at :479||494|107777',
    '  COND|UNLESS|case ARequest of|uGenericTableRoute.pas:188|else arm at :192|E1|',
    '  COND|UNLESS|SQL = ''''|uGenericTableRoute.pas:196||E1|',
    'step||CALLS TGenericApplyContext.BindParams||uGenericTableRoute.pas:123|TGenericApplyContext.HandleU' +
      'pdateRecord|from :208||208|107766',
    'step||DESERIALIZES ACmd.Params[I].LoadFromStream||uGenericTableRoute.pas:169|TGenericApplyContext.Bi' +
      'ndParams|||169|107757',
    '  COND|WHEN|Field is TBlobField|uGenericTableRoute.pas:157||E1|',
    '  COND|UNLESS|IsOld or Field.IsNull|uGenericTableRoute.pas:160||E1|',
    'step||RUNS Cmd.Execute||uGenericTableRoute.pas:210|TGenericApplyContext.HandleUpdateRecord|||210|107' +
      '766',
    'step||APPLIES Mem.CommitUpdates||uGenericTableRoute.pas:497|TGenericTableRoute.HandleDelta|||497|107' +
      '777',
    '  COND|WHEN|ApplyResult = 0|uGenericTableRoute.pas:495|else AThreadStorage.UpdateTransaction.Rollbac' +
      'k @uGenericTableRoute.pas:562, rspError|E1|',
    'step||RUNS AThreadStorage.UpdateTransaction.Commit||uGenericTableRoute.pas:498|TGenericTableRoute.Ha' +
      'ndleDelta|||498|107777',
    '  COND|WHEN|not WasTxn|uGenericTableRoute.pas:498||E1|',
    'step||CALLS TBroadcastServer.PushTableChanged||uBroadcastServer.pas:401|TGenericTableRoute.HandleDel' +
      'ta|from :507||507|107777',
    '  COND|WHEN|Assigned(GBroadcastServer)|uGenericTableRoute.pas:507||E1|TGenericTableRoute.HandleDelta',
    'step||SENDS rspOK||uGenericTableRoute.pas:553|TGenericTableRoute.HandleDelta|overwrites the rspError' +
      ' default set at :405||553|107777');
  DBW_OPERAT: array[0..1] of string = (
    'stops||the statement for the posted OPERAT row is FDef.InsertSQL (loaded at uDatasetsDef.pas:148), F' +
      'Def.UpdateSQL (loaded at uDatasetsDef.pas:149) or FDef.DeleteSQL (loaded at uDatasetsDef.pas:150), p' +
      'icked by the case over ARequest at :188, from FIB$DATASETS_INFO rows the index does not hold (fb_dat' +
      'asets has 0 rows in MicroniteMW1Service)||uGenericTableRoute.pas:190|TGenericApplyContext.HandleUpda' +
      'teRecord|the statement member is named here, in the routine that executes it|E4|0|0',
    'step||WRITES OPERAT.NAME|inferred|MS1.SQL:2809||NAME is a column of the newest of 2 OPERAT declarati' +
      'ons (SQL index, MS1.SQL:2809)|E4|0|0');
  ROUTE0_OPERAT: array[0..11] of string = (
    'crosses||process boundary||Blueprint4.ViewModel.pas:1136|TBlueprint_ViewModel.LoadOneTable|cmdTableL' +
      'oad via ExecuteCommand||1136|144218',
    '  FACET|FROM|Micronite2027||the index this side was read from',
    '  FACET|TO|MicroniteMW1Service||the counterpart index, queried separately',
    '  FACET|OVER|uPipeClientConnection.ExecuteCommand|uPipeClientConnection.pas:460|transport unit match' +
      'ed by naming convention',
    '  FACET|WITH|cmdTableLoad ''TABLE='' + ATableName + ''|BLOBS=0|WHERE='' + AWhere|Blueprint4.ViewMode' +
      'l.pas:1136|payload quoted from the assignment at :1134',
    '  FACET|CONTRACT|Pipes.Protocol.TCommandID.cmdTableLoad|Pipes.Protocol.pas:57|',
    'step||RECEIVES rspData||Blueprint4.ViewModel.pas:1137|TBlueprint_ViewModel.LoadOneTable|||1137|14421' +
      '8',
    '  COND|UNLESS|(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspData)|Blueprint4.ViewMod' +
      'el.pas:1137||E1|',
    'step||EMPTIES AMT.EmptyDataSet||Blueprint4.ViewModel.pas:1162|TBlueprint_ViewModel.LoadOneTable|||11' +
      '62|144218',
    '  COND|WHEN|AMT.Active|Blueprint4.ViewModel.pas:1162||E1|',
    'step||DESERIALIZES AMT.LoadFromStream||Blueprint4.ViewModel.pas:1167|TBlueprint_ViewModel.LoadOneTab' +
      'le|||1167|144218',
    '  COND|WHEN|Length(RspPayload) > 0|Blueprint4.ViewModel.pas:1163||E1|');
  DBR_OPERAT: array[0..1] of string = (
    'stops||the SELECT statement for OPERAT is assembled in SQL at uPipeSessionBuilder.pas:544 (SQL:= ''S' +
      'ELECT '' + ColSQL + '' FROM '' + ATableName) and :556 (SQL:= SQL + '' WHERE '' + WhereSql), from val' +
      'ues the index holds no text for, and the FIB$ rows the walk reads (FIB$DATASETS_INFO, FIB$FIELDS_INF' +
      'O) are not in the index (fb_datasets has 0 rows, fb_field_info has 0 rows in MicroniteMW1Service)||u' +
      'PipeSessionBuilder.pas:544|TPipeSessionBuilder.HandleTableLoad|the statement is assembled here, in t' +
      'he routine that runs it|E4|0|0',
    'step||READS OPERAT.NAME|inferred|MS1.SQL:2809||NAME is a column of the newest of 2 OPERAT declaratio' +
      'ns (SQL index, MS1.SQL:2809)|E4|0|0');
  ALSO_OPERAT: array[0..6] of string = (
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation||Blueprint4.ViewModel.pas:1853|TBlueprint_ViewMo' +
      'del.ImportJenVICI|another caller of the traced sender|',
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation||Blueprint4.ViewModel.pas:2175|TBlueprint_ViewMo' +
      'del.ImportLK|another caller of the traced sender|',
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation||Blueprint4.ViewModel.pas:2441|TBlueprint_ViewMo' +
      'del.ImportNikon|another caller of the traced sender|',
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation||Blueprint4.ViewModel.pas:3124|TBlueprint_ViewMo' +
      'del.ImportSheffield|another caller of the traced sender|',
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation||Blueprint4.ViewModel.pas:3416|TBlueprint_ViewMo' +
      'del.ImportZEISS|another caller of the traced sender|',
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation||Blueprint4.ViewModel.pas:4099|TBlueprint_ViewMo' +
      'del.AddOperation|another caller of the traced sender|',
    'step||CALLS TBlueprint_ViewModel.SendDeltaOperation||Blueprint4.ViewModel.pas:4273|TBlueprint_ViewMo' +
      'del.VerifyAll|another caller of the traced sender|');
  WALK_FTRS: array[0..12] of string = (
    'step||CALLS TBlueprint_ViewModel.SendDeltaFtrs ''AfterPost''||Blueprint4.ViewModel.pas:3565|TBluepri' +
      'nt_ViewModel.DoAfterPostFtrs|from :3556||3556|144222',
    '  COND|UNLESS|FMTFtrs.ChangeCount = 0|Blueprint4.ViewModel.pas:3582|else Exit(True)|E1|',
    '  COND|UNLESS|not (Assigned(FConn) and FConn.Connected)|Blueprint4.ViewModel.pas:3583||E1|',
    'step||SERIALIZES FMTFtrs.SaveToStream||Blueprint4.ViewModel.pas:3587|TBlueprint_ViewModel.SendDeltaF' +
      'trs|||3587|144226',
    'crosses||process boundary||Blueprint4.ViewModel.pas:3594|TBlueprint_ViewModel.SendDeltaFtrs|cmdDelta' +
      ' via ExecuteCommand||3594|144226',
    '  FACET|FROM|Micronite2027||the index this side was read from',
    '  FACET|TO|MicroniteMW1Service||the counterpart index, queried separately',
    '  FACET|OVER|uPipeClientConnection.ExecuteCommand|uPipeClientConnection.pas:460|transport unit match' +
      'ed by naming convention',
    '  FACET|WITH|cmdDelta ''TABLE=MSCLIST|'' + sfBinary stream|Blueprint4.ViewModel.pas:3594|payload inf' +
      'erred from the literals before the send',
    '  FACET|CONTRACT|Pipes.Protocol.TCommandID.cmdDelta|Pipes.Protocol.pas:55|',
    'step||RECEIVES rspOK||Blueprint4.ViewModel.pas:3599|TBlueprint_ViewModel.SendDeltaFtrs|||3599|144226',
    '  COND|UNLESS|(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK)|Blueprint4.ViewModel' +
      '.pas:3599|else FMTFtrs.CancelUpdates @Blueprint4.ViewModel.pas:3611|E1|',
    'step||APPLIES FMTFtrs.CommitUpdates||Blueprint4.ViewModel.pas:3629|TBlueprint_ViewModel.SendDeltaFtr' +
      's|||3629|144226');

type
  TClones = class
  public
    Client: TChartsIndex;
    ClientReader: TSourceReader;
    Server: TChartsIndex;
    ServerReader: TSourceReader;
    SqlIndex: TChartsIndex;
    SqlReader: TSourceReader;
    Catalog: TSqlCatalog;
    Chain: TChainWalker;
    Resolver: TTraceAnchorResolver;
    Walker: TTraceWalker;
    class function Open: TClones;
    destructor Destroy; override;
  end;

  { One anchor and what the emitter derives from it before the walk (Emit-RoundTrip.ps1:138-139, 172-181). }
  TRun = class
  public
    Anchor: TAnchorResult;
    Ctx: TTraceContext;
    Wiring: TArray<TEventWiring>;
    constructor Create(pC: TClones; const pTarget: string);
    destructor Destroy; override;
  end;

function FindUp(const pRel: string): string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, pRel)) then
    Exit(TPath.Combine(Root, pRel));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, pRel)) then
      Exit(TPath.Combine(Dir, pRel));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

{ nil when the clones are missing }
class function TClones.Open: TClones;
begin
  var ClientDb:= FindUp(CLIENT_REL);
  var ServerDb:= FindUp(SERVER_REL);
  var SqlDb:= FindUp(SQL_REL);
  if (ClientDb = '') or (ServerDb = '') or (SqlDb = '') then
    Exit(nil);
  Result:= TClones.Create;
  Result.Client:= TChartsIndex.Create(ClientDb);
  Result.ClientReader:= TSourceReader.Create(Result.Client);
  Result.Server:= TChartsIndex.Create(ServerDb);
  Result.ServerReader:= TSourceReader.Create(Result.Server);
  Result.SqlIndex:= TChartsIndex.Create(SqlDb);
  Result.SqlReader:= TSourceReader.Create(Result.SqlIndex);
  Result.Catalog:= TSqlCatalog.Create(Result.SqlIndex, Result.SqlReader);
  Result.Chain:= TChainWalker.Create(Result.Client, Result.ClientReader, Result.Catalog, Result.Catalog.TableSet);
  Result.Resolver:= TTraceAnchorResolver.Create(Result.Client, Result.ClientReader, Result.Chain, Result.Catalog,
    Result.Catalog.TableSet);
  Result.Walker:= TTraceWalker.Create(Result.Client, Result.Server, Result.ClientReader, Result.ServerReader, Result.Catalog,
    Result.Catalog.TableSet);
end;

destructor TClones.Destroy;
begin
  Walker.Free;
  Resolver.Free;
  Chain.Free;
  Catalog.Free;
  SqlReader.Free;
  SqlIndex.Free;
  ServerReader.Free;
  Server.Free;
  ClientReader.Free;
  Client.Free;
  inherited Destroy;
end;

constructor TRun.Create(pC: TClones; const pTarget: string);
begin
  inherited Create;
  Anchor:= pC.Resolver.ResolveTraceAnchor(pTarget);
  Ctx:= TTraceContext.Create;
  Ctx.Table:= Anchor.Table;
  Ctx.Column:= Anchor.Column;
  Ctx.TableColumn:= Anchor.TableColumn;
  Ctx.DataSet:= Anchor.DataSet;
  Ctx.HasDataSet:= Anchor.HasDataSet;
  Ctx.Likes:= BoundaryLikes(BOUNDARY);
  Ctx.NearIndex:= NEAR_NAME;
  Ctx.FarIndex:= FAR_NAME;
  Wiring:= pC.Resolver.EventWiring(Anchor.DataSet);
end;

destructor TRun.Destroy;
begin
  Ctx.Free;
  Anchor.Free;
  inherited Destroy;
end;

function LineOwner(pItem: TTraceItem; pWith: Boolean): string;
begin
  Result:= if pWith then '|' + IntToStr(pItem.Line) + '|' + IntToStr(pItem.Owner) else '';
end;

{ the harvest's rows: one per item, one per child line (Kind|Actor|Text|Grade|Anchor|Routine|Note|Ask[|Line|Owner]) }
function Rows(const pItems: TArray<TTraceItem>; pWithLineOwner: Boolean = True): TArray<string>;
begin
  var L:= TList<string>.Create;
  try
    for var I in pItems do
    begin
      L.Add(string.Join('|', [I.Kind, I.Actor, I.Text, I.Grade, I.Anchor, I.Routine, I.Note, I.Ask]) + LineOwner(I, pWithLineOwner));
      for var C in I.Children do
        if C.Kind = 'cond' then
          L.Add('  COND|' + string.Join('|', [C.Keyword, C.Condition, C.Anchor, C.Note, C.Ask, C.Routine]))
        else
          L.Add('  FACET|' + string.Join('|', [C.Head, C.Text, C.Anchor, C.Note]));
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function CondRows(pConds: TObjectList<TTraceChild>): string;
begin
  var Parts: TArray<string>:= [];
  for var C in pConds do
    Parts:= Parts + ['  COND|' + string.Join('|', [C.Keyword, C.Condition, C.Anchor, C.Note, C.Ask, C.Routine])];
  Result:= string.Join(sLineBreak, Parts);
end;

procedure AreRows(const pExpected: array of string; const pActual: TArray<string>; const pWhat: string);
begin
  for var K:= 0 to High(pExpected) do
    if K <= High(pActual) then
      Assert.AreEqual(pExpected[K], pActual[K], pWhat + ' row ' + IntToStr(K));
  Assert.AreEqual(Integer(Length(pExpected)), Integer(Length(pActual)), pWhat + ' row count');
end;

function FactsRow(pF: TRoutineFacts; pFull: Boolean): string;
begin
  Result:= Format('%d|%s|%d|%d|refs=%d|lits=%d', [pF.Id, pF.Short, pF.ImplStart, pF.ImplEnd, pF.Refs.Count, pF.Lits.Count]);
  if pFull then
    Result:= Result + Format('|pid=%d|decl=%d|sqlr=%s|sqlw=%s', [pF.Pid, pF.Decl, pF.SqlReads, pF.SqlWrites]);
end;

function FirstCrossing(pItems: TObjectList<TTraceItem>): TTraceItem;
begin
  Result:= nil;
  for var I in pItems do
    if I.Kind = 'crosses' then
      Exit(I);
end;

function SenderId(pC: TClones; const pQName: string): Integer;
begin
  var Q:= pC.Client.Query(Format('SELECT id FROM symbols WHERE qualified_name = ''%s'' AND impl_start_line > 0', [TChartsIndex.SqlText(pQName)]));
  try
    Result:= Q[0].I('id');
  finally
    Q.Free;
  end;
end;

function TracedText(const pT: TTracedRoutes): string;
begin
  var S: TArray<string>:= [];
  for var X in pT.Senders do
    S:= S + [IntToStr(X.Owner) + ':' + IntToStr(X.Line)];
  var C: TArray<string>:= [];
  for var Id in pT.Callers do
    C:= C + [IntToStr(Id)];
  Result:= 'senders=' + string.Join(',', S) + ' callers=' + string.Join(',', C);
end;

{ the handler walk of the preferred wiring (Emit-RoundTrip.ps1:180-181) }
function HandlerWalk(pC: TClones; pRun: TRun): TWalkResult;
begin
  var Visited:= TDictionary<Integer, Byte>.Create;
  try
    Result:= pC.Walker.WalkRoutine(tsClient, pRun.Wiring[0].HandlerId, WALK_DEPTH, Visited, pRun.Ctx);
  finally
    Visited.Free;
  end;
end;

procedure TCoreTraceWalkTests.HandlerWalkMatchesPowerShell;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_OPERAT);
    try
      Assert.AreEqual(FACTS_HANDLER, FactsRow(C.Walker.RoutineFacts(tsClient, Run.Wiring[0].HandlerId, Run.Ctx.Likes), True));
      Assert.AreEqual(FACTS_SENDER, FactsRow(C.Walker.RoutineFacts(tsClient, SenderId(C, SENDER_OPERAT), Run.Ctx.Likes), False));
      var W:= HandlerWalk(C, Run);
      try
        AreRows(WALK_OPERAT, Rows(W.Items.ToArray), 'walk');
        Assert.AreEqual(COND_OPERAT, CondRows(W.Conds));
        Assert.AreEqual(Integer(0), Integer(Run.Ctx.Seen.Count), 'the client walk shows no FIB$ literal');
        Assert.AreEqual('cmdDelta', FirstCrossing(W.Items).Command);
      finally
        W.Free;
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceWalkTests.ServerHandlingRoutesCmdDelta;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_OPERAT);
    try
      var S:= C.Walker.ServerHandling('cmdDelta', Run.Ctx, WALK_DEPTH);
      try
        Assert.AreEqual(Integer(SERVER_ITEMS_OPERAT), Integer(S.Items.Count));
        AreRows(SERVER_OPERAT, Rows(S.Items.ToArray), 'server');
        Assert.AreEqual(RESPONSES_WRITE, string.Join(',', S.Responses));
        Assert.IsTrue(S.HasContract);
        Assert.AreEqual(CONTRACT_DELTA, S.ContractText + '|' + S.ContractAnchor);
        Assert.IsTrue(S.Walked);
        Assert.IsNull(S.Stop);
      finally
        S.Free;
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceWalkTests.WriteDatabaseStepsStopOnTheStatement;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_OPERAT);
    try
      var S:= C.Walker.ServerHandling('cmdDelta', Run.Ctx, WALK_DEPTH);
      try
        var D:= C.Walker.DatabaseSteps(S.Items.ToArray, Run.Ctx, 'write');
        try
          AreRows(DBW_OPERAT, Rows(D.Items.ToArray), 'database write');
          Assert.IsNull(D.After, 'a write has no After');
        finally
          D.Free;
        end;
      finally
        S.Free;
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceWalkTests.FillRoutesOfFmtOperation;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_OPERAT);
    try
      var R:= C.Walker.FillRoutes(Run.Anchor.DataSet, Run.Ctx, WALK_DEPTH);
      try
        var Got: TArray<string>:= [];
        for var X in R do
          Got:= Got + [Format('%d|%s|%d|%s|%s|%d|%s|items=%d|conds=%d', [X.Line, X.Routine, X.TargetId, X.TargetShort,
            ExtractFileName(X.TargetPath), X.TargetImpl, X.Lits, X.Walk.Items.Count, X.Walk.Conds.Count])];
        AreRows(ROUTES_OPERAT, Got, 'routes');
        AreRows(ROUTE0_OPERAT, Rows(R[0].Walk.Items.ToArray), 'route 0 walk');
        Assert.AreEqual(ROUTE0_COND, CondRows(R[0].Walk.Conds));
        Assert.AreNotSame(Run.Ctx, R[0].Ctx, 'each route walks with its own context');
      finally
        R.Free;
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceWalkTests.ReadSelectStopIsAssembledHere;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_OPERAT);
    try
      var R:= C.Walker.FillRoutes(Run.Anchor.DataSet, Run.Ctx, WALK_DEPTH);
      try
        var X:= FirstCrossing(R[0].Walk.Items);
        Assert.AreEqual('cmdTableLoad', X.Command);
        var S:= C.Walker.ServerHandling(X.Command, R[0].Ctx, WALK_DEPTH);
        try
          Assert.AreEqual(Integer(READ_SERVER_ITEMS), Integer(S.Items.Count));
          Assert.AreEqual(RESPONSES_READ, string.Join(',', S.Responses));
          Assert.AreEqual(CONTRACT_LOAD, S.ContractText + '|' + S.ContractAnchor);
          var D:= C.Walker.DatabaseSteps(S.Items.ToArray, R[0].Ctx, 'read');
          try
            AreRows(DBR_OPERAT, Rows(D.Items.ToArray), 'database read');
            Assert.IsNotNull(D.After, 'the select stop carries the RUNS step');
            Assert.AreEqual(AFTER_ROW, D.After.Text + '|' + D.After.Anchor);
            Assert.AreEqual(Integer(AFTER_INDEX), Integer(S.Items.IndexOf(D.After)), 'After is a server item, by reference');
          finally
            D.Free;
          end;
        finally
          S.Free;
        end;
      finally
        R.Free;
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

function SkipIds(const pT: TTracedRoutes; const pWiring: TArray<TEventWiring>): TArray<Integer>;
begin
  var L:= TList<Integer>.Create;
  try
    for var Id in pT.Callers do
      if not L.Contains(Id) then
        L.Add(Id);
    for var W in pWiring do
      if not L.Contains(W.HandlerId) then
        L.Add(W.HandlerId);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

procedure TCoreTraceWalkTests.AlsoRoutesSkipTheTraced;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_OPERAT);
    try
      var W:= HandlerWalk(C, Run);
      var R:= C.Walker.FillRoutes(Run.Anchor.DataSet, Run.Ctx, WALK_DEPTH);
      try
        var T:= TTraceWalker.TracedRouteIds([W.Items.ToArray, R[0].Walk.Items.ToArray]);
        Assert.AreEqual(TRACED_OPERAT, TracedText(T));
        var A:= C.Walker.AlsoRoutes(T.Senders, SkipIds(T, Run.Wiring), Run.Ctx);
        try
          AreRows(ALSO_OPERAT, Rows(A.ToArray, False), 'also');
        finally
          A.Free;
        end;
      finally
        R.Free;
        W.Free;
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceWalkTests.FtrsAnchorWalksTheOtherSender;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_FTRS);
    try
      var W:= HandlerWalk(C, Run);
      var S:= C.Walker.ServerHandling(FirstCrossing(W.Items).Command, Run.Ctx, WALK_DEPTH);
      var R:= C.Walker.FillRoutes(Run.Anchor.DataSet, Run.Ctx, WALK_DEPTH);
      try
        AreRows(WALK_FTRS, Rows(W.Items.ToArray), 'walk');
        Assert.AreEqual(COND_FTRS, CondRows(W.Conds));
        Assert.AreEqual(Integer(SERVER_ITEMS_FTRS), Integer(S.Items.Count), 'the MSCLIST branches are walked, the others omitted');
        Assert.AreEqual(Integer(ROUTES_FTRS), Integer(R.Count));
        var T:= TTraceWalker.TracedRouteIds([W.Items.ToArray, R[0].Walk.Items.ToArray]);
        Assert.AreEqual(TRACED_FTRS, TracedText(T));
        var A:= C.Walker.AlsoRoutes(T.Senders, SkipIds(T, Run.Wiring), Run.Ctx);
        try
          Assert.AreEqual(Integer(ALSO_FTRS), Integer(A.Count));
        finally
          A.Free;
        end;
      finally
        R.Free;
        S.Free;
        W.Free;
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

{ a copy of pPath with one trailing blank on its first line: same text, another sha }
function WriteStaleCopy(const pPath: string): string;
begin
  var B:= TFile.ReadAllBytes(pPath);
  var K:= 0;
  while (K < Length(B)) and (B[K] <> BYTE_LF) do
    Inc(K);
  var Outp: TBytes;
  SetLength(Outp, Length(B) + 1);
  if K > 0 then
    Move(B[0], Outp[0], K);
  Outp[K]:= BYTE_SPACE;
  if Length(B) > K then
    Move(B[K], Outp[K + 1], Length(B) - K);
  Result:= TPath.Combine(TPath.GetTempPath, 'dl-walk-stale-' + ExtractFileName(pPath));
  TFile.WriteAllBytes(Result, Outp);
end;

procedure TCoreTraceWalkTests.StaleFileRefusesByName;
begin
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    var Run:= TRun.Create(C, CTL_OPERAT);
    try
      var F:= C.Walker.RoutineFacts(tsClient, Run.Wiring[0].HandlerId, Run.Ctx.Likes);
      if not TFile.Exists(F.Path) then
      begin
        Assert.Pass('the ORM3 source is missing');
        Exit;
      end;
      var StaleCopy:= WriteStaleCopy(F.Path);
      try
        C.ClientReader.AddOverride(F.Path, StaleCopy);
        var Msg:= '';
        try
          HandlerWalk(C, Run).Free;
        except
          on E: EChartsTrace do
            Msg:= E.Message;
        end;
        Assert.AreEqual(STALE_TEXT, Msg);
      finally
        TFile.Delete(StaleCopy);
      end;
    finally
      Run.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TCoreTraceWalkTests.IndexFactsAndBoundaryLikes;
begin
  Assert.AreEqual(LIKES, BoundaryLikes(BOUNDARY));
  Assert.AreEqual('sfBinary', StreamFormat('    FMTOperation.SaveToStream(MS, sfBinary);'));
  Assert.AreEqual('', StreamFormat('    FMTOperation.SaveToStream(MS);'));
  Assert.AreEqual('', StreamFormat('    X.SaveToStream(MS, Fmt(1));'));
  var C:= TClones.Open;
  if C = nil then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  try
    Assert.AreEqual(Integer(FILES_CLIENT), C.Walker.FilesCount(tsClient));
    Assert.AreEqual(Integer(FILES_SERVER), C.Walker.FilesCount(tsServer));
    Assert.AreEqual(STAMPS, string.Join('/', [TTraceWalker.IndexStamp(C.Client), TTraceWalker.IndexStamp(C.Server),
      TTraceWalker.IndexStamp(C.SqlIndex)]));
  finally
    C.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreTraceWalkTests);

end.
