unit DRagLint.Analysis.DataFlow;

{ Generic monotone data-flow framework (M2). An analysis supplies a lattice
  value type plus Bottom/Boundary/Join/Transfer/Equals and a direction; the
  worklist solver iterates IN/OUT per basic block to a fixpoint. }

interface

uses
  System.Diagnostics,
  System.Generics.Collections,
  DRagLint.Analysis.Cfg;

type
  /// <summary>Iteration direction of a data-flow analysis.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Analysis.DataFlow.pas), declaration (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TDefiniteAssignment.Direction (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TFreedState.Direction (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TLiveness.Direction (DRagLint.Analysis.Flow.Lattices.pas) (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFlowDir = (fdForward, fdBackward);

  /// <summary>A monotone data-flow analysis over a CFG.</summary>
  /// <remarks>
  /// TValue is the lattice element (e.g. a variable bitset). `Join`
  /// must be commutative/associative and monotone; `Transfer` monotone. The
  /// solver terminates because the lattice has finite height.
  /// </remarks>
  IDataFlowAnalysis<TValue> = interface
    /// <summary>Forward (Entry-&gt;Exit) or backward (Exit-&gt;Entry).</summary>
    /// <returns><!-- drag-lint:auto type -->TFlowDir</returns>
    function Direction: TFlowDir;
    /// <summary>The lattice bottom (initial IN/OUT of interior blocks).</summary>
    /// <returns><!-- drag-lint:auto type -->TValue</returns>
    function Bottom: TValue;
    /// <summary>Value at the boundary block (Entry for forward, Exit for
    /// backward) -- e.g. params assigned-on-entry, or vars live-at-exit.</summary>
    /// <returns><!-- drag-lint:auto type -->TValue</returns>
    function Boundary: TValue;
    /// <summary>Meet of two predecessor/successor contributions.</summary>
    /// <param name="A"><!-- drag-lint:auto type -->const TValue</param>
    /// <param name="B"><!-- drag-lint:auto type -->const TValue</param>
    /// <returns><!-- drag-lint:auto type -->TValue</returns>
    function Join(const A, B: TValue): TValue;
    /// <summary>Effect of one block on the in-value.</summary>
    /// <param name="ABlock"><!-- drag-lint:auto type -->const TCfgBlock</param>
    /// <param name="AIn"><!-- drag-lint:auto type -->const TValue</param>
    /// <returns><!-- drag-lint:auto type -->TValue</returns>
    function Transfer(const ABlock: TCfgBlock; const AIn: TValue): TValue;
    /// <summary>Lattice equality (fixpoint test).</summary>
    /// <param name="A"><!-- drag-lint:auto type -->const TValue</param>
    /// <param name="B"><!-- drag-lint:auto type -->const TValue</param>
    /// <returns><!-- drag-lint:auto type -->Boolean</returns>
    function Equals(const A, B: TValue): Boolean;
  end;

  /// <summary>Worklist fixpoint solver over a CFG.</summary>
  TDataFlowSolver<TValue> = class
  public
    /// <summary>Solve AAnalysis over ACfg. Returns False (and leaves AIn/AOut
    /// empty) when ACfg.Skipped. Otherwise AIn[b]/AOut[b] hold the per-block
    /// fixpoint values.</summary>
    /// <param name="ACfg"><!-- drag-lint:auto type -->const TCfg</param>
    /// <param name="AAnalysis"><!-- drag-lint:auto type -->const IDataFlowAnalysis&lt;TValue&gt;</param>
    /// <param name="AIn"><!-- drag-lint:auto type -->out TArray&lt;TValue&gt;</param>
    /// <param name="AOut"><!-- drag-lint:auto type -->out TArray&lt;TValue&gt;</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.Analysis.Cfg.TCfg.BlockCount</para>
    /// <para>Complexity: 17 (cyclomatic, outer body), 64 lines (full implementation)</para>
    /// <para>Mutates: AIn (out), AOut (out)</para>
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.BlockCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Solve(const ACfg: TCfg; const AAnalysis: IDataFlowAnalysis<TValue>;
      out AIn, AOut: TArray<TValue>): Boolean;
  end;

  /// <summary>Worklist counters accumulated across every Solve since process
  /// start, for every lattice instantiation.</summary>
  /// <remarks>
  /// This exists to REFUTE one named hypothesis, not to describe the solver.
  /// INBOX-flowchecker-is-half-of-lint-all measured the two solves at 71.8% of
  /// FlowChecker and proposed seeding the worklist in reverse postorder. That
  /// only pays if blocks are actually RE-visited, so Visits/Blocks is the test.
  /// At ~1.0 the reordering has no iteration to remove and the cost is per-visit
  /// lattice work instead -- which is what TransferSeconds against SolveSeconds
  /// separates. The repo's record on GUESSED flow-perf targets is 100% failure;
  /// this makes the next attempt aimed.
  ///
  /// Accumulation is unconditional -- a handful of increments per block visit
  /// and two timestamp reads per Transfer, which walks an AST -- and only the
  /// PRINTING is gated on DRAGLINT_PROFILE. Same rule as FlowPhaseTicks: the
  /// measured code has to be the shipped code.
  /// </remarks>
  TDataFlowStats = record
    /// <summary>Solve calls that ran. A Skipped CFG exits before counting.</summary>
    Solves: Int64;
    /// <summary>Sum of BlockCount over those solves -- the denominator.</summary>
    Blocks: Int64;
    /// <summary>Blocks dequeued. Never below Blocks: every block is seeded once.</summary>
    Visits: Int64;
    /// <summary>Re-enqueues caused by a changed lattice value; the seeding pass
    /// is excluded. This is the work an iteration-order change could remove.</summary>
    Reenqueues: Int64;
    /// <summary>Join calls -- one per in-edge per visit.</summary>
    Joins: Int64;
    /// <summary>Transfer calls -- one per visit.</summary>
    Transfers: Int64;
    /// <summary>Equals calls -- one per visit.</summary>
    Comparisons: Int64;
    /// <summary>Highest Visits/BlockCount observed in a single solve.</summary>
    WorstRatio: Double;
    /// <summary>BlockCount of the solve that set WorstRatio.</summary>
    WorstBlocks: Int64;
    /// <summary>Seconds inside Solve.</summary>
    SolveSeconds: Double;
    /// <summary>Seconds inside Transfer. A SUBSET of SolveSeconds.</summary>
    TransferSeconds: Double;
  end;

  /// <summary>The same counters, split by the ANALYSIS that drove the solve.</summary>
  /// <remarks>
  /// The aggregate hides the decision. Four lattices share one solver -- the two
  /// that matter are definite-assignment and escape -- and a fix that memoises a
  /// per-block transfer pays in proportion to THAT lattice's own re-visit ratio,
  /// not the pooled one. An aggregate of 2.388 is consistent with one lattice at
  /// 1.0 and another at 6.0, in which case memoising the first buys nothing.
  /// </remarks>
  TDataFlowLatticeStat = record
    /// <summary>Class name of the IDataFlowAnalysis implementation.</summary>
    Name: string;
    /// <summary>Solve calls driven by this analysis.</summary>
    Solves: Int64;
    /// <summary>Sum of BlockCount over them -- the ratio's denominator.</summary>
    Blocks: Int64;
    /// <summary>Blocks dequeued -- the ratio's numerator.</summary>
    Visits: Int64;
    /// <summary>Seconds inside Solve for this analysis.</summary>
    SolveSeconds: Double;
    /// <summary>Seconds inside Transfer for this analysis.</summary>
    TransferSeconds: Double;
  end;

