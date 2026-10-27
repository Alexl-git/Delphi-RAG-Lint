unit UnconditionalRecursion;

interface

implementation

type
  TNode = class
    FInner: TNode;
    procedure Walk;
    function Depth: Integer;
    procedure Save(const S: string); overload;
    procedure Save(const S: string; N: Integer); overload;
    procedure Delegate;
  end;

procedure TNode.Walk;
begin
  WriteLn('walking');
  Walk; // HIT
end;

function TNode.Depth: Integer;
begin
  Result := Depth + 1; // HIT
end;

function Fact(N: Integer): Integer;
begin
  Result := N * Fact(N - 1); // HIT
end;

function FactOk(N: Integer): Integer;
begin
  { FP shape: a guard before the recursive call }
  if N <= 1 then
    Result := 1
  else
    Result := N * FactOk(N - 1);
end;

function FactOk2(N: Integer): Integer;
begin
  { FP shape: an early Exit before the recursive call }
  Result := 1;
  if N <= 1 then Exit;
  Result := N * FactOk2(N - 1);
end;

procedure TNode.Save(const S: string);
begin
  { FP shape: overload with another signature }
  Save(S, 0);
end;

procedure TNode.Save(const S: string; N: Integer);
begin
  WriteLn(S, N);
end;

procedure TNode.Delegate;
begin
  { FP shape: same name on ANOTHER object }
  FInner.Delegate;
end;

procedure Loop(N: Integer);
var
  I: Integer;
begin
  { FP shape: recursion inside a loop is conditional on the loop running }
  for I := 0 to N do
    Loop(I);
end;

end.
