unit DRagLint.Charts.PsSort;

(* PowerShell's Sort-Object row order, for the ported chart emitters (spec P3/P4).

  PS TRAP CLOSED HERE: Sort-Object is NOT a stable sort. Without -Stable it hands the rows
  to List<T>.Sort, i.e. .NET's ArraySortHelper introsort: two or three rows are ordered by
  compare-and-swap (so EQUAL keys can change places already at three rows), four to sixteen
  by insertion sort (stable), and more by median-of-three quicksort with a heapsort
  fallback. A chart that sorts groups by a count, e.g. `Sort-Object { $_.Count } -Descending`,
  therefore puts tied groups in an order no stable sort reproduces. This unit is a line-for-
  line port of that algorithm (dotnet/runtime ArraySortHelper<T>.IntroSort, the generic
  Comparison overload), measured 2026-10-13 against Sort-Object under pwsh 7.6 on 1,495
  random arrays of 2..300 rows with four tied key values: 0 differences. *)

interface

uses
  System.Generics.Defaults;

type
  /// <summary>Sort-Object's order for an array, ties included.</summary>
  /// <remarks>Use as <c>TPsSort&lt;TRow&gt;.Sort(Rows, Compare)</c>. The fields and private
  /// routines are the working state of one sort (the array and the comparison); every routine
  /// works on the 0-based slice [pLo, pLo + pCount) of FItems.</remarks>
  TPsSort<T> = record
  private const
    { ArraySortHelper.IntrosortSizeThreshold }
    INTROSORT_SIZE_THRESHOLD = 16;
    PAIR = 2;
    TRIPLE = 3;
  private
    FItems  : TArray<T>;
    FCompare: TComparison<T>;
    procedure Swap(pI, pJ: Integer);
    procedure SwapIfGreater(pI, pJ: Integer);
    procedure InsertionSort(pLo, pCount: Integer);
    function PickPivotAndPartition(pLo, pCount: Integer): Integer;
    procedure DownHeap(pLo, pI, pN: Integer);
    procedure HeapSort(pLo, pCount: Integer);
    procedure IntroSort(pLo, pCount, pDepthLimit: Integer);
    class function Log2Floor(pN: Cardinal): Integer; static;
  public
    /// <summary>Sorts in place exactly as PowerShell 7 Sort-Object (without -Stable) does.</summary>
    /// <param name="pItems">The rows, in input order; sorted in place.</param>
    /// <param name="pCompare">The key comparison Sort-Object applies: negative, zero or positive.
    /// For -Descending pass the reversed comparison (Sort-Object negates its comparer).</param>
    /// <remarks>Equal keys are NOT kept in input order (see the unit header): that is the
    /// point. Pure; allocates nothing beyond the call stack.</remarks>
    class procedure Sort(var pItems: TArray<T>; const pCompare: TComparison<T>); static;
  end;

implementation

procedure TPsSort<T>.Swap(pI, pJ: Integer);
begin
  var X:= FItems[pI];
  FItems[pI]:= FItems[pJ];
  FItems[pJ]:= X;
end;

procedure TPsSort<T>.SwapIfGreater(pI, pJ: Integer);
begin
  if FCompare(FItems[pI], FItems[pJ]) > 0 then
    Swap(pI, pJ);
end;

procedure TPsSort<T>.InsertionSort(pLo, pCount: Integer);
begin
  for var I:= 0 to pCount - 2 do
  begin
    var X:= FItems[pLo + I + 1];
    var J:= I;
    while (J >= 0) and (FCompare(X, FItems[pLo + J]) < 0) do
    begin
      FItems[pLo + J + 1]:= FItems[pLo + J];
      Dec(J);
    end;
    FItems[pLo + J + 1]:= X;
  end;
end;

function TPsSort<T>.PickPivotAndPartition(pLo, pCount: Integer): Integer;
begin
  var Hi:= pCount - 1;
  var Middle:= Hi shr 1;
  SwapIfGreater(pLo, pLo + Middle);
  SwapIfGreater(pLo, pLo + Hi);
  SwapIfGreater(pLo + Middle, pLo + Hi);
  var Pivot:= FItems[pLo + Middle];
  Swap(pLo + Middle, pLo + Hi - 1);
  var Left:= 0;
  var Right:= Hi - 1;
  while Left < Right do
  begin
    repeat
      Inc(Left);
    until not (FCompare(FItems[pLo + Left], Pivot) < 0);
    repeat
      Dec(Right);
    until not (FCompare(Pivot, FItems[pLo + Right]) < 0);
    if Left >= Right then
      Break;
    Swap(pLo + Left, pLo + Right);
  end;
  if Left <> Hi - 1 then
    Swap(pLo + Left, pLo + Hi - 1);
  Result:= Left;
end;

procedure TPsSort<T>.DownHeap(pLo, pI, pN: Integer);
begin
  var D:= FItems[pLo + pI - 1];
  var I:= pI;
  while I <= pN shr 1 do
  begin
    var Child:= 2 * I;
    if (Child < pN) and (FCompare(FItems[pLo + Child - 1], FItems[pLo + Child]) < 0) then
      Inc(Child);
    if not (FCompare(D, FItems[pLo + Child - 1]) < 0) then
      Break;
    FItems[pLo + I - 1]:= FItems[pLo + Child - 1];
    I:= Child;
  end;
  FItems[pLo + I - 1]:= D;
end;

procedure TPsSort<T>.HeapSort(pLo, pCount: Integer);
begin
  for var I:= pCount shr 1 downto 1 do
    DownHeap(pLo, I, pCount);
  for var I:= pCount downto 2 do
  begin
    Swap(pLo, pLo + I - 1);
    DownHeap(pLo, 1, I - 1);
  end;
end;

procedure TPsSort<T>.IntroSort(pLo, pCount, pDepthLimit: Integer);
begin
  var Count:= pCount;
  var Depth:= pDepthLimit;
  while Count > 1 do
  begin
    if Count <= INTROSORT_SIZE_THRESHOLD then
    begin
      if Count = PAIR then
        SwapIfGreater(pLo, pLo + 1)
      else if Count = TRIPLE then
      begin
        SwapIfGreater(pLo, pLo + 1);
        SwapIfGreater(pLo, pLo + 2);
        SwapIfGreater(pLo + 1, pLo + 2);
      end
      else
        InsertionSort(pLo, Count);
      Exit;
    end;
    if Depth = 0 then
    begin
      HeapSort(pLo, Count);
      Exit;
    end;
    Dec(Depth);
    var P:= PickPivotAndPartition(pLo, Count);
    IntroSort(pLo + P + 1, Count - (P + 1), Depth);
    Count:= P;
  end;
end;

{ floor(log2(n)) for n >= 1, as BitOperations.Log2 }
class function TPsSort<T>.Log2Floor(pN: Cardinal): Integer;
begin
  Result:= 0;
  var N:= pN;
  while N > 1 do
  begin
    N:= N shr 1;
    Inc(Result);
  end;
end;

class procedure TPsSort<T>.Sort(var pItems: TArray<T>; const pCompare: TComparison<T>);
var
  S: TPsSort<T>;
begin
  if Length(pItems) <= 1 then
    Exit;
  S.FItems:= pItems;
  S.FCompare:= pCompare;
  S.IntroSort(0, Length(pItems), 2 * (Log2Floor(Length(pItems)) + 1));
  pItems:= S.FItems;
end;

end.