/// <summary>Snapshot of the solver counters accumulated since process start.</summary>
/// <returns>A copy. The counters keep accumulating after the call.</returns>
function DataFlowStats: TDataFlowStats;

/// <summary>The per-analysis split of the same counters, heaviest first.</summary>
/// <returns>One entry per IDataFlowAnalysis class that has run, sorted by
/// SolveSeconds descending. Empty before the first solve.</returns>
function DataFlowLatticeStats: TArray<TDataFlowLatticeStat>;

/// <summary>Fold one finished Solve into the process-wide counters.</summary>
/// <param name="AName">Class name of the analysis that drove the solve.</param>
/// <param name="ABlocks">BlockCount of the CFG just solved.</param>
/// <param name="AVisits">Blocks dequeued during that solve.</param>
/// <param name="AReenqueues">Re-enqueues caused by a changed lattice value.</param>
/// <param name="AJoins">Join calls made.</param>
/// <param name="ATransfers">Transfer calls made.</param>
/// <param name="AComparisons">Equals calls made.</param>
/// <param name="ASolveTicks">Stopwatch ticks spent in Solve.</param>
/// <param name="ATransferTicks">Stopwatch ticks spent inside Transfer.</param>
/// <remarks>
/// DECLARED HERE, NOT IN THE IMPLEMENTATION, AND THAT IS LOAD-BEARING. Solve is
/// a method of a PARAMETERIZED type declared in the interface section, so the
/// compiler forbids it touching an implementation-section symbol (E2506 --
/// "must not use local symbol"). Accumulating straight into the counter
/// variables therefore does not compile, however natural it looks. The counters
/// stay private to the implementation and this is their one door.
/// Not thread-safe, and deliberately so -- see the counter block's remarks.
/// </remarks>
procedure DataFlowRecordSolve(const AName: string; ABlocks, AVisits, AReenqueues,
  AJoins, ATransfers, AComparisons, ASolveTicks, ATransferTicks: Int64);

