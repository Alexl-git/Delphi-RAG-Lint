unit uCycle;
{ Purity v2 stage fixture: the fixpoint (acceptance 8, 9, 10). }
interface
function IsEven(N: Integer): Boolean;
function IsOdd(N: Integer): Boolean;
procedure A1;
procedure B1;
procedure C1;
procedure SelfLoop(N: Integer);
implementation
var
  GHit: Integer;
function IsEven(N: Integer): Boolean;
begin
  if N = 0 then Exit(True);
  Result := IsOdd(N - 1);
end;
function IsOdd(N: Integer): Boolean;
begin
  if N = 0 then Exit(False);
  Result := IsEven(N - 1);
end;
procedure A1;
begin
  B1;
end;
procedure B1;
begin
  A1;
  C1;
end;
procedure C1;
begin
  GHit := 1;
end;
procedure SelfLoop(N: Integer);
begin
  if N > 0 then SelfLoop(N - 1);
end;
end.
