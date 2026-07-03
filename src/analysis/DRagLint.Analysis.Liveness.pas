unit DRagLint.Analysis.Liveness;

{ Boundary-liveness helper (M2): queries the live-variable set at an arbitrary
  ITEM boundary inside a block, not just the per-block IN/OUT that
  TDataFlowSolver<TArray<Boolean>> exposes. Extract Method (and other
  refactorings that need to know what is live at a specific statement) can
  therefore ask "what is live right after/before item K of block B" instead
  of only "what is live at block entry/exit". }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  TreeSitter,
  DRagLint.Analysis.Cfg,
  DRagLint.Analysis.DataFlow,
  DRagLint.Analysis.Flow.Lattices;

/// <summary>Live var-table indices immediately AFTER item AItemIdx of block
/// ABlockIdx (i.e. the state liveness would report if AItemIdx were the last
/// item of the block).</summary>
/// <param name="ACfg">The routine's control-flow graph (must not be
/// ACfg.Skipped; caller checks first).</param>
/// <param name="AVars">The routine's variable table (locals/params/Result).</param>
/// <param name="ASrc">The unit's source bytes, matching the CFG's own Src.</param>
/// <param name="ABlockIdx">Index of the block containing the item.</param>
/// <param name="AItemIdx">0-based index of the item within the block; must be
/// in range 0..ABlock.Items.Count-1.</param>
/// <returns>A bitset over 0..AVars.Count-1: True where the var is live
/// immediately after the item. Always a fresh array -- never aliases the
/// solver's internal AOut array.</returns>
/// <remarks>Solves TLiveness once via TDataFlowSolver, then replays the same
/// per-item backward transfer TLiveness.Transfer uses -- starting from the
/// block's live-OUT and applying items Count-1 downto AItemIdx+1 -- so the
/// result is exactly what the block-level fixpoint would have produced had
/// the block ended at AItemIdx. Returns all-False (sized to AVars.Count) if
/// ACfg.Skipped or the indices are out of range.</remarks>
function LiveAfterItem(const ACfg: TCfg; AVars: TRoutineVarTable; const ASrc: TBytes;
  ABlockIdx, AItemIdx: Integer): TArray<Boolean>;

/// <summary>Live var-table indices immediately BEFORE item AItemIdx of block
/// ABlockIdx -- i.e. LiveAfterItem's result with AItemIdx's own backward
/// transfer additionally applied. This is the liveness a selection ENTERING
/// at AItemIdx would see (a candidate cut point for Extract Method).</summary>
/// <param name="ACfg">The routine's control-flow graph (must not be
/// ACfg.Skipped; caller checks first).</param>
/// <param name="AVars">The routine's variable table (locals/params/Result).</param>
/// <param name="ASrc">The unit's source bytes, matching the CFG's own Src.</param>
/// <param name="ABlockIdx">Index of the block containing the item.</param>
/// <param name="AItemIdx">0-based index of the item within the block; must be
/// in range 0..ABlock.Items.Count-1.</param>
/// <returns>A bitset over 0..AVars.Count-1: True where the var is live
/// immediately before the item. Always a fresh array -- never aliases the
/// solver's internal arrays.</returns>
/// <remarks>Equivalent to LiveAfterItem(..., AItemIdx) with one more backward
/// step (AItemIdx's own kill-then-gen) applied, matching TLiveness.Transfer's
/// per-item order: kill the whole-var def first, then add its uses.</remarks>
function LiveBeforeItem(const ACfg: TCfg; AVars: TRoutineVarTable; const ASrc: TBytes;
  ABlockIdx, AItemIdx: Integer): TArray<Boolean>;

implementation

{ Apply TLiveness's per-item backward transfer for a single item to ALive (in
  place): kill the whole-var def first, then add reads/call-defs as uses.
  Mirrors TLiveness.Transfer's per-item body and the split-variable replay in
  DRagLint.Diagnostics.FlowChecks.pas exactly, so LiveAfterItem/LiveBeforeItem
  agree with the block-level TLiveness fixpoint. }
procedure ApplyItemBackward(const AItem: TCfgItem; AVars: TRoutineVarTable;
  const ASrc: TBytes; var ALive: TArray<Boolean>);