implementation

{ SOLVER COUNTERS. Unit-level, so every TDataFlowSolver<T> instantiation
  accumulates into the SAME totals -- which is the point: the two dominant
  phases are different instantiations of one algorithm, and the question is
  about the algorithm. Plain Inc, not Interlocked: lint-all is single-threaded
  (no TParallel/TTask anywhere on that path), and a torn count would be a
  measurement bug, not a correctness one. }
type
  TLatticeBucket = record
    Name: string;
    Solves, Blocks, Visits, SolveTicks, TransferTicks: Int64;
  end;

var
  GBuckets: TArray<TLatticeBucket>;
  GSolves, GBlocks, GVisits, GReenq: Int64;
  GJoins, GTransfers, GComparisons: Int64;
  GSolveTicks, GTransferTicks: Int64;
  GWorstRatio: Double;
  GWorstBlocks: Int64;

function DataFlowStats: TDataFlowStats;
begin
  Result.Solves      := GSolves;
  Result.Blocks      := GBlocks;
  Result.Visits      := GVisits;
  Result.Reenqueues  := GReenq;
  Result.Joins       := GJoins;
  Result.Transfers   := GTransfers;
  Result.Comparisons := GComparisons;
  Result.WorstRatio  := GWorstRatio;
  Result.WorstBlocks := GWorstBlocks;
  Result.SolveSeconds    := GSolveTicks    / TStopwatch.Frequency;
  Result.TransferSeconds := GTransferTicks / TStopwatch.Frequency;
end;

function DataFlowLatticeStats: TArray<TDataFlowLatticeStat>;
var I, J: Integer; T: TDataFlowLatticeStat;
begin
  SetLength(Result, Length(GBuckets));
  for I := 0 to High(GBuckets) do
  begin
    Result[I].Name            := GBuckets[I].Name;
    Result[I].Solves          := GBuckets[I].Solves;
    Result[I].Blocks          := GBuckets[I].Blocks;
    Result[I].Visits          := GBuckets[I].Visits;
    Result[I].SolveSeconds    := GBuckets[I].SolveTicks    / TStopwatch.Frequency;
    Result[I].TransferSeconds := GBuckets[I].TransferTicks / TStopwatch.Frequency;
  end;
  { Insertion sort, descending by cost. A handful of lattices exist, so the
    simplest correct thing beats reaching for a comparer. }
  for I := 1 to High(Result) do
  begin
    T := Result[I]; J := I - 1;
    while (J >= 0) and (Result[J].SolveSeconds < T.SolveSeconds) do
    begin Result[J + 1] := Result[J]; Dec(J); end;
    Result[J + 1] := T;
  end;
end;

procedure DataFlowRecordSolve(const AName: string; ABlocks, AVisits, AReenqueues,
  AJoins, ATransfers, AComparisons, ASolveTicks, ATransferTicks: Int64);
var I, K: Integer;
begin
  K := -1;
  for I := 0 to High(GBuckets) do
    if GBuckets[I].Name = AName then begin K := I; Break; end;
  if K < 0 then
  begin
    K := Length(GBuckets); SetLength(GBuckets, K + 1);
    GBuckets[K].Name := AName;
  end;
  Inc(GBuckets[K].Solves); Inc(GBuckets[K].Blocks, ABlocks);
  Inc(GBuckets[K].Visits, AVisits);
  Inc(GBuckets[K].SolveTicks, ASolveTicks);
  Inc(GBuckets[K].TransferTicks, ATransferTicks);
  Inc(GSolves); Inc(GBlocks, ABlocks); Inc(GVisits, AVisits); Inc(GReenq, AReenqueues);
  Inc(GJoins, AJoins); Inc(GTransfers, ATransfers); Inc(GComparisons, AComparisons);
  Inc(GSolveTicks, ASolveTicks); Inc(GTransferTicks, ATransferTicks);
  { WorstRatio is tracked per SOLVE, not derived from the totals: an aggregate
    near 1.00 can still hide a handful of pathological routines, and if it does
    then THOSE are the target rather than the iteration order. }
  if (ABlocks > 0) and (AVisits / ABlocks > GWorstRatio) then
  begin GWorstRatio := AVisits / ABlocks; GWorstBlocks := ABlocks; end;
