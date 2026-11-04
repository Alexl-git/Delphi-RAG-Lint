unit uLoopInv;

{ Fixture for the `effect-free-in-loop-invariant` project lint rule (1.42,
  TRIAGE #35, INBOX-new-rules-from-graph-and-converter-facts section D).

  An effect-free call inside a loop whose arguments, and the state it reads,
  cannot change in that loop is a provable hoist. Every line below is a TRIGGER
  or a deliberate CONTROL; the runner reads each line number from its
  LI-TRIGGER-n / LI-CONTROL-n marker. }

interface

type
  TBox = class
  private
    FBase: Integer;
    FOther: Integer;
  public
    { Effect-free, reads its own field: only a loop that writes nothing else may hoist it. }
    function Score(A: Integer): Integer;
    { Effect-free, reads no state at all: hoistable from any loop. }
    function Pure(A: Integer): Integer;
    { A one-line accessor: proven, and not worth hoisting. }
    function Base: Integer;
    { Writes its own field. }
    procedure Bump;
    procedure LoopOverField;
  end;

  TOtherBox = class
  private
    FX: Integer;
  public
    function Twin(A: Integer): Integer;
    function Rate(A: Integer): Integer;
  end;

  TOtherBox2 = class
  private
    FY: Integer;
  public
    { Same name as TOtherBox.Twin, and it writes: the name is not proven. }
    function Twin(A: Integer): Integer;
  end;

function Sq(A: Integer): Integer;
function ReadsGlobal(A: Integer): Integer;
function NextId: Integer;
procedure Log(A: Integer);
procedure Mutate(var A: Integer);
procedure Driver(pIn: Integer; var pRef: Integer);

const
  CK = 7;

var
  GSeq: Integer;

implementation

function TBox.Score(A: Integer): Integer;
begin
  Result:= A * FBase + 1;
end;

function TBox.Pure(A: Integer): Integer;
begin
  Result:= A * 2 + 1;
end;

function TBox.Base: Integer;
begin
  Result:= FBase;
end;

procedure TBox.Bump;
begin
  FBase:= FBase + 1;
end;

function TOtherBox.Twin(A: Integer): Integer;
begin
  Result:= A * 3 + 1;
end;

function TOtherBox.Rate(A: Integer): Integer;
begin
  Result:= A * FX + 1;
end;

function TOtherBox2.Twin(A: Integer): Integer;
begin
  FY:= A;
  Result:= A;
end;

function Sq(A: Integer): Integer;
begin
  Result:= A * A + 1;
end;

function ReadsGlobal(A: Integer): Integer;
begin
  Result:= A + GSeq;
end;

function NextId: Integer;
begin
  GSeq:= GSeq + 1;
  Result:= GSeq;
end;

procedure Log(A: Integer);
begin
  GSeq:= A;
end;

procedure Mutate(var A: Integer);
begin
  A:= A + 1;
end;

procedure TBox.LoopOverField;
var
  I, R: Integer;
begin
  R:= 0;
  for I:= 0 to 3 do
  begin
    Log(I);
    R:= R + Sq(FOther);          { LI-CONTROL-1: a field argument, and Log may change it }
  end;
  for I:= 0 to 3 do
    R:= R + Sq(FOther);          { LI-TRIGGER-9: a field argument, and the loop writes only locals }
  FOther:= R;
end;

procedure AddressTaken;
var
  I, N, R: Integer;
  P: ^Integer;
begin
  N:= 3;
  R:= 0;
  P:= @N;
  for I:= 0 to 3 do
  begin
    P^:= I;
    R:= R + Sq(N);                             { LI-CONTROL-9: the address of N was taken before the loop }
  end;
  Log(R);
end;

{ A nested routine that does not touch the argument changes nothing. }
procedure NestedElsewhere;
var
  I, N, R, M: Integer;

  procedure Other;
  begin
    M:= 1;
  end;

begin
  N:= 3;
  R:= 0;
  Other;
  for I:= 0 to 3 do
  begin
    Log(I);
    R:= R + Sq(N);                             { LI-TRIGGER-12: the nested routine writes M, not N }
  end;
  Log(R + M);
end;

procedure NestedWrites;
var
  I, N, R: Integer;

  procedure Step;
  begin
    N:= N + 1;
  end;

begin
  N:= 3;
  R:= 0;
  for I:= 0 to 3 do
  begin
    Step;
    R:= R + Sq(N);                             { LI-CONTROL-21: the nested routine writes N }
  end;
  Log(R);
end;

procedure WithClosure;
var
  I, N, R: Integer;
  Fn: TFunc<Integer>;
begin
  N:= 3;
  R:= 0;
  Fn:= function: Integer begin N:= N + 1; Result:= N; end;
  for I:= 0 to 3 do
  begin
    Fn();
    R:= R + Sq(N);                             { LI-CONTROL-19: a closure writes the argument }
  end;
  Log(R);
end;

procedure Driver(pIn: Integer; var pRef: Integer);
var
  I, N, R, V: Integer;
  Arr: array[0..3] of Integer;
  Items: array of Integer;
  B, C: TBox;
  O: TOtherBox;
begin
  N:= 3;
  R:= 0;
  I:= 0;
  B:= TBox.Create;
  C:= TBox.Create;
  O:= TOtherBox.Create;

  for I:= 0 to 3 do Arr[I]:= Sq(N);            { LI-TRIGGER-1: for body, local argument }
  while I < 3 do
  begin
    R:= R + Sq(pIn);                           { LI-TRIGGER-2: while body, value parameter }
    Inc(I);
  end;
  while Sq(N) > I do Inc(I);                   { LI-TRIGGER-3: while condition runs every iteration }
  repeat
    Inc(I);
  until Sq(N) < I;                             { LI-TRIGGER-4: until condition runs every iteration }
  for I:= 0 to 3 do R:= R + B.Score(N);        { LI-TRIGGER-5: reads Self state, the loop writes only locals }
  for I:= 0 to 3 do
  begin
    Log(I);
    R:= R + Sq(N);                             { LI-TRIGGER-6: an effectful loop, a callee that reads no state }
  end;
  for V in Items do R:= R + Sq(N);             { LI-TRIGGER-7: foreach body }
  for I:= 0 to 3 do R:= R + Sq(CK) + Sq(5);    { LI-TRIGGER-8: named constant and literal }
  for I:= 0 to 3 do
  begin
    Log(I);
    R:= R + B.Pure(N);                         { LI-TRIGGER-10: a stateless method on a receiver the loop keeps }
  end;

  for I:= 0 to 3 do R:= R + Sq(I);             { LI-CONTROL-2: the loop variable }
  for I:= 0 to 3 do
  begin
    N:= N + 1;
    R:= R + Sq(N);                             { LI-CONTROL-3: argument assigned in the loop }
  end;
  for I:= 0 to 3 do
  begin
    Inc(N);
    R:= R + Sq(N);                             { LI-CONTROL-4: argument changed by Inc }
  end;
  for I:= 0 to 3 do
  begin
    Mutate(N);
    R:= R + Sq(N);                             { LI-CONTROL-5: argument handed to a var parameter }
  end;
  for I:= 0 to 3 do
  begin
    B.Bump;
    R:= R + B.Score(N);                        { LI-CONTROL-6: state the callee reads changes }
  end;
  for I:= 0 to 3 do
  begin
    R:= R + B.Pure(N);                         { LI-CONTROL-7: the receiver changes }
    B:= C;
  end;
  for I:= 0 to 3 do
  begin
    Unknown(I);
    R:= R + B.Score(N);                        { LI-CONTROL-8: an unbound call may change what it reads }
  end;
  R:= R + Sq(N);                               { LI-CONTROL-10: no loop }
  for I:= 0 to Sq(N) do Log(I);                { LI-CONTROL-11: a for bound is evaluated once }
  for I:= 0 to 3 do
    R:= R + NextId;                            { LI-CONTROL-12: the callee has an effect }
  for I:= 0 to 3 do
    R:= R + B.Base;                            { LI-CONTROL-13: one-line accessor }
  for I:= 0 to 3 do
    R:= R + O.Twin(N);                         { LI-CONTROL-14: a same-named routine writes }
  for I:= 0 to 3 do
  begin
    Log(I);
    R:= R + ReadsGlobal(N);                    { LI-CONTROL-15: reads a global, Log writes it }
  end;
  for I:= 0 to 3 do
  begin
    var W: Integer:= I * 2;
    R:= R + Sq(W);                             { LI-CONTROL-16: inline variable set per iteration }
  end;
  for I:= 0 to 3 do
  begin
    Log(I);
    R:= R + Sq(pRef);                          { LI-CONTROL-17: a var parameter may alias what Log writes }
  end;
  with B do
    for I:= 0 to 3 do
      R:= R + Sq(N);                           { LI-CONTROL-18: with may rebind the name }
  for I:= 0 to 3 do
  begin
    O.FX:= I;
    R:= R + O.Rate(N);                         { LI-CONTROL-20: a heap write in the loop, the callee reads it }
  end;
  for I:= 0 to 3 do
  begin
    if I = 2 then Continue;
    R:= R + Length('a') + B.Score(N);          { LI-TRIGGER-11: flow control and an intrinsic keep the loop frozen }
  end;
  B.Free;
  C.Free;
  O.Free;
end;

end.
