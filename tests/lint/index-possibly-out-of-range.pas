unit IndexPossiblyOutOfRange;

interface

implementation

uses
  System.SysUtils;

type
  TSmall = 0..9;

var
  GArr: array[0..9] of Integer;

function Calc: Integer;
begin
  Result:= 42;
end;

procedure HitPlainCalc;
var
  A: array[0..9] of Integer;
  i: Integer;
begin
  i:= Calc;
  A[i]:= 1;
end;

procedure HitIncBeforeAccess(const D: TArray<Integer>);
var
  i, s: Integer;
begin
  i:= 0;
  s:= 0;
  while i < Length(D) do
  begin
    Inc(i);
    s:= s + D[i];
  end;
end;

procedure HitOneSided;
var
  A: TBytes;
  i: Integer;
begin
  SetLength(A, 4);
  i:= Calc;
  i:= i - 1;
  if i < Length(A) then
    A[i]:= 0;
end;

procedure HitSubrange;
var
  A: array[0..9] of Integer;
  i: TSmall;
begin
  i:= Calc;
  A[i]:= 2;
end;

function HintParam(const D: TArray<Integer>; Idx: Integer): Integer;
begin
  Result:= D[Idx];
end;

procedure OkForLowHigh;
var
  A: array[0..9] of Integer;
  i: Integer;
begin
  for i:= Low(A) to High(A) do
    A[i]:= i;
end;

procedure OkForLength(const D: TArray<Integer>);
var
  i, s: Integer;
begin
  s:= 0;
  for i:= 0 to Length(D) - 1 do
    s:= s + D[i];
end;

procedure OkWhileIncAfter(const D: TArray<Integer>);
var
  i, s: Integer;
begin
  i:= 0;
  s:= 0;
  while i < Length(D) do
  begin
    s:= s + D[i];
    Inc(i);
  end;
end;

procedure OkInRange;
var
  A: array[0..9] of Integer;
  i: Integer;
begin
  i:= Calc;
  if (i >= Low(A)) and (i <= High(A)) then
    A[i]:= 3;
end;

procedure OkEarlyExit;
var
  A: array[0..9] of Integer;
  i: Integer;
begin
  i:= Calc;
  if (i < Low(A)) or (i > High(A)) then
    Exit;
  A[i]:= 4;
end;

procedure OkEarlyRaise(const D: TArray<Integer>);
var
  i: Integer;
begin
  i:= Calc;
  if (i < 0) or (i >= Length(D)) then
    raise Exception.Create('bad');
  D[i]:= 5;
end;

procedure OkDualUse;
var
  A: array[0..9] of Integer;
  n: Integer;
begin
  n:= Calc;
  A[3]:= n;
end;

procedure OkString;
var
  S: string;
  i: Integer;
begin
  S:= 'abc';
  i:= Calc;
  S[i]:= 'x';
end;

function OkGuardedParam(const D: TArray<Integer>; Idx: Integer): Integer;
begin
  Result:= 0;
  if (Idx >= 0) and (Idx < Length(D)) then
    Result:= D[Idx];
end;

procedure HitNoAnchor(const D: TArray<Integer>; X: Boolean);
var
  i: Integer;
begin
  i:= Calc;
  if X then D[i]:= 1;
end;

procedure OkLengthAlias(const D: TArray<Integer>);
var
  i, n, s: Integer;
begin
  n:= Length(D);
  s:= 0;
  i:= 0;
  while i < n do
  begin
    s:= s + D[i];
    Inc(i);
  end;
end;

function OkShortCircuit(const D: TArray<Integer>; P: Integer): Integer;
var
  k: Integer;
begin
  k:= P;
  while (k >= 0) and (k < Length(D)) and (D[k] <> 0) do
    Inc(k);
  Result:= k;
end;

procedure OkGrowOnDemand(var Rows: TArray<Integer>);
var
  n: Integer;
begin
  n:= 0;
  SetLength(Rows, 4);
  while n < 100 do
  begin
    if n >= Length(Rows) then
      SetLength(Rows, Length(Rows) * 2);
    Rows[n]:= n;
    Inc(n);
  end;
