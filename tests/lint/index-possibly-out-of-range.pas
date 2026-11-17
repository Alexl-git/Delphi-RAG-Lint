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

end.