var
  J, Tgt: Integer;
  Reads, CallDefs: TList<Integer>;
begin
  if AItem.Opaque then
  begin
    for J := 0 to AVars.Count - 1 do
      if AVars.Get(J).Kind = vkLocal then ALive[J] := True;
    Exit;
  end;
  Reads := TList<Integer>.Create;
  CallDefs := TList<Integer>.Create;
  try
    if AItem.Node.NodeType = 'assignment' then
    begin
      Tgt := AssignmentTargetIndex(AItem.Node, ASrc, AVars); { whole-var def kills }
      if Tgt >= 0 then ALive[Tgt] := False;
      CollectReadsAndCallDefs(AItem.Node.ChildByField('rhs'), ASrc, AVars, Reads, CallDefs);
      for J := 0 to Reads.Count - 1 do ALive[Reads[J]] := True;
      for J := 0 to CallDefs.Count - 1 do ALive[CallDefs[J]] := True;
      { a partial write (a[i] := / x.f :=) reads its base + index -> live }
      if Tgt < 0 then
      begin
        Reads.Clear; CallDefs.Clear;
        CollectReadsAndCallDefs(AItem.Node.ChildByField('lhs'), ASrc, AVars, Reads, CallDefs);
        for J := 0 to Reads.Count - 1 do ALive[Reads[J]] := True;
        for J := 0 to CallDefs.Count - 1 do ALive[CallDefs[J]] := True;
      end;
    end
    else
    begin
      CollectReadsAndCallDefs(AItem.Node, ASrc, AVars, Reads, CallDefs);
      for J := 0 to Reads.Count - 1 do ALive[Reads[J]] := True;
      for J := 0 to CallDefs.Count - 1 do ALive[CallDefs[J]] := True;
    end;
  finally
    Reads.Free;
    CallDefs.Free;
  end;
end;

/// <summary>Shared implementation: solve TLiveness once, then replay the
/// per-item backward transfer within ABlockIdx from its live-OUT down to
/// (but not including, unless AIncludeTarget) the item at AItemIdx.</summary>
function LiveAtBoundary(const ACfg: TCfg; AVars: TRoutineVarTable; const ASrc: TBytes;
  ABlockIdx, AItemIdx: Integer; AIncludeTarget: Boolean): TArray<Boolean>;
var
  AIn, AOut: TArray<TArray<Boolean>>;
  I: Integer;
  Block: TCfgBlock;
  FirstReplayIdx: Integer;
begin
  SetLength(Result, AVars.Count);
  for I := 0 to AVars.Count - 1 do Result[I] := False;
  if ACfg.Skipped then Exit;
  if (ABlockIdx < 0) or (ABlockIdx >= ACfg.BlockCount) then Exit;
  Block := ACfg.Blocks[ABlockIdx];
  if (AItemIdx < 0) or (AItemIdx >= Block.Items.Count) then Exit;

  if not TDataFlowSolver<TArray<Boolean>>.Solve(ACfg, TLiveness.Create(AVars, ASrc), AIn, AOut) then
    Exit;

  Result := Copy(AOut[ABlockIdx]); { start from the block's live-OUT; never alias it }
  if AIncludeTarget then FirstReplayIdx := AItemIdx
  else FirstReplayIdx := AItemIdx + 1;
  for I := Block.Items.Count - 1 downto FirstReplayIdx do
    ApplyItemBackward(Block.Items[I], AVars, ASrc, Result);
end;

function LiveAfterItem(const ACfg: TCfg; AVars: TRoutineVarTable; const ASrc: TBytes;
  ABlockIdx, AItemIdx: Integer): TArray<Boolean>;
begin
  Result := LiveAtBoundary(ACfg, AVars, ASrc, ABlockIdx, AItemIdx, False);
end;

function LiveBeforeItem(const ACfg: TCfg; AVars: TRoutineVarTable; const ASrc: TBytes;
  ABlockIdx, AItemIdx: Integer): TArray<Boolean>;
begin
  Result := LiveAtBoundary(ACfg, AVars, ASrc, ABlockIdx, AItemIdx, True);
end;

end.
