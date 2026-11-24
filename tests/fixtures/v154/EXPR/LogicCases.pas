unit LogicCases;

{ Fixture of lane EXPR: a line that must report ends in "// FIRE <rule>"; every other line must stay silent.
  Never compiled; only indexed and linted. }

interface

type
  TFoo = class
    function Total: Integer;
  end;

implementation

var
  A, B, X, Y, Flag, Other, N, Q, Flags, K, Cnt: Integer;
  C: Char;
  Map: TMap;
  Obj: TFoo;

procedure Duplicates;
begin
  if (A = 1) or (A = 1) then Exit; // FIRE duplicate-logical-operand
  if (A = 1) and (B = 2) and (a=1) then Exit; // FIRE duplicate-logical-operand
  if Assigned(Q) or Assigned(Q) then Exit; // FIRE duplicate-logical-operand
  if (A = 1) or (A = 2) then Exit;
  if (A = 1) and (B = 1) then Exit;
  if (Next(Q) = 1) or (Next(Q) = 1) then Exit;
  if Next(Q) or Next(Q) then Exit;
  if Flags and Flags then Exit;
  Flag := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
  if Map.TryGetValue(K, Cnt) and (Cnt = 1) and Map.TryGetValue(K, Cnt) and (Cnt = 1) then Exit;
  if (A = 1) or (B = 1) or (A = 2) then Exit;
end;

procedure Contradictions;
begin
  if (X > 5) and (X < 3) then Exit; // FIRE contradictory-condition
  if (X = 1) and (X = 2) then Exit; // FIRE contradictory-condition
  if (X > 3) and (X < 3) then Exit; // FIRE contradictory-condition
  if (X = 1) and (X <> 1) then Exit; // FIRE contradictory-condition
  if (5 < X) and (X < 3) then Exit; // FIRE contradictory-condition
  if (X >= 3) and (X <= 3) then Exit;
  if (X > 5) and (X < 6) then Exit;
  if (X > 5) and (Y < 3) then Exit;
  if (X > 5) or (X < 3) then Exit;
  if (X > 5) and (Next(X) < 3) then Exit;
  if (X = 1) and (X <> 2) then Exit;
end;

procedure Precedence;
begin
  if Flag and Other = False then Exit; // FIRE boolean-comparison-precedence
  if Flag = True and Other then Exit; // FIRE boolean-comparison-precedence
  if Flags and 4 = 0 then Exit;
  if (Flag and Other) = False then Exit;
  if Flag and (Other = False) then Exit;
end;

function Counter: Integer;
begin
  Counter := 0;
  Counter := Counter + X; // FIRE function-name-reads-itself
end;

function TFoo.Total: Integer;
begin
  Total := 1;
  Total := Total + 1; // FIRE function-name-reads-itself
  Q := Obj.Total;
  Q := Total();
  Q := Integer(@Total);
end;

function Fact(N: Integer): Integer;
begin
  if N <= 1 then Fact := 1 else Fact := N * Fact(N - 1);
end;

function Plain: Integer;
begin
  Result := 1;
  if Plain > 0 then Exit;
end;

function Outer: Integer;
  function Inner: Integer;
  begin
    Outer := Outer + 1;
  end;
begin
  Outer := 1;
end;

end.