end;

procedure HitWrongOrder;
var
  A: array[0..8] of Integer;
  i: Integer;
begin
  i:= 0;
  while (A[i] = 0) and (i <= 8) do
    Inc(i);
end;

function OkIfExprAndLaterReuse(const D: TArray<Integer>; const S: string): Integer;
var
  i: Integer;
begin
  i:= 0;
  while (i < Length(D)) and (D[i] <> 0) do
    Inc(i);
  Result:= if i < Length(D) then D[i] else 0;
  i:= Pos('x', S);
  Result:= Result + i;
end;

{ ---- 1.52 lane IDXRANGE2: C1 parallel arrays (owner 2026-11-17) ---- }

procedure OkParallelSetLength(const Names: TStrings);
var
  Values: TArray<Integer>;
  i: Integer;
begin
  SetLength(Values, Names.Count);
  for i:= 0 to Names.Count - 1 do
    Values[i]:= i;
end;

procedure HitParallelUnsized(const Names: TStrings; var Values: TArray<Integer>);
var
  i: Integer;
begin
  for i:= 0 to Names.Count - 1 do
    Values[i]:= i;
end;

procedure OkParallelStatic;
var
  Names: array[0..9] of string;
  Values: array[0..9] of Integer;
  i: Integer;
begin
  for i:= Low(Names) to High(Names) do
    Values[i]:= Length(Names[i]);
end;

procedure HitParallelStaticSmaller;
var
  Names: array[0..9] of string;
  Values: array[0..4] of Integer;
  i: Integer;
begin
  for i:= Low(Names) to High(Names) do
    Values[i]:= Length(Names[i]);
end;

procedure OkParallelSameSource(N: Integer);
var
  A, B: TArray<Integer>;
  i: Integer;
begin
  SetLength(A, N);
  SetLength(B, N);
  for i:= 0 to High(B) do
    A[i]:= B[i];
end;

procedure HitParallelDiffer(RowCount, ColCount: Integer);
var
  Rows, Cols: TArray<Integer>;
  i: Integer;
begin
  SetLength(Rows, ColCount);
  SetLength(Cols, RowCount);
  for i:= 0 to High(Cols) do
    Rows[i]:= i;
end;

procedure OkParallelWhile(const Names: TStrings);
var
  Values: TArray<Integer>;
  i: Integer;
begin
  SetLength(Values, Names.Count);
  i:= 0;
  while i < Names.Count do
  begin
    Values[i]:= i;
    Inc(i);
  end;
end;

procedure MarkAll(const Toks: TStrings; var Marks: TArray<Boolean>);
var
  j: Integer;
begin
  j:= 0;
  while j < Toks.Count do
  begin
    Marks[j]:= True;
    Inc(j);
  end;
end;

function MarksOf(const L: TStrings): TArray<Boolean>;
begin
  SetLength(Result, L.Count);
  MarkAll(L, Result);
end;

procedure MarkSome(const Toks: TStrings; var Marks: TArray<Boolean>);
var
  j: Integer;
begin
  j:= 0;
  while j < Toks.Count do
  begin
    Marks[j]:= True;
    Inc(j);
  end;
end;

procedure MarkSomeCaller(const L: TStrings);
var
  R: TArray<Boolean>;
begin
  SetLength(R, 3);
  MarkSome(L, R);
end;

{ ---- C2 unchecked index parameter: local callers ---- }

function ItemAt(const D: TArray<Integer>; Idx: Integer): Integer;
begin
  Result:= D[Idx];
end;

function SumAll(const D: TArray<Integer>): Integer;
var
  k: Integer;
begin
  Result:= 0;
  for k:= 0 to High(D) do
    Result:= Result + ItemAt(D, k);
end;

function ItemAt2(const D: TArray<Integer>; Idx: Integer): Integer;
begin
  Result:= D[Idx];
end;

