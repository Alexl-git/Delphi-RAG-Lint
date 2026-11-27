unit DRagLint.V156.TAINTEXC.Support;

{ Wave v156 lane FA-2 -- helpers of DRagLint.V156.TAINTEXC (private to the lane): the join of a
  raise row (data_flows dst_kind 'raise') to a handler source (src_kind 'except'). The extractor
  (DRagLint.Index.DataFlowExc) writes the two sides and does NOT join them; this unit joins them
  by exception class (name or ancestry) and by reachability over the resolved call edges.
  All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM. }

interface

uses
  System.Generics.Collections
  , DRagLint.Core.Model  // dl:ok uses-global-census -- the named constants are the whole contract this unit draws; the unit pair travels together
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Call-edge hops followed from a handler's routine when looking for the routines whose
  /// raise can reach it.</summary>
  TAINTEXC_MAX_DEPTH = 12;
  /// <summary>Routines visited per handler routine before the search stops (the answer is then
  /// short, never wrong).</summary>
  TAINTEXC_MAX_NODES = 4000;
  /// <summary>The root exception class: a handler of it catches every raised class.</summary>
  TAINTEXC_ROOT_CLASS = 'Exception';

type
  /// <summary>Joins raise rows to handler sources: which raised class a handler catches, which
  /// routines a handler's routine can reach, and which ordinary argument row a raise row mirrors.</summary>
  /// <remarks>Owns two caches for one check run; holds the stores by reference. Not thread-safe.</remarks>
  TTaintExcJoin = class
  private
    FStore   : ISymbolStore;
    FLibStore: ISymbolStore;
    FCallees : TDictionary<Int64, TArray<Int64>>;
    FCatches : TDictionary<string, Boolean>;
    function CalleesOf(ARoutineId: Int64): TArray<Int64>;
  public
    /// <summary>Creates the join over one project store and an optional library store.</summary>
    /// <param name="AStore">The project index; not nil.</param>
    /// <param name="ALibStore">The library index (ancestry of library exception classes); may be nil.</param>
    constructor Create(const AStore, ALibStore: ISymbolStore);
    /// <summary>Frees the caches.</summary>
    destructor Destroy; override;
    /// <summary>The last dot-separated segment of a class name ('uX.EProbe' gives 'EProbe').</summary>
    /// <param name="AName">A class name, bare or unit-qualified.</param>
    /// <returns>The leaf name; AName itself when it has no dot.</returns>
    class function LeafOf(const AName: string): string; static;
    /// <summary>True when a handler of class AHandled catches a raise of class ARaised.</summary>
    /// <param name="AHandled">The on-clause class; '' = a bare except / ExceptObject (catches all).</param>
    /// <param name="ARaised">The raised class (raise row dst_name); '' = a re-raise, never joined.</param>
    /// <param name="ARaiseFileId">files.id of the raise site (scope of the ancestry lookup).</param>
    /// <returns>True for the same leaf name (case-insensitive), a handler of the root class, or
    /// ARaised descending from AHandled in the project or the library index.</returns>
    function Catches(const AHandled, ARaised: string; ARaiseFileId: Int64): Boolean;
    /// <summary>The routines whose raise can reach a handler inside routine AFrom: AFrom itself and
    /// every routine it calls, transitively, over the resolved call edges.</summary>
    /// <param name="AFrom">symbols.id of the handler's routine.</param>
    /// <returns>AFrom first, then the callees breadth-first; at most TAINTEXC_MAX_NODES ids and
    /// TAINTEXC_MAX_DEPTH hops. Unresolved and run-time dispatched calls are not followed.</returns>
    function Reachable(AFrom: Int64): TArray<Int64>;
    /// <summary>Finds the ordinary argument row a raise row mirrors: the same source flowing into
    /// the same argument position of the exception constructor call of that raise statement.</summary>
    /// <param name="ARaise">A dst_kind 'raise' row with dst_index >= 0.</param>
    /// <param name="ARows">Every data_flows row of the raising routine.</param>
    /// <param name="AArg">The matching dst_kind 'arg' row; a zeroed row when none.</param>
    /// <returns>True when a row was found.</returns>
    class function CtorArgRow(const ARaise: TDataFlowRow; const ARows: TArray<TDataFlowRow>;
                              out AArg: TDataFlowRow): Boolean; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  ;

