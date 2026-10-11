unit DRagLint.Charts.Diff;

{ The ONE diff for every charts output (spec 6a). Items carry a display Text and a
  comparison Key; this unit compares Keys ORDINALLY and knows nothing about any
  format -- adapters (DRagLint.Charts.Adapter.*) decide what a key is. }

interface

const
  /// <summary>The index a TDiffEdit carries for the side it does not touch.</summary>
  DIFF_NO_INDEX = -1;

type
  /// <summary>One comparable item: what is SHOWN and what is COMPARED.</summary>
  /// <remarks>Key is compared with ordinal string equality (case-sensitive): an adapter
  /// that wants case-blind matching lowercases its key. PS trap handled: PowerShell's -eq
  /// is case-insensitive and would not have told two keys apart by case; this does.</remarks>
  TDiffItem = record
    /// <summary>The text a renderer shows for this item.</summary>
    Text: string;
    /// <summary>The value MyersDiff compares, ordinally.</summary>
    Key : string;
    /// <summary>Builds an item.</summary>
    /// <param name="pText">Display text.</param>
    /// <param name="pKey">Comparison key.</param>
    /// <returns>The item.</returns>
    class function Make(const pText, pKey: string): TDiffItem; static;
  end;

  /// <summary>Kind of one edit-script step.</summary>
  TDiffOp = (doEqual, doDelete, doInsert);

  /// <summary>One step of the edit script.</summary>
  /// <remarks>OldIndex and NewIndex are 0-based into the old / new arrays; OldIndex is
  /// DIFF_NO_INDEX for doInsert, NewIndex is DIFF_NO_INDEX for doDelete.</remarks>
  TDiffEdit = record
    /// <summary>What this step does.</summary>
    Op      : TDiffOp;
    /// <summary>0-based old index; DIFF_NO_INDEX for doInsert.</summary>
    OldIndex: Integer;
    /// <summary>0-based new index; DIFF_NO_INDEX for doDelete.</summary>
    NewIndex: Integer;
  end;

  /// <summary>A group of changes with unchanged context around them, unified-diff style.</summary>
  /// <remarks>Starts are 1-based line numbers and counts are the old / new lines the hunk
  /// holds, exactly as in a unified diff's "@@ -OldStart,OldCount +NewStart,NewCount @@".
  /// A side with NO lines in the hunk (count 0) carries the line AFTER which the change
  /// sits, as GNU diff does: a pure insert after old line 2 is -2,0, an empty old side is
  /// -0,0.</remarks>
  TDiffHunk = record
    /// <summary>1-based first old line (see remarks for count 0).</summary>
    OldStart: Integer;
    /// <summary>Old lines (equal + deleted) in the hunk.</summary>
    OldCount: Integer;
    /// <summary>1-based first new line (see remarks for count 0).</summary>
    NewStart: Integer;
    /// <summary>New lines (equal + inserted) in the hunk.</summary>
    NewCount: Integer;
    /// <summary>The slice of the edit script this hunk covers, context included.</summary>
    Edits: TArray<TDiffEdit>;
  end;

/// <summary>Shortest edit script between two item sequences (Myers 1986, forward greedy
/// O((N+M)D), with the V array kept per D so the script is recovered by backtracking
/// rather than by the linear-space refinement).</summary>
/// <param name="pOld">The old sequence.</param>
/// <param name="pNew">The new sequence.</param>
/// <returns>Edits in order; replaying equals and inserts yields pNew, replaying equals and
/// deletes yields pOld. Two empty inputs give an empty script.</returns>
/// <remarks>Keys compare ordinally (see TDiffItem). A moved block is a deletion plus an
/// insertion (D3). Memory is O((N+M)D) for the trace -- fine for report-sized inputs.
/// Pure; thread-safe.</remarks>
function MyersDiff(const pOld, pNew: TArray<TDiffItem>): TArray<TDiffEdit>;

/// <summary>Groups an edit script into hunks, keeping pContext equal items on each side of
/// every change and merging two changes whose contexts overlap or touch (D2).</summary>
/// <param name="pEdits">An edit script from MyersDiff.</param>
/// <param name="pContext">Equal items kept before and after each change; a negative value
/// counts as 0.</param>
/// <returns>Hunks in order; none when the script holds no change.</returns>
/// <remarks>Two changes separated by at most 2 * pContext equal items share one hunk, as
/// in GNU diff. Ranges follow the TDiffHunk rules. Pure; thread-safe.</remarks>
function BuildHunks(const pEdits: TArray<TDiffEdit>; pContext: Integer = 3): TArray<TDiffHunk>;