function UseItemAt2(const D: TArray<Integer>): Integer;
begin
  Result:= ItemAt2(D, 0) + ItemAt2(D, Length(D));
end;

function TableAt(Idx: Integer): Integer;
begin
  Result:= GArr[Idx];
end;

function UseTableAt: Integer;
var
  k: Integer;
begin
  Result:= TableAt(3);
  for k:= Low(GArr) to High(GArr) do
    Result:= Result + TableAt(k);
end;

function ItemAt3(const D: TArray<Integer>; Idx: Integer): Integer;
begin
  Result:= D[Idx];
end;

procedure TakesAddress;
var
  P: Pointer;
begin
  P:= @ItemAt3;
  if P = nil then Exit;
end;

{ ---- ORM3 batch 3 (2026-11-17) patterns ---- }

procedure OkOverAllocated(const Data: array of Double);
var
  Used: array of Boolean;
  J: Integer;
begin
  SetLength(Used, High(Data) - Low(Data) + 3);
  J:= Low(Data);
  while Used[J] and (J <= High(Data)) do
    Inc(J);
end;

procedure HitExactAllocated(const Data: array of Double);
var
  Used: array of Boolean;
  J: Integer;
begin
  SetLength(Used, High(Data) - Low(Data) + 1);
  J:= Low(Data);
  while Used[J] and (J <= High(Data)) do
    Inc(J);
end;

procedure HitNssConvert(var N: Integer);
const
  NssConv: array[0..4] of Integer = (1, 2, 3, 4, 5);
var
  Hist: array[0..8] of Integer;
  i: Integer;
begin
  i:= 0;
  while (Hist[i] = 0) and (i <= 4) do Inc(i);
  N:= NssConv[i];
end;

procedure SplitInto(const S: string; c: Char; var sa: array of string);
var
  i, j: Integer;
begin
  j:= Low(sa);
  for i:= 1 to Length(S) do
  begin
    if S[i] <> c then
      sa[j]:= sa[j] + S[i]
    else
    begin
      Inc(j);
      if j > High(sa) - 1 then
      begin
        sa[j]:= Copy(S, i + 1, MaxInt);
        Exit;
      end;
    end;
  end;
end;

procedure UseSplitInto(const S: string);
var
  Tokens: array[0..10] of string;
begin
  SplitInto(S, ',', Tokens);
end;

procedure SplitOne(const S: string; c: Char; var sa: array of string);
var
  i, j: Integer;
begin
  j:= Low(sa);
  for i:= 1 to Length(S) do
  begin
    if S[i] <> c then
      sa[j]:= sa[j] + S[i]
    else
    begin
      Inc(j);
      if j > High(sa) - 1 then
      begin
        sa[j]:= Copy(S, i + 1, MaxInt);
        Exit;
      end;
    end;
  end;
end;

procedure UseSplitOne(const S: string);
var
  One: array[0..0] of string;
begin
  SplitOne(S, ',', One);
end;

function LookupIndex(const Cols: TDictionary<string, Integer>; const Name: string): Integer;
var
  Picks: array[1..8] of Integer;
  colidx: Integer;
begin
  Result:= 0;
  colidx:= Cols.GetValueOrDefault(Name, -1);
  if colidx > 0 then
    Result:= Picks[colidx];
end;

procedure OkCountInvariant(ColCount: Integer; const Src: TArray<Integer>);
var
  Rows: TArray<Integer>;
  RowCount: Integer;
begin
  SetLength(Rows, ColCount);
  RowCount:= 0;
  for var I: Integer:= 2 to ColCount - 1 do
  begin
    if Src[I] = 0 then Continue;
    Rows[RowCount]:= I;
    Inc(RowCount);
  end;
end;

procedure HitCountInvariant(ColCount: Integer);
var
  Rows: TArray<Integer>;
  RowCount: Integer;
begin
  SetLength(Rows, ColCount);
  RowCount:= 0;
  for var I: Integer:= 0 to ColCount do
  begin
    Rows[RowCount]:= I;
    Inc(RowCount);
  end;
end;

end.
