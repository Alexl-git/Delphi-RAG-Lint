unit IdxRangeSlz;

interface

implementation

const
  CNotFound = -1;

function PickIdx(const A: TArray<Integer>; AWant: Integer): Integer;
var
  I: Integer;
begin
  Result := CNotFound;
  for I := 0 to High(A) do
    if A[I] = AWant then Exit(I);
end;

{ 1.52.1 SLZ-RULE2 FP shapes (self-LoopZero) -- each must stay silent. }

{ A: Inc-only scan whose start copies another Inc-only local that starts at 0 (ProjectRules.pas:1805) }
procedure PairScan(const Sites: TArray<Integer>);
var
  A, B: Integer;
begin
  A := 0;
  while A < Length(Sites) do
  begin
    B := A;
    while (B < Length(Sites)) and (Sites[B] = Sites[A]) do Inc(B);
    A := B;
  end;
end;

{ A: the upper side in an or-chain before the access, a local started at 0 (DisallowedChecks.pas:226) }
function OrChainGuard(const ATok, ASegs: TArray<string>): Boolean;
var
  P, K: Integer;
begin
  Result := False;
  P := 0;
  for K := 0 to High(ASegs) do
  begin
    if (P > High(ATok)) or (ATok[P] <> ASegs[K]) then Exit;
    Inc(P);
  end;
  Result := True;
end;

procedure TakeRange(AFrom, ATo: Integer);
begin
end;

procedure TakeRangeVar(var AFrom: Integer; ATo: Integer);
begin
  AFrom := ATo - 100;
end;

{ A: the index handed BY VALUE to a routine of this file between the guard and the next pass
  (ProjectRules.pas:1805, ReportName(A, B, ..)) -- the call cannot move it }
procedure PairScanCall(const Sites: TArray<Integer>);
var
  A, B: Integer;
begin
  A := 0;
  while A < Length(Sites) do
  begin
    B := A;
    while (B < Length(Sites)) and (Sites[B] = Sites[A]) do Inc(B);
    TakeRange(A, B);
    A := B;
  end;
end;
{ D: sentinel tested and left before the access (CyclePlan.pas:2680) }
function SentinelExit(const A: TArray<Integer>): Integer;
var
  Best: Integer;
begin
  Best := PickIdx(A, 3);
  if Best = CNotFound then Exit(0);
  Result := A[Best];
end;

{ D: the else arm of the sentinel test (ReportHeader.pas:423) }
function SentinelTernary(const A: TArray<Integer>): Integer;
begin
  var I := PickIdx(A, 4);
  Result := if I = CNotFound then 0 else A[I];
end;

{ D: `< 0 then Continue` (CMP.pas:1280) }
function NegativeContinue(const A, Wants: TArray<Integer>): Integer;
var
  W, Idx: Integer;
begin
  Result := 0;
  for W in Wants do
  begin
    Idx := PickIdx(A, W);
    if Idx < 0 then Continue;
    Inc(Result, A[Idx]);
  end;
end;

{ E: an unsigned hash mod the array's length (Q.ExceptionPaths.pas:417) }
procedure ModIndex(var ABuckets: TArray<Integer>; AHash: Cardinal);
var
  B: Integer;
begin
  if Length(ABuckets) = 0 then Exit;
  B := Integer(AHash mod Cardinal(Length(ABuckets)));
  ABuckets[B] := 1;
end;

{ ---- controls: each must keep firing ---- }

function CtlOtherValueExit(const A: TArray<Integer>): Integer;
var
  Best: Integer;
begin
  Best := PickIdx(A, 3);
  if Best = 5 then Exit(0);
  Result := A[Best];
end;

function CtlSentinelNoLeave(const A: TArray<Integer>): Integer;
var
  Best: Integer;
begin
  Result := 0;
  Best := PickIdx(A, 3);
  if Best = CNotFound then Result := -1;
  Result := Result + A[Best];
end;

procedure CtlSignedMod(var ABuckets: TArray<Integer>; AKey: Integer);
var
  B: Integer;
begin
  if Length(ABuckets) = 0 then Exit;
  B := AKey mod Length(ABuckets);
  ABuckets[B] := 1;
end;

procedure CtlParallel(const A: TArray<Integer>; var B: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    B[I] := A[I];
end;

function CtlParamIndex(const A: TArray<Integer>; AIdx: Integer): Integer;
begin
  Result := A[AIdx];
end;

procedure CtlPairScanVarCall(const Sites: TArray<Integer>);
var
  A, B: Integer;
begin
  A := 0;
  while A < Length(Sites) do
  begin
    B := A;
    while (B < Length(Sites)) and (Sites[B] = Sites[A]) do Inc(B);
    TakeRangeVar(A, B);
    A := B;
  end;
end;
end.