/// <summary>Counts equal / deleted / inserted edits.</summary>
/// <param name="pEdits">An edit script.</param>
/// <param name="pEqual">Receives the number of doEqual edits.</param>
/// <param name="pDeleted">Receives the number of doDelete edits.</param>
/// <param name="pInserted">Receives the number of doInsert edits.</param>
/// <returns>True when at least one edit is not doEqual.</returns>
function CountEdits(const pEdits: TArray<TDiffEdit>; out pEqual, pDeleted, pInserted: Integer): Boolean;

implementation

uses
  System.Math, System.Generics.Collections;

function MakeEdit(pOp: TDiffOp; pOldIndex, pNewIndex: Integer): TDiffEdit;
begin
  Result.Op:= pOp;
  Result.OldIndex:= pOldIndex;
  Result.NewIndex:= pNewIndex;
end;

{ True when the furthest-reaching path on diagonal pK in round pD arrives by a DOWN move
  from diagonal pK + 1 (an insert); False when it arrives by a RIGHT move from pK - 1 (a
  delete). pV is the V array as it stood at the start of round pD. }
function StepsDown(const pV: TArray<Integer>; pOffset, pK, pD: Integer): Boolean;
begin
  Result:= (pK = -pD) or ((pK <> pD) and (pV[pOffset + pK - 1] < pV[pOffset + pK + 1]));
end;

{ Index of the first edit at or after pFrom that is not doEqual; -1 when none. }
function NextChange(const pEdits: TArray<TDiffEdit>; pFrom: Integer): Integer;
begin
  for var I:= pFrom to High(pEdits) do
    if pEdits[I].Op <> doEqual then
      Exit(I);
  Result:= DIFF_NO_INDEX;
end;

class function TDiffItem.Make(const pText, pKey: string): TDiffItem;
begin
  Result.Text:= pText;
  Result.Key:= pKey;
end;

function MyersDiff(const pOld, pNew: TArray<TDiffItem>): TArray<TDiffEdit>;
var
  OldLen, NewLen, MaxD, Offset, D, K, X, Y: Integer;
  V    : TArray<Integer>;
  Trace: TList<TArray<Integer>>;
  Rev  : TList<TDiffEdit>;
  Found: Boolean;
begin
  Result:= nil;
  OldLen:= Length(pOld);
  NewLen:= Length(pNew);
  MaxD:= OldLen + NewLen;
  if MaxD = 0 then
    Exit;
  { V[Offset + K] = furthest X reached on diagonal K (= X - Y). Diagonals -MaxD - 1 ..
    MaxD + 1 are addressed; SetLength zero-fills, which gives the virtual start: X = 0 on diagonal 1. }
  Offset:= MaxD + 1;
  SetLength(V, 2 * Offset + 1);
  Rev:= nil;
  Trace:= TList<TArray<Integer>>.Create;
  try
    { forward pass: round D extends every diagonal -D, -D + 2 .. D by one edit plus its
      snake, until a path reaches (OldLen, NewLen); D never exceeds MaxD. }
    Found:= False;
    D:= 0;
    while not Found do
    begin
      Trace.Add(Copy(V));
      K:= -D;
      while K <= D do
      begin
        X:= if StepsDown(V, Offset, K, D) then V[Offset + K + 1] else V[Offset + K - 1] + 1;
        Y:= X - K;
        while (X < OldLen) and (Y < NewLen) and (pOld[X].Key = pNew[Y].Key) do
        begin
          Inc(X);
          Inc(Y);
        end;
        V[Offset + K]:= X;
        if (X >= OldLen) and (Y >= NewLen) then
        begin
          Found:= True;
          Break;
        end;
        Inc(K, 2);
      end;
      if not Found then
        Inc(D);
    end;
    { backtrack from (OldLen, NewLen): Trace[Step] is V at the start of round Step, so it
      names the diagonal round Step came from. Edits are collected last-first. }
    Rev:= TList<TDiffEdit>.Create;
    X:= OldLen;
    Y:= NewLen;
    for var Step:= D downto 1 do
    begin
      var VPrev:= Trace[Step];
      K:= X - Y;
      var PrevK:= if StepsDown(VPrev, Offset, K, Step) then K + 1 else K - 1;
      var PrevX:= VPrev[Offset + PrevK];
      var PrevY:= PrevX - PrevK;
      while (X > PrevX) and (Y > PrevY) do
      begin
        Dec(X);
        Dec(Y);
        Rev.Add(MakeEdit(doEqual, X, Y));
      end;
      if X = PrevX then
        Rev.Add(MakeEdit(doInsert, DIFF_NO_INDEX, PrevY))
      else
        Rev.Add(MakeEdit(doDelete, PrevX, DIFF_NO_INDEX));
      X:= PrevX;
      Y:= PrevY;
    end;
    { the round-0 snake: a common prefix }
    while (X > 0) and (Y > 0) do
    begin
      Dec(X);
      Dec(Y);
      Rev.Add(MakeEdit(doEqual, X, Y));
    end;
    SetLength(Result, Rev.Count);
    for var I:= 0 to Rev.Count - 1 do
      Result[I]:= Rev[Rev.Count - 1 - I];
  finally
    Rev.Free;
    Trace.Free;
  end;
