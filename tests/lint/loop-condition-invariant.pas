unit LoopConditionInvariant;

interface

implementation

type
  TBox = class
    FBusy: Boolean;
    procedure Tick;
    procedure Run;
  end;

procedure TBox.Tick;
begin
  FBusy := False;
end;

procedure TBox.Run;
begin
  { FP shape: a field changed by a callee in the body }
  while FBusy do
    Tick;
end;

procedure Hit1(N: Integer);
var
  Done: Boolean;
begin
  Done := False;
  while not Done do // HIT
  begin
    WriteLn(N);
  end;
end;

procedure Hit2(Max: Integer);
var
  I: Integer;
begin
  I := 0;
  while I < Max do // HIT
    WriteLn(I);
end;

procedure NoHitModified(Max: Integer);
var
  I: Integer;
begin
  I := 0;
  while I < Max do
  begin
    Inc(I);
  end;
end;

procedure NoHitAssigned(Max: Integer);
var
  I: Integer;
begin
  I := 0;
  while I < Max do
    I := I + 1;
end;

procedure NoHitVarArg(Limit: Integer);
var
  Pos: Integer;
begin
  Pos := 1;
  { FP shape: the variable is handed to a call that may change it }
  while Pos <= Limit do
    Advance(Pos);
end;

procedure NoHitBreak(Max: Integer);
var
  I: Integer;
begin
  I := 0;
  { FP shape: the loop leaves through Break }
  while I < Max do
  begin
    if Check then Break;
  end;
end;

procedure NoHitCallInCondition;
var
  S: string;
begin
  { FP shape: a call in the condition is not invariant }
  while Next(S) do
    WriteLn(S);
end;

procedure NoHitExit(Flag: Boolean);
begin
  while Flag do
  begin
    if Check then Exit;
  end;
end;

end.