constructor TTaintExcJoin.Create(const AStore, ALibStore: ISymbolStore);
begin
  inherited Create;
  FStore   := AStore;
  FLibStore:= ALibStore;
  FCallees := TDictionary<Int64, TArray<Int64>>.Create;
  FCatches := TDictionary<string, Boolean>.Create;
end;

destructor TTaintExcJoin.Destroy;
begin
  FCatches.Free;
  FCallees.Free;
  inherited;
end;

class function TTaintExcJoin.LeafOf(const AName: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', AName);
  Result:= if P > 0 then Copy(AName, P + 1) else AName;
end;

function TTaintExcJoin.Catches(const AHandled, ARaised: string; ARaiseFileId: Int64): Boolean;
var
  H, R, Key: string;
begin
  H:= LeafOf(AHandled);
  R:= LeafOf(ARaised);
  if R = '' then Exit(False);
  if (H = '') or SameText(H, TAINTEXC_ROOT_CLASS) or SameText(H, R) then Exit(True);
  Key:= LowerCase(H + '|' + R) + '|' + IntToStr(ARaiseFileId);
  if FCatches.TryGetValue(Key, Result) then Exit;
  Result:= FStore.IsDescendantOf(R, H, ARaiseFileId);
  if not Result and (FLibStore <> nil) then Result:= FLibStore.IsDescendantOf(R, H, 0);
  FCatches.Add(Key, Result);
end;

function TTaintExcJoin.CalleesOf(ARoutineId: Int64): TArray<Int64>;
var
  Edge: TCallEdge;
begin
  if FCallees.TryGetValue(ARoutineId, Result) then Exit;
  Result:= nil;
  for Edge in FStore.GetCallEdgesFromSymbol(ARoutineId) do
    if Edge.TargetSymbolId > 0 then Result:= Result + [Edge.TargetSymbolId];
  FCallees.Add(ARoutineId, Result);
end;

function TTaintExcJoin.Reachable(AFrom: Int64): TArray<Int64>;
var
  Seen    : TDictionary<Int64, Boolean>;
  Level   : TArray<Int64>;
  Next    : TArray<Int64>;
  Id, Tgt : Int64;
  Depth   : Integer;
begin
  Result:= [AFrom];
  Seen:= TDictionary<Int64, Boolean>.Create;
  try
    Seen.Add(AFrom, True);
    Level:= [AFrom];
    Depth:= 0;
    while (Level <> nil) and (Depth < TAINTEXC_MAX_DEPTH) do
    begin
      Next:= nil;
      for Id in Level do
        for Tgt in CalleesOf(Id) do
        begin
          if Seen.ContainsKey(Tgt) or (Seen.Count >= TAINTEXC_MAX_NODES) then Continue;
          Seen.Add(Tgt, True);
          Next:= Next + [Tgt];
        end;
      Result:= Result + Next;
      Level := Next;
      Inc(Depth);
    end;
  finally
    Seen.Free;
  end;
end;

class function TTaintExcJoin.CtorArgRow(const ARaise: TDataFlowRow; const ARows: TArray<TDataFlowRow>;
                                        out AArg: TDataFlowRow): Boolean;
var
  Row: TDataFlowRow;
begin
  Result:= False;
  AArg  := Default(TDataFlowRow);
  for Row in ARows do
  begin
    if (Row.DstKind <> DF_DST_ARG) or (Row.DstIndex <> ARaise.DstIndex) or (Row.DstLine < ARaise.DstLine) then Continue;
    if (Row.SrcKind <> ARaise.SrcKind) or (Row.SrcLine <> ARaise.SrcLine) or (Row.SrcCol <> ARaise.SrcCol) then Continue;
    if (Row.SrcIndex <> ARaise.SrcIndex) or not SameText(Row.SrcName, ARaise.SrcName) then Continue;
    if not EndsText(ARaise.DstName, Row.DstReceiver) then Continue;
    { the nearest constructor call after the raise keyword is the raised one }
    if Result and ((Row.DstLine > AArg.DstLine) or ((Row.DstLine = AArg.DstLine) and (Row.DstCol >= AArg.DstCol))) then Continue;
    AArg  := Row;
    Result:= True;
  end;
end;

end.
