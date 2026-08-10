unit DRagLint.Analysis.DataFlow;

{ Generic monotone data-flow framework (M2). An analysis supplies a lattice
  value type plus Bottom/Boundary/Join/Transfer/Equals and a direction; the
  worklist solver iterates IN/OUT per basic block to a fixpoint. }

interface

uses
  System.Generics.Collections,
  DRagLint.Analysis.Cfg;

type
  /// <summary>Iteration direction of a data-flow analysis.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Analysis.DataFlow.pas), declaration (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TDefiniteAssignment.Direction (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TFreedState.Direction (DRagLint.Analysis.Flow.Lattices.pas), DRagLint.Analysis.Flow.Lattices.TLiveness.Direction (DRagLint.Analysis.Flow.Lattices.pas) (+1 more)
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
    function Direction: TFlowDir;
    /// <summary>The lattice bottom (initial IN/OUT of interior blocks).</summary>
    function Bottom: TValue;
    /// <summary>Value at the boundary block (Entry for forward, Exit for
    /// backward) -- e.g. params assigned-on-entry, or vars live-at-exit.</summary>
    function Boundary: TValue;
    /// <summary>Meet of two predecessor/successor contributions.</summary>
    /// <param name="A"><!-- drag-lint:auto type -->const TValue</param>
    /// <param name="B"><!-- drag-lint:auto type -->const TValue</param>
    function Join(const A, B: TValue): TValue;
    /// <summary>Effect of one block on the in-value.</summary>
    /// <param name="ABlock"><!-- drag-lint:auto type -->const TCfgBlock</param>
    /// <param name="AIn"><!-- drag-lint:auto type -->const TValue</param>
    function Transfer(const ABlock: TCfgBlock; const AIn: TValue): TValue;
    /// <summary>Lattice equality (fixpoint test).</summary>
    /// <param name="A"><!-- drag-lint:auto type -->const TValue</param>
    /// <param name="B"><!-- drag-lint:auto type -->const TValue</param>
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
    /// <returns><!-- drag-lint:auto -->Observed: True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: DRagLint.Analysis.Cfg.TCfg.BlockCount
    /// Complexity: 17 (cyclomatic, outer body), 64 lines (full implementation)
    /// Mutates: AIn (out), AOut (out)
    /// <seealso cref="DRagLint.Analysis.Cfg.TCfg.BlockCount"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Solve(const ACfg: TCfg; const AAnalysis: IDataFlowAnalysis<TValue>;
      out AIn, AOut: TArray<TValue>): Boolean;
  end;

implementation

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
begin
  AIn := nil; AOut := nil;
  if ACfg.Skipped then Exit(False);
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
      B := Work.Dequeue; InQueue[B] := False;
      { gather predecessors (forward) or successors (backward) }
      if Fwd then Adj := ACfg.Blocks[B].Pred else Adj := ACfg.Blocks[B].Succ;
      if B = Boundary then Acc := AAnalysis.Boundary
      else Acc := AAnalysis.Bottom;
      for I := 0 to Adj.Count - 1 do
      begin
        P := Adj[I];
        if Fwd then Acc := AAnalysis.Join(Acc, AOut[P])
        else Acc := AAnalysis.Join(Acc, AIn[P]);
      end;
      if Fwd then
      begin
        AIn[B] := Acc;
        NewVal := AAnalysis.Transfer(ACfg.Blocks[B], AIn[B]);
        if not AAnalysis.Equals(NewVal, AOut[B]) then
        begin
          AOut[B] := NewVal;
          for I := 0 to ACfg.Blocks[B].Succ.Count - 1 do
            if not InQueue[ACfg.Blocks[B].Succ[I]] then
            begin Work.Enqueue(ACfg.Blocks[B].Succ[I]); InQueue[ACfg.Blocks[B].Succ[I]] := True; end;
        end;
      end
      else
      begin
        AOut[B] := Acc;
        NewVal := AAnalysis.Transfer(ACfg.Blocks[B], AOut[B]);
        if not AAnalysis.Equals(NewVal, AIn[B]) then
        begin
          AIn[B] := NewVal;
          for I := 0 to ACfg.Blocks[B].Pred.Count - 1 do
            if not InQueue[ACfg.Blocks[B].Pred[I]] then
            begin Work.Enqueue(ACfg.Blocks[B].Pred[I]); InQueue[ACfg.Blocks[B].Pred[I]] := True; end;
        end;
      end;
    end;
    Result := True;
  finally
    Work.Free;
  end;
end;

end.
