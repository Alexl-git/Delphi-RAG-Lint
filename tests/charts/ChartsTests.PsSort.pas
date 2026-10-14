unit ChartsTests.PsSort;

(* Cases for DRagLint.Charts.PsSort. Every expected order was printed by PowerShell 7.6
  itself on 2026-10-13: `$rows | Sort-Object { $_.K } -Descending | % { $_.I }` over the keys
  shown (spec P3: the PS output is the reference). *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPsSortTests = class
  public
    [Test] procedure ThreeRowsSwapTies;
    [Test] procedure SixteenAndFewerKeepTies;
    [Test] procedure ManyRowsMatchSortObject;
    [Test] procedure EmptyAndSingleAreUntouched;
  end;

implementation

uses
  System.SysUtils, System.Generics.Defaults, DRagLint.Charts.PsSort;

const
  ANY_KEY = 7;

type
  TKeyed = record
    I: Integer;
    K: Integer;
  end;

function Rows(const pKeys: array of Integer): TArray<TKeyed>;
begin
  SetLength(Result, Length(pKeys));
  for var N:= 0 to High(pKeys) do
  begin
    Result[N].I:= N;
    Result[N].K:= pKeys[N];
  end;
end;

(* Sort-Object { $_.K } -Descending, then the input positions joined with ',' *)
function DescendingOrder(const pKeys: array of Integer): string;
begin
  var A:= Rows(pKeys);
  TPsSort<TKeyed>.Sort(A, function(const pL, pR: TKeyed): Integer begin Result:= pR.K - pL.K; end);
  var Parts: TArray<string>:= [];
  for var R in A do
    Parts:= Parts + [IntToStr(R.I)];
  Result:= string.Join(',', Parts);
end;

procedure TPsSortTests.ThreeRowsSwapTies;
begin
  { compare-and-swap of three: the tie (rows 0 and 1) comes out REVERSED; a stable sort gives 2,0,1 }
  Assert.AreEqual('2,1,0', DescendingOrder([1, 1, 2]));
  Assert.AreEqual('1,2,0', DescendingOrder([1, 2, 2]));
  Assert.AreEqual('0,2,1', DescendingOrder([2, 1, 2]));
end;

procedure TPsSortTests.SixteenAndFewerKeepTies;
begin
  { insertion sort: stable }
  Assert.AreEqual('1,3,5,0,2,4', DescendingOrder([0, 1, 0, 1, 0, 1]));
end;

procedure TPsSortTests.ManyRowsMatchSortObject;
begin
  { 24 rows: introsort; Sort-Object -Stable would give 0,6,9,18,23,3,7,12,... }
  Assert.AreEqual('0,18,9,6,23,14,3,7,20,19,12,16,21,1,17,5,4,13,22,10,2,8,15,11',
    DescendingOrder([2, 0, 0, 1, 0, 0, 2, 1, 0, 2, 0, 0, 1, 0, 1, 0, 1, 0, 2, 1, 1, 0, 0, 2]));
end;

procedure TPsSortTests.EmptyAndSingleAreUntouched;
begin
  Assert.AreEqual('', DescendingOrder([]));
  Assert.AreEqual('0', DescendingOrder([ANY_KEY]));
end;

end.
