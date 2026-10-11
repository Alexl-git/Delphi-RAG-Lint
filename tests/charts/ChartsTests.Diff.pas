unit ChartsTests.Diff;

{ Cases for DRagLint.Charts.Diff: the Myers edit script, ordinal key comparison,
  unified-diff hunks and the edit counter.

  Expected values are written as strings in the notation a reader already knows:
  an edit script as '=' / '-' / '+' per step, a hunk as its unified-diff range
  '-OldStart,OldCount +NewStart,NewCount', counts as '=E -D +I'. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDiffCoreTests = class
  public
    [Test] procedure IdenticalSequencesGiveOnlyEquals;
    [Test] procedure EmptyOldIsAllInserts;
    [Test] procedure EmptyNewIsAllDeletes;
    [Test] procedure ClassicAbcabbaVsCbabac;       // Myers paper: D = 5
    [Test] procedure KeysCompareOrdinalNotText;    // same Key, different Text = equal; differing case = different
    [Test] procedure EditScriptReplaysOldIntoNew;  // apply edits to old, get new (any input)
    [Test] procedure HunksCarryContextAndMerge;    // two changes 2 lines apart, context 3 -> one hunk
    [Test] procedure HunksSplitWhenFarApart;       // changes 10 lines apart, context 3 -> two hunks
    [Test] procedure HunkRangesAreUnifiedStyle;    // 1-based start, counts of old/new lines in the hunk
    [Test] procedure MovedBlockIsDeletePlusInsert; // D3
    [Test] procedure CountEditsReportsChange;
  end;

implementation

uses
  System.SysUtils, DRagLint.Charts.Diff;

const
  UNIFIED_CONTEXT = 3; // the default of diff -u
  NARROW_CONTEXT = 2;

function Items(const pKeys: array of string): TArray<TDiffItem>;
begin
  SetLength(Result, Length(pKeys));
  for var I:= 0 to High(pKeys) do
    Result[I]:= TDiffItem.Make('shown ' + pKeys[I], pKeys[I]);
end;

{ The new side rebuilt from the script: equals take the old item, inserts the new one. }
function Replay(const pOld, pNew: TArray<TDiffItem>; const pEdits: TArray<TDiffEdit>): string;
begin
  var Keys: TArray<string>;
  SetLength(Keys, Length(pEdits));
  var N:= 0;
  for var E in pEdits do
    if E.Op <> doDelete then
    begin
      Keys[N]:= if E.Op = doEqual then pOld[E.OldIndex].Key else pNew[E.NewIndex].Key;
      Inc(N);
    end;
  Result:= string.Join('', Keys, 0, N);
end;

{ The old side rebuilt from the script: equals and deletes, in order. }
function ReplayOld(const pOld: TArray<TDiffItem>; const pEdits: TArray<TDiffEdit>): string;
begin
  var Keys: TArray<string>;
  SetLength(Keys, Length(pEdits));
  var N:= 0;
  for var E in pEdits do
    if E.Op <> doInsert then
    begin
      Keys[N]:= pOld[E.OldIndex].Key;
      Inc(N);
    end;
  Result:= string.Join('', Keys, 0, N);
end;

function KeysOf(const pItems: TArray<TDiffItem>): string;
begin
  var Keys: TArray<string>;
  SetLength(Keys, Length(pItems));
  for var I:= 0 to High(pItems) do
    Keys[I]:= pItems[I].Key;
  Result:= string.Join('', Keys);
end;

{ '=' equal, '-' delete, '+' insert, one character per edit. }
function Ops(const pEdits: TArray<TDiffEdit>): string;
const
  OP_CHAR: array[TDiffOp] of Char = ('=', '-', '+');
begin
  SetLength(Result, Length(pEdits));
  for var I:= 0 to High(pEdits) do
    Result[I + 1]:= OP_CHAR[pEdits[I].Op];
end;

function Range(const pHunk: TDiffHunk): string;
begin
  Result:= Format('-%d,%d +%d,%d', [pHunk.OldStart, pHunk.OldCount, pHunk.NewStart, pHunk.NewCount]);
end;

{ Every hunk's range, ' | '-separated; '' when there is none. }
function Ranges(const pHunks: TArray<TDiffHunk>): string;
begin
  var Parts: TArray<string>;
  SetLength(Parts, Length(pHunks));
  for var I:= 0 to High(pHunks) do
    Parts[I]:= Range(pHunks[I]);
  Result:= string.Join(' | ', Parts);
end;

function Counts(const pEdits: TArray<TDiffEdit>; out pChanged: Boolean): string;
begin
  var Eq, Del, Ins: Integer;
  pChanged:= CountEdits(pEdits, Eq, Del, Ins);
  Result:= Format('=%d -%d +%d', [Eq, Del, Ins]);
end;

procedure TDiffCoreTests.IdenticalSequencesGiveOnlyEquals;
begin
  var Edits:= MyersDiff(Items(['a', 'b', 'c']), Items(['a', 'b', 'c']));
  Assert.AreEqual('===', Ops(Edits));
  for var I: Integer:= 0 to High(Edits) do
  begin
    Assert.AreEqual(I, Edits[I].OldIndex);
    Assert.AreEqual(I, Edits[I].NewIndex);
  end;
  Assert.AreEqual('', Ranges(BuildHunks(Edits)), 'no change = no hunk');
  Assert.AreEqual('', Ops(MyersDiff(nil, nil)), 'two empty sequences = empty script');
end;

procedure TDiffCoreTests.EmptyOldIsAllInserts;
begin
  var Edits:= MyersDiff(nil, Items(['x', 'y']));
  Assert.AreEqual('++', Ops(Edits));
  for var I: Integer:= 0 to High(Edits) do
  begin
    Assert.AreEqual(DIFF_NO_INDEX, Edits[I].OldIndex);
    Assert.AreEqual(I, Edits[I].NewIndex);
  end;
end;

procedure TDiffCoreTests.EmptyNewIsAllDeletes;
begin
  var Edits:= MyersDiff(Items(['x', 'y', 'z']), nil);
  Assert.AreEqual('---', Ops(Edits));
  for var I: Integer:= 0 to High(Edits) do
  begin
    Assert.AreEqual(I, Edits[I].OldIndex);
    Assert.AreEqual(DIFF_NO_INDEX, Edits[I].NewIndex);
  end;
end;

procedure TDiffCoreTests.ClassicAbcabbaVsCbabac;
begin
  var OldSeq:= Items(['a', 'b', 'c', 'a', 'b', 'b', 'a']);
  var NewSeq:= Items(['c', 'b', 'a', 'b', 'a', 'c']);
  var Edits:= MyersDiff(OldSeq, NewSeq);
  var Changed: Boolean;
  { Myers 1986, fig. 1: the shortest edit script has D = 5 (5 deletes + inserts), so the
    longest common subsequence is 7 - 3 = 4 long }
  Assert.AreEqual('=4 -3 +2', Counts(Edits, Changed));
  Assert.IsTrue(Changed);
  Assert.AreEqual('cbabac', Replay(OldSeq, NewSeq, Edits));
  Assert.AreEqual('abcabba', ReplayOld(OldSeq, Edits));
end;

procedure TDiffCoreTests.KeysCompareOrdinalNotText;
begin
  var OldSeq: TArray<TDiffItem>:= [TDiffItem.Make('  Foo @A.pas:1', 'Foo (A.pas)')];
  var NewSeq: TArray<TDiffItem>:= [TDiffItem.Make('Foo (A.pas:9)', 'Foo (A.pas)')];
  var Eq, Del, Ins: Integer;
  Assert.IsFalse(CountEdits(MyersDiff(OldSeq, NewSeq), Eq, Del, Ins), 'same key = no change');
  NewSeq[0].Key:= 'foo (A.pas)';
  Assert.IsTrue(CountEdits(MyersDiff(OldSeq, NewSeq), Eq, Del, Ins),
    'ordinal: case differs = change (PS -eq would say equal)');
end;

procedure TDiffCoreTests.EditScriptReplaysOldIntoNew;
const
  ALPHABET = 'abcd';
  CASES = 200;
  MAX_LEN = 12;
  SEED = 20261010;
begin
  { Fixed seed: deterministic, yet far more shapes than hand-written cases. A small
    alphabet forces many repeated keys, which is where a wrong backtrack shows. }
  RandSeed:= SEED;
  for var C:= 1 to CASES do
  begin
    var OldSeq: TArray<TDiffItem>:= nil;
    var NewSeq: TArray<TDiffItem>:= nil;
    for var I:= 1 to Random(MAX_LEN + 1) do
      OldSeq:= OldSeq + [TDiffItem.Make('', ALPHABET[Random(Length(ALPHABET)) + 1])];
    for var I:= 1 to Random(MAX_LEN + 1) do
      NewSeq:= NewSeq + [TDiffItem.Make('', ALPHABET[Random(Length(ALPHABET)) + 1])];
    var Edits:= MyersDiff(OldSeq, NewSeq);
    var Ctx:= 'case ' + C.ToString + ' old=' + KeysOf(OldSeq) + ' new=' + KeysOf(NewSeq);
    Assert.AreEqual(KeysOf(NewSeq), Replay(OldSeq, NewSeq, Edits), Ctx + ': new side');
    Assert.AreEqual(KeysOf(OldSeq), ReplayOld(OldSeq, Edits), Ctx + ': old side');
  end;
end;

procedure TDiffCoreTests.HunksCarryContextAndMerge;
begin
  var OldSeq:= Items(['1', '2', '3', '4', '5', '6', '7', '8', '9', '10']);
  var NewSeq:= Items(['1', '2', 'X', '4', '5', 'Y', '7', '8', '9', '10']);
  Assert.AreEqual('-1,9 +1,9', Ranges(BuildHunks(MyersDiff(OldSeq, NewSeq), UNIFIED_CONTEXT)));
end;

procedure TDiffCoreTests.HunksSplitWhenFarApart;
begin
  { changes at line 2 and line 12: 9 equal lines between them, more than 2 * 3 context.
    Hunk 1 = line 1, change, lines 3-5; hunk 2 = lines 9-11, change, lines 13-14. }
  var OldSeq:= Items(['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14']);
  var NewSeq:= Items(['1', 'X', '3', '4', '5', '6', '7', '8', '9', '10', '11', 'Y', '13', '14']);
  var H:= BuildHunks(MyersDiff(OldSeq, NewSeq), UNIFIED_CONTEXT);
  Assert.AreEqual('-1,5 +1,5 | -9,6 +9,6', Ranges(H));
  Assert.IsTrue(Ops(H[1].Edits).StartsWith('==='), 'hunk 2 opens with its 3 context lines');
  Assert.IsTrue(Ops(H[1].Edits).EndsWith('-+==') or Ops(H[1].Edits).EndsWith('+-=='), 'and closes with the 2 left');
  { exactly 2 * context equal lines between two changes: the contexts touch and merge }
  OldSeq:= Items(['1', '2', '3', '4', '5', '6', '7', '8', '9']);
  NewSeq:= Items(['X', '2', '3', '4', '5', '6', '7', 'Y', '9']);
  Assert.AreEqual('-1,9 +1,9', Ranges(BuildHunks(MyersDiff(OldSeq, NewSeq), UNIFIED_CONTEXT)), '6 equal lines, context 3: one hunk');
end;

procedure TDiffCoreTests.HunkRangesAreUnifiedStyle;
begin
  { an insert in the middle of the hunk: 1-based starts, counts per side (d e f g / d e N f g) }
  var OldSeq:= Items(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']);
  var NewSeq:= Items(['a', 'b', 'c', 'd', 'e', 'N', 'f', 'g', 'h']);
  Assert.AreEqual('-4,4 +4,5', Ranges(BuildHunks(MyersDiff(OldSeq, NewSeq), NARROW_CONTEXT)));
  { a change at old position p (context 0) whose hunk holds old lines has OldStart = p+1,
    whichever of its delete / insert edits comes first... }
  OldSeq:= Items(['a', 'b', 'c']);
  NewSeq:= Items(['a', 'N', 'C']);
  Assert.AreEqual('-2,2 +2,2', Ranges(BuildHunks(MyersDiff(OldSeq, NewSeq), 0)));
  { ...and a side with NO lines in the hunk gives the line AFTER which the change sits (GNU
    diff): a pure insert after old line 2 is -2,0; an empty side is 0,0 }
  OldSeq:= Items(['a', 'b', 'c']);
  NewSeq:= Items(['a', 'b', 'N', 'c']);
  Assert.AreEqual('-2,0 +3,1', Ranges(BuildHunks(MyersDiff(OldSeq, NewSeq), 0)));
  Assert.AreEqual('-0,0 +1,2', Ranges(BuildHunks(MyersDiff(nil, Items(['x', 'y'])), UNIFIED_CONTEXT)));
  Assert.AreEqual('-1,2 +0,0', Ranges(BuildHunks(MyersDiff(Items(['x', 'y']), nil), UNIFIED_CONTEXT)));
  { a negative context counts as 0 }
  Assert.AreEqual('-2,0 +3,1', Ranges(BuildHunks(MyersDiff(OldSeq, NewSeq), -1)));
end;

procedure TDiffCoreTests.MovedBlockIsDeletePlusInsert;
begin
  var OldSeq:= Items(['a', 'b', 'c', 'd', 'e']);
  var NewSeq:= Items(['d', 'e', 'a', 'b', 'c']);
  var Edits:= MyersDiff(OldSeq, NewSeq);
  var Changed: Boolean;
  { the longer run (a b c) stays; the moved block (d e) is deleted and inserted again }
  Assert.AreEqual('=3 -2 +2', Counts(Edits, Changed));
  Assert.IsTrue(Changed, 'a move is reported as change');
  for var E in Edits do
    if E.Op = doEqual then
      Assert.AreNotEqual('d', OldSeq[E.OldIndex].Key, 'd is not matched across the move');
  Assert.AreEqual('deabc', Replay(OldSeq, NewSeq, Edits));
end;

procedure TDiffCoreTests.CountEditsReportsChange;
begin
  var Changed: Boolean;
  Assert.AreEqual('=0 -0 +0', Counts(nil, Changed));
  Assert.IsFalse(Changed, 'empty script = no change');
  Assert.AreEqual('=2 -0 +0', Counts(MyersDiff(Items(['a', 'b']), Items(['a', 'b'])), Changed));
  Assert.IsFalse(Changed, 'only equals = no change');
  Assert.AreEqual('=2 -1 +2', Counts(MyersDiff(Items(['a', 'b', 'c']), Items(['a', 'x', 'c', 'd'])), Changed));
  Assert.IsTrue(Changed);
end;

initialization
  TDUnitX.RegisterTestFixture(TDiffCoreTests);
end.