end;

class function TDataFlowSolver<TValue>.Solve(const ACfg: TCfg;
  const AAnalysis: IDataFlowAnalysis<TValue>; out AIn, AOut: TArray<TValue>): Boolean;
var
  N, B, P, I: Integer;
  Work: TQueue<Integer>;
  InQueue: TArray<Boolean>;
  Acc, NewVal: TValue;
  Fwd: Boolean;
  Boundary: Integer;
  Adj: TList<Integer>;
  T0, TX, LocalVisits, LocalJoins, LocalReenq, LocalTransferTicks: Int64;
  LocalTransfers, LocalEquals: Int64;
  LatticeName: string;
begin
  AIn := nil; AOut := nil;
  if ACfg.Skipped then Exit(False);
  T0 := TStopwatch.GetTimeStamp;
  LocalVisits := 0; LocalJoins := 0; LocalReenq := 0; LocalTransferTicks := 0;
  LocalTransfers := 0; LocalEquals := 0;
  { Interface-to-object cast: the lattices are all TInterfacedObject descendants,
    and this is the only way to tell them apart without threading a tag through
    every call site. Once per solve, never per visit. }
  LatticeName := (AAnalysis as TObject).ClassName;
  N := ACfg.BlockCount;
  SetLength(AIn, N); SetLength(AOut, N); SetLength(InQueue, N);
  Fwd := AAnalysis.Direction = fdForward;
  if Fwd then Boundary := ACfg.EntryIdx else Boundary := ACfg.ExitIdx;
  for B := 0 to N - 1 do begin AIn[B] := AAnalysis.Bottom; AOut[B] := AAnalysis.Bottom; end;

  Work := TQueue<Integer>.Create;
  try
    for B := 0 to N - 1 do begin Work.Enqueue(B); InQueue[B] := True; end;
    while Work.Count > 0 do
    begin
      B := Work.Dequeue; InQueue[B] := False; Inc(LocalVisits);
      { gather predecessors (forward) or successors (backward) }
      if Fwd then Adj := ACfg.Blocks[B].Pred else Adj := ACfg.Blocks[B].Succ;
      if B = Boundary then Acc := AAnalysis.Boundary
      else Acc := AAnalysis.Bottom;
      for I := 0 to Adj.Count - 1 do
      begin
        P := Adj[I];
        Inc(LocalJoins);
        if Fwd then Acc := AAnalysis.Join(Acc, AOut[P])
        else Acc := AAnalysis.Join(Acc, AIn[P]);
      end;
      if Fwd then
      begin
        AIn[B] := Acc;
        TX := TStopwatch.GetTimeStamp;
        NewVal := AAnalysis.Transfer(ACfg.Blocks[B], AIn[B]);
        Inc(LocalTransferTicks, TStopwatch.GetTimeStamp - TX); Inc(LocalTransfers);
        Inc(LocalEquals);
        if not AAnalysis.Equals(NewVal, AOut[B]) then
        begin
          AOut[B] := NewVal;
          for I := 0 to ACfg.Blocks[B].Succ.Count - 1 do
            if not InQueue[ACfg.Blocks[B].Succ[I]] then
            begin Work.Enqueue(ACfg.Blocks[B].Succ[I]); InQueue[ACfg.Blocks[B].Succ[I]] := True; Inc(LocalReenq); end;
        end;
      end
      else
      begin
        AOut[B] := Acc;
        TX := TStopwatch.GetTimeStamp;
        NewVal := AAnalysis.Transfer(ACfg.Blocks[B], AOut[B]);
        Inc(LocalTransferTicks, TStopwatch.GetTimeStamp - TX); Inc(LocalTransfers);
        Inc(LocalEquals);
        if not AAnalysis.Equals(NewVal, AIn[B]) then
        begin
          AIn[B] := NewVal;
          for I := 0 to ACfg.Blocks[B].Pred.Count - 1 do
            if not InQueue[ACfg.Blocks[B].Pred[I]] then
            begin Work.Enqueue(ACfg.Blocks[B].Pred[I]); InQueue[ACfg.Blocks[B].Pred[I]] := True; Inc(LocalReenq); end;
        end;
      end;
    end;
    Result := True;
  finally
    Work.Free;
    { In the finally, so an exception mid-solve still records the work done. }
    DataFlowRecordSolve(LatticeName, N, LocalVisits, LocalReenq, LocalJoins,
      LocalTransfers, LocalEquals, TStopwatch.GetTimeStamp - T0, LocalTransferTicks);
  end;
end;

end.
