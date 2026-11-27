unit DRagLint.V156.TAINTEXC;

{ Wave v156 (1.56.0-alpha) lane FA-2 -- taint through exceptions (on the B4 rows of
  DRagLint.Index.DataFlowExc). NOT a rule provider of DRagLint.V151.Dispatch: it emits under the
  taint ids of DRagLint.Lint.TaintRules, which calls Check through ONE hook line (lane TAINT-1).
  Scaffold created by lane FRAME-1; lane FA-2 owns this unit and DRagLint.V156.TAINTEXC.Support.

  HOW IT WORKS (three steps, all read-only):
  1. HANDLER SIDE. Every data_flows row of a scope file whose source is an exception object
     (src_kind 'except': `on E: T do ... E.Message ...`) and whose destination has the SHAPE of a
     catalogued sink (name, kind, argument position, receiver suffix) is a handler hit.
  2. JOIN. A raise row (dst_kind 'raise', dst_name = the raised class, dst_index = the constructor
     argument) is joined to a hit when the handler catches that class (TTaintExcJoin.Catches) and
     the raising routine is the handler's routine or one it calls, transitively
     (TTaintExcJoin.Reachable). The extractor does not join the two sides.
  3. RAISE SIDE. Whether the raised constructor argument is tainted is answered by the ordinary
     walker: TTaintRules.Check runs once more with the exception constructor calls of the joined
     raise sites as its only sinks, so sources, propagators, sanitizers, categories and the
     interprocedural walk are exactly those of the taint rules. A finding of that run at a joined
     constructor call makes one finding at the handler's sink.

  LIMITS (reported, not hidden): the handler side is one routine deep -- the exception value must
  reach the sink inside the handler's routine, directly or through locals, not through a call;
  a sink entry with a "type" is matched by shape only there and reported weak; `raise;` and
  `raise E` (no constructor argument) are not followed; run-time dispatched calls are not followed
  by the reachability search.
  All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Taint that reaches a sink through raise / except: the part of the taint check that
  /// reads the exception data flows.</summary>
  /// <remarks>Stateless between runs except for the one-shot configuration of UseConfig; class
  /// methods only. Not thread-safe (one store connection).</remarks>
  TV156TaintExc = class
  public
    /// <summary>Hands the merged taint configuration of the running check to the next Check call.</summary>
    /// <param name="ACfg">A DRagLint.Lint.TaintRules.TTaintConfig (untyped: that unit uses this one
    /// in its interface, so the type cannot be named here). Copied; consumed by the next Check.</param>
    /// <remarks>Without it Check loads the built-in catalogues only (rules\taint-*.json beside the
    /// exe): entries of a lint config's `taint` object are then unknown to the exception check.</remarks>
    class procedure UseConfig(const ACfg); static;
    /// <summary>Findings for tainted values carried by an exception object into a handler's sink.</summary>
    /// <param name="AStore">The project index; nil gives no findings.</param>
    /// <param name="ALibStore">The library index; may be nil.</param>
    /// <param name="AScopeFileIds">The files whose handler sinks are reported; empty = none (as the
    /// ordinary walk). Raise sites are searched in every routine a handler's routine reaches.</param>
    /// <returns>ONE finding per handler sink site and rule under the existing taint rule ids, its
    /// message starting with TAINT_MSG_PREFIX and its Path running source -> raise -> handler ->
    /// sink; nil when none, when the store has no data_flows, or when called from its own inner walk.</returns>
    /// <remarks>Read-only. Called once per TTaintRules.Check run, after the ordinary walk; runs
    /// TTaintRules.Check once itself (re-entrancy is cut by a guard) only when a handler hit has a
    /// joined raise site.</remarks>
    class function Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , FireDAC.Stan.Param // dl:unit FireDAC.Stan.Param accepted -- TFDParam.AsString is inline: dcc expands it only with the declaring unit in uses (H2443)
  , FireDAC.Comp.Client
  , DRagLint.Storage.SQLite
  , DRagLint.Lint.TaintRules  // dl:ok circular-uses@aecf -- REVIEWED 2026-11-27: implementation-only cycle by design (v156 plan settlement, PLAN-HPS 7): TaintRules' interface calls this unit through ONE hook line; this unit runs TTaintRules.Check for the raise side and reads TTaintConfig; re-entrancy is cut by GInside
  , DRagLint.V156.TAINTEXC.Support
  ;

const
  KIND_CALL      = 'call';
  KIND_WRITE     = 'write';
  SEV_ERROR      = 'error';
  SEV_WARNING    = 'warning';
  SEV_INFO       = 'info';
  WEAK_MARK      = ', weak';
  NOTE_RAISE     = 'raise ';
  NOTE_CAUGHT    = 'caught: on ';
  NOTE_CAUGHT_ANY= 'caught: except';
  NOTE_SINK      = 'sink ';
  SQL_HANDLERS   = 'SELECT DISTINCT symbol_id FROM data_flows WHERE src_kind = :p0 AND dst_kind IN (:p1, :p2)';
  SQL_RAISERS    = 'SELECT DISTINCT symbol_id FROM data_flows WHERE dst_kind = :p0 AND dst_index >= 0';
  SQL_PARAM      = 'p';

type
  { One exception value reaching a catalogued sink shape inside a handler's routine. }
  THandlerHit = record
    Routine: TSymbol;
    Row    : TDataFlowRow;
    Rule   : string;
    Cwe    : string;
    Weak   : Boolean;
  end;

  { One raise site a handler hit is joined to; SiteKey names the constructor call the inner walk reports. }
  TRaiseLink = record
    Hit    : Integer;
    Raised : string;
    SiteKey: string;
  end;

  { One finding of the inner walk at a joined raise site, with the class raised there. }
  TRaiseHit = record
    Finding: TLintFinding;
    Raised : string;
  end;

  TExcRun = class
  private
    FStore   : ISymbolStore;
    FLibStore: ISymbolStore;
    FCfg     : TTaintConfig;
    FJoin    : TTaintExcJoin;
    FRows    : TDictionary<Int64, TArray<TDataFlowRow>>;
    FHits    : TList<THandlerHit>;
    FLinks   : TList<TRaiseLink>;
    FSinks   : TList<TTaintSinkEntry>;
    FSinkKeys: TDictionary<string, Boolean>;
    FFiles   : TDictionary<Int64, Boolean>;
    function  RoutineIds(const ASql: string; const AKinds: TArray<string>): TArray<Int64>;
    function  RowsOf(ARoutineId: Int64): TArray<TDataFlowRow>;
    procedure CollectHits(const AScopeFileIds: TArray<Int64>);
    procedure AddHit(const ARoutine: TSymbol; const ARow: TDataFlowRow; const AEntry: TTaintSinkEntry);
    procedure CollectLinks(const ARaisers: TArray<Int64>);
    procedure AddSink(const AArg: TDataFlowRow; const ARaised, ARule: string);
  public
    constructor Create(const AStore, ALibStore: ISymbolStore; const ACfg: TTaintConfig);
    destructor Destroy; override;
    function Execute(const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>;
  end;

var
  GInside : Boolean = False;
  GCfg    : TTaintConfig;
  GCfgSet : Boolean = False;

function SiteKeyOf(AFileId: Int64; ALine, ACol: Integer; const ARule: string): string;
begin
  Result:= Format('%d|%d|%d|%s', [AFileId, ALine, ACol, LowerCase(ARule)]);
end;

function DropSeverity(const ASev: string): string;
begin
  Result:= if SameText(ASev, SEV_ERROR) then SEV_WARNING else SEV_INFO;
end;

{ True when inner finding A is the better one to name the message: certain before weak, then
  the shorter path. }
function Better(const A, B: TLintFinding): Boolean;
var
  WeakA, WeakB: Boolean;
begin
  WeakA:= ContainsText(A.Message, WEAK_MARK);
  WeakB:= ContainsText(B.Message, WEAK_MARK);
  Result:= if WeakA <> WeakB then WeakB else Length(A.Path) < Length(B.Path);
end;

{ True when two rows of one routine name the same on clause feeding the same sink site. }
function SameFlow(const A, B: TDataFlowRow): Boolean;
begin
  Result:= (A.FileId = B.FileId) and (A.DstLine = B.DstLine) and (A.DstCol = B.DstCol);
  Result:= Result and (A.SrcLine = B.SrcLine) and (A.SrcCol = B.SrcCol);
end;

function SinkShapeMatches(const AEntry: TTaintSinkEntry; const ARow: TDataFlowRow): Boolean;
var
  KindOk: Boolean;
  Idx   : Integer;
begin
  if SameText(AEntry.Kind, KIND_WRITE) then KindOk:= ARow.DstKind = DF_DST_WRITE
  else
  begin
    KindOk:= False;
    if ARow.DstKind = DF_DST_ARG then
      for Idx in AEntry.Args do KindOk:= KindOk or (Idx = ARow.DstIndex);
  end;
  Result:= KindOk and SameText(AEntry.Name, ARow.DstName)
           and ((AEntry.ReceiverSuffix = '') or EndsText(AEntry.ReceiverSuffix, ARow.DstReceiver));
end;

{ The ONE finding of a handler sink site and rule. AInner = the inner walk's findings at the
  joined raise sites, not empty, AInner[0] the best (certain before weak, then the shorter path). }
function HandlerFinding(const AFilePath: string; AWeakDrop: Boolean; const AHit: THandlerHit; const AInner: TArray<TRaiseHit>): TLintFinding;
var
  Best   : TLintFinding;
  Weak   : Boolean;
  Caught : TLintLocation;
  Sink   : TLintLocation;
  Tail   : TArray<TLintLocation>;
  Path   : TArray<TLintLocation>;
  One    : TRaiseHit;
begin
  Best:= AInner[0].Finding;
  Weak:= AHit.Weak or ContainsText(Best.Message, WEAK_MARK);
  Result:= Default(TLintFinding);
  Result.RuleId    := AHit.Rule;
  Result.FileId    := AHit.Row.FileId;
  Result.FilePath  := AFilePath;
  Result.StartLine := AHit.Row.DstLine;
  Result.StartCol  := AHit.Row.DstCol;
  Result.EndLine   := AHit.Row.DstLine;
  Result.EndCol    := AHit.Row.DstCol + Length(AHit.Row.DstName);
  Result.SymbolName:= AHit.Routine.Name;
  Result.Severity  := Best.Severity;
  { the inner walk already dropped a weak raise side; a weak handler sink drops it once, too }
  if AHit.Weak and AWeakDrop and not ContainsText(Best.Message, WEAK_MARK) then
    Result.Severity:= DropSeverity(Result.Severity);
  Caught:= Default(TLintLocation);
  Caught.FilePath:= Result.FilePath;
  Caught.Line    := AHit.Row.SrcLine;
  Caught.Col     := AHit.Row.SrcCol;
  Caught.Routine := AHit.Routine.QualifiedName;
  Caught.Note    := if AHit.Row.SrcName = '' then NOTE_CAUGHT_ANY else NOTE_CAUGHT + AHit.Row.SrcName;
  Sink:= Caught;
  Sink.Line:= AHit.Row.DstLine;
  Sink.Col := AHit.Row.DstCol;
  Sink.Note:= NOTE_SINK + AHit.Row.DstName;
  Tail:= [Caught, Sink];
  for One in AInner do
  begin
    { the inner path ends at the constructor call: that hop is the raise }
    Path:= Copy(One.Finding.Path);
    if Path <> nil then Path[High(Path)].Note:= NOTE_RAISE + One.Raised;
    Path:= Path + Tail;
    if Result.Path = nil then Result.Path:= Path;
    if Length(AInner) > 1 then Result.Paths:= Result.Paths + [Path];
  end;
  Result.Message:= Format('%s %s through exception %s: raised in %s (line %d), caught in %s (line %d%s)',
    [TAINT_MSG_PREFIX, AHit.Row.DstName, AInner[0].Raised, Best.SymbolName, Best.StartLine, AHit.Routine.Name,
     AHit.Row.SrcLine, IfThen(Weak, WEAK_MARK)]);
  if AHit.Cwe <> '' then Result.Message:= Result.Message + ' -- ' + AHit.Cwe;
  if Length(AInner) > 1 then Result.Message:= Result.Message + Format(' (%d raise sites)', [Length(AInner)]);
end;

{ ---- TExcRun -------------------------------------------------------------------- }

constructor TExcRun.Create(const AStore, ALibStore: ISymbolStore; const ACfg: TTaintConfig);
begin
  inherited Create;
  FStore   := AStore;
  FLibStore:= ALibStore;
  FCfg     := ACfg;
  FJoin    := TTaintExcJoin.Create(AStore, ALibStore);
  FRows    := TDictionary<Int64, TArray<TDataFlowRow>>.Create;
  FHits    := TList<THandlerHit>.Create;
  FLinks   := TList<TRaiseLink>.Create;
  FSinks   := TList<TTaintSinkEntry>.Create;
  FSinkKeys:= TDictionary<string, Boolean>.Create;
  FFiles   := TDictionary<Int64, Boolean>.Create;
end;

destructor TExcRun.Destroy;
begin
  FFiles.Free;
  FSinkKeys.Free;
  FSinks.Free;
  FLinks.Free;
  FHits.Free;
  FRows.Free;
  FJoin.Free;
  inherited;
end;

function TExcRun.RoutineIds(const ASql: string; const AKinds: TArray<string>): TArray<Int64>;
var
  Q: TFDQuery;
  I: Integer;
begin
  Result:= nil;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= TSQLiteSymbolStore(FStore).GetConnection;
    Q.SQL.Text  := ASql;
    for I:= 0 to High(AKinds) do Q.ParamByName(SQL_PARAM + IntToStr(I)).AsString:= AKinds[I];
    Q.Open;
    while not Q.Eof do
    begin
      Result:= Result + [Q.Fields[0].AsLargeInt];
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TExcRun.RowsOf(ARoutineId: Int64): TArray<TDataFlowRow>;
begin
  if FRows.TryGetValue(ARoutineId, Result) then Exit;
  Result:= FStore.GetDataFlowsOf(ARoutineId, '');
  FRows.Add(ARoutineId, Result);
end;

procedure TExcRun.AddHit(const ARoutine: TSymbol; const ARow: TDataFlowRow; const AEntry: TTaintSinkEntry);
var
  Hit: THandlerHit;
  I  : Integer;
begin
  { one hit per (sink site, rule, on clause): a certain entry wins over a typed (weak) one }
  for I:= 0 to FHits.Count - 1 do
  begin
    Hit:= FHits[I];
    if SameFlow(Hit.Row, ARow) and SameText(Hit.Rule, AEntry.Rule) then
    begin
      Hit.Weak:= Hit.Weak and (AEntry.TypeName <> '');
      FHits[I]:= Hit;
      Exit;
    end;
  end;
  Hit:= Default(THandlerHit);
  Hit.Routine:= ARoutine;
  Hit.Row    := ARow;
  Hit.Rule   := AEntry.Rule;
  Hit.Cwe    := AEntry.Cwe;
  Hit.Weak   := AEntry.TypeName <> '';
  FHits.Add(Hit);
end;

procedure TExcRun.CollectHits(const AScopeFileIds: TArray<Int64>);
var
  Scope: TDictionary<Int64, Boolean>;
  Fid  : Int64;
  Id   : Int64;
  Row  : TDataFlowRow;
  Entry: TTaintSinkEntry;
  S    : TSymbol;
begin
  Scope:= TDictionary<Int64, Boolean>.Create;
  try
    for Fid in AScopeFileIds do Scope.AddOrSetValue(Fid, True);
    for Id in RoutineIds(SQL_HANDLERS, [DF_SRC_EXCEPT, DF_DST_ARG, DF_DST_WRITE]) do
    begin
      S:= Default(TSymbol);
      for Row in RowsOf(Id) do
      begin
        if (Row.SrcKind <> DF_SRC_EXCEPT) or not Scope.ContainsKey(Row.FileId) then Continue;
        for Entry in FCfg.Sinks do
        begin
          if not SinkShapeMatches(Entry, Row) then Continue;
          if S.Id = 0 then S:= FStore.GetSymbolById(Id);
          AddHit(S, Row, Entry);
        end;
      end;
    end;
  finally
    Scope.Free;
  end;
end;

procedure TExcRun.AddSink(const AArg: TDataFlowRow; const ARaised, ARule: string);
var
  Entry: TTaintSinkEntry;
  Typed: Boolean;
  Key  : string;
begin
  { two shapes per constructor call: the untyped one matches an inherited (library or
    unresolved) constructor, the typed one a constructor the project class declares }
  for Typed in [False, True] do
  begin
    Key:= LowerCase(Format('%s|%d|%s|%s', [AArg.DstName, AArg.DstIndex, ARule, IfThen(Typed, ARaised)]));
    if FSinkKeys.ContainsKey(Key) then Continue;
    FSinkKeys.Add(Key, True);
    Entry:= Default(TTaintSinkEntry);
    Entry.Id      := 'taintexc:' + Key;
    Entry.Rule    := ARule;
    Entry.Name    := AArg.DstName;
    Entry.Kind    := KIND_CALL;
    Entry.Args    := [AArg.DstIndex];
    Entry.TypeName:= IfThen(Typed, ARaised);
    FSinks.Add(Entry);
  end;
end;

procedure TExcRun.CollectLinks(const ARaisers: TArray<Int64>);
var
  Raisers: TDictionary<Int64, Boolean>;
  Id     : Int64;
  I      : Integer;
  Hit    : THandlerHit;
  Rows   : TArray<TDataFlowRow>;
  Row    : TDataFlowRow;
  Arg    : TDataFlowRow;
  Link   : TRaiseLink;
begin
  Raisers:= TDictionary<Int64, Boolean>.Create;
  try
    for Id in ARaisers do Raisers.AddOrSetValue(Id, True);
    for I:= 0 to FHits.Count - 1 do
    begin
      Hit:= FHits[I];
      for Id in FJoin.Reachable(Hit.Routine.Id) do
      begin
        if not Raisers.ContainsKey(Id) then Continue;
        Rows:= RowsOf(Id);
        for Row in Rows do
        begin
          if (Row.DstKind <> DF_DST_RAISE) or (Row.DstIndex < 0) then Continue;
          if not FJoin.Catches(Hit.Row.SrcName, Row.DstName, Row.FileId) then Continue;
          if not TTaintExcJoin.CtorArgRow(Row, Rows, Arg) then Continue;
          Link:= Default(TRaiseLink);
          Link.Hit    := I;
          Link.Raised := Row.DstName;
          Link.SiteKey:= SiteKeyOf(Arg.FileId, Arg.DstLine, Arg.DstCol, Hit.Rule);
          FLinks.Add(Link);
          FFiles.AddOrSetValue(Arg.FileId, True);
          AddSink(Arg, Row.DstName, Hit.Rule);
        end;
      end;
    end;
  finally
    Raisers.Free;
  end;
end;

function TExcRun.Execute(const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>;
var
  Cfg    : TTaintConfig;
  Stats  : TTaintStats;
  BySite : TDictionary<string, TLintFinding>;
  Seen   : TDictionary<string, Boolean>;
  F      : TLintFinding;
  Link   : TRaiseLink;
  Inner  : TArray<TRaiseHit>;
  One    : TRaiseHit;
  I, At  : Integer;
begin
  Result:= nil;
  CollectHits(AScopeFileIds);
  if FHits.Count = 0 then Exit;
  CollectLinks(RoutineIds(SQL_RAISERS, [DF_DST_RAISE]));
  if FLinks.Count = 0 then Exit;
  Cfg:= FCfg;
  Cfg.Sinks:= FSinks.ToArray;
  BySite:= TDictionary<string, TLintFinding>.Create;
  Seen  := TDictionary<string, Boolean>.Create;
  try
    for F in TTaintRules.Check(FStore, FLibStore, FFiles.Keys.ToArray, Cfg, Stats) do
      BySite.AddOrSetValue(SiteKeyOf(F.FileId, F.StartLine, F.StartCol, F.RuleId), F);
    for I:= 0 to FHits.Count - 1 do
    begin
      Inner:= nil;
      Seen.Clear;
      for Link in FLinks do
      begin
        if (Link.Hit <> I) or Seen.ContainsKey(Link.SiteKey) or not BySite.TryGetValue(Link.SiteKey, F) then Continue;
        Seen.Add(Link.SiteKey, True);
        { keep the best first: certain before weak, then the shorter path }
        One.Finding:= F;
        One.Raised := Link.Raised;
        At:= if (Inner <> nil) and Better(F, Inner[0].Finding) then 0 else Length(Inner);
        Insert(One, Inner, At);
      end;
      if Inner <> nil then
        Result:= Result + [HandlerFinding(FStore.GetFilePath(FHits[I].Row.FileId), FCfg.WeakSeverityDrop, FHits[I], Inner)];
    end;
  finally
    Seen.Free;
    BySite.Free;
  end;
end;

{ ---- TV156TaintExc -------------------------------------------------------------- }

class procedure TV156TaintExc.UseConfig(const ACfg);
begin
  GCfg   := TTaintConfig(ACfg);
  GCfgSet:= True;
end;

class function TV156TaintExc.Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>;
var
  Run: TExcRun;
  Cfg: TTaintConfig;
begin
  Result:= nil;
  { GInside: the inner walk of step 3 calls this hook again }
  if GInside or (AStore = nil) or (AScopeFileIds = nil) then Exit;
  if (AStore is not TSQLiteSymbolStore) or not AStore.HasDataFlows then Exit;
  Cfg:= if GCfgSet then GCfg else TTaintRules.LoadConfig('', nil);
  GCfgSet:= False;
  GInside:= True;
  try
    Run:= TExcRun.Create(AStore, ALibStore, Cfg);
    try
      Result:= Run.Execute(AScopeFileIds);
    finally
      Run.Free;
    end;
  finally
    GInside:= False;
  end;
end;

end.
