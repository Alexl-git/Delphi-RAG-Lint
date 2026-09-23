unit uAssertFx;

{ Fixture for the `assert-with-side-effect` project lint rule (INBOX
  docs\INBOX-lint-rules-from-new-facts-2026-09-23.md section 4).

  Release builds compile Assert out (the C- switch), so a routine with a PROVEN effect
  called inside Assert's arguments runs only in Debug. Every Assert below is
  either a TRIGGER or a deliberate NON-triggering control, and the controls are
  the point: a proven effect-free callee, a binding gap ('?' only), an unbound
  callee, a plain expression, and a side-effecting call written OUTSIDE an
  Assert must all stay silent. Asserted by run_assert_side_effect.ps1, which
  reads every line number from the TRIGGER-n / CONTROL-n markers. }

interface

type
  TStack = class
  private
    FCount: Integer;
  public
    { Proven effect-free: reads its own field only. }
    function Peek: Integer;
    { Writes its own field -- summary 's'. }
    function Bump: Integer;
    { Only blocker is an UNBOUND callee -- summary '?', a gap, not an effect. }
    function Guess: Boolean;
  end;

function Pop(var AList: Integer): Integer;
function NextId: Integer;
procedure Driver;

var
  GNext: Integer;

implementation

function TStack.Peek: Integer;
begin
  Result:= FCount;
end;

function TStack.Bump: Integer;
begin
  FCount:= FCount + 1;
  Result:= FCount;
end;

function TStack.Guess: Boolean;
begin
  Result:= Trim('x') <> '';
end;

{ Writes through its var parameter -- summary 'p0'. }
function Pop(var AList: Integer): Integer;
begin
  AList:= AList - 1;
  Result:= AList;
end;

{ Writes a global -- summary 'g'. }
function NextId: Integer;
begin
  GNext:= GNext + 1;
  Result:= GNext;
end;

procedure Driver;
var
  N: Integer;
  S: TStack;
begin
  N:= 3;
  S:= TStack.Create;
  Assert(Pop(N) > 0);                    { TRIGGER-1: p0 }
  Assert(S.Bump > 0, 'bumped');          { TRIGGER-2: s }
  Assert(NextId() > 0);                  { TRIGGER-3: g (parens; its parenless twin is trigger five) }
  Assert(N >= 0,
    'left ' + IntToStr(Pop(N)));         { TRIGGER-4: in the message, wrapped }
  Assert(NextId > 0);                    { TRIGGER-5: g, PARENLESS -- a 'read' ref, a call edge since resolver 1.7.0 }
  Assert(S.Peek >= 0);                   { CONTROL-1: proven effect-free }
  Assert(S.Guess);                       { CONTROL-2: summary '?' only }
  Assert(Trim('y') <> '');               { CONTROL-3: unbound callee }
  Assert(N > -100);                      { CONTROL-4: plain expression }
  N:= Pop(N);                            { CONTROL-5: effect outside any Assert }
  if S.Bump > 0 then Assert(N > -100);   { CONTROL-6: same line, outside the Assert }
  N:= NextId(); // Assert(NextId() > 0)   CONTROL-7: the Assert is a comment
  N:= NextId;                            { CONTROL-8: parenless effect outside any Assert }
  S.Free;
end;

end.