end;

function BuildHunks(const pEdits: TArray<TDiffEdit>; pContext: Integer): TArray<TDiffHunk>;
var
  Ctx, First, Last, Next, Lo, Hi, I, OldPos, NewPos: Integer;
  Hunk : TDiffHunk;
  Hunks: TList<TDiffHunk>;
begin
  Ctx:= Max(0, pContext);
  Hunks:= TList<TDiffHunk>.Create;
  try
    I:= 0;      // next edit not yet counted into OldPos / NewPos
    OldPos:= 0; // old items before edit I
    NewPos:= 0; // new items before edit I
    First:= NextChange(pEdits, 0);
    while First <> DIFF_NO_INDEX do
    begin
      { absorb every later change whose gap of equal edits is at most 2 * Ctx: the two
        contexts would overlap or touch }
      Last:= First;
      Next:= NextChange(pEdits, Last + 1);
      while (Next <> DIFF_NO_INDEX) and (Next - Last - 1 <= 2 * Ctx) do
      begin
        Last:= Next;
        Next:= NextChange(pEdits, Last + 1);
      end;
      Lo:= Max(I, First - Ctx);
      Hi:= Min(High(pEdits), Last + Ctx);
      while I < Lo do
      begin
        if pEdits[I].Op <> doInsert then
          Inc(OldPos);
        if pEdits[I].Op <> doDelete then
          Inc(NewPos);
        Inc(I);
      end;
      Hunk.OldCount:= 0;
      Hunk.NewCount:= 0;
      for var J:= Lo to Hi do
      begin
        if pEdits[J].Op <> doInsert then
          Inc(Hunk.OldCount);
        if pEdits[J].Op <> doDelete then
          Inc(Hunk.NewCount);
      end;
      { 1-based first line; a side with no lines names the line it follows (GNU diff) }
      Hunk.OldStart:= if Hunk.OldCount > 0 then OldPos + 1 else OldPos;
      Hunk.NewStart:= if Hunk.NewCount > 0 then NewPos + 1 else NewPos;
      Hunk.Edits:= Copy(pEdits, Lo, Hi - Lo + 1);
      Hunks.Add(Hunk);
      Inc(OldPos, Hunk.OldCount);
      Inc(NewPos, Hunk.NewCount);
      I:= Hi + 1;
      First:= Next;
    end;
    Result:= Hunks.ToArray;
  finally
    Hunks.Free;
  end;
end;

function CountEdits(const pEdits: TArray<TDiffEdit>; out pEqual, pDeleted, pInserted: Integer): Boolean;
begin
  pEqual:= 0;
  pDeleted:= 0;
  pInserted:= 0;
  for var E in pEdits do
    case E.Op of
      doEqual : Inc(pEqual);
      doDelete: Inc(pDeleted);
      doInsert: Inc(pInserted);
    end;
  Result:= (pDeleted + pInserted) > 0;
end;

end.
