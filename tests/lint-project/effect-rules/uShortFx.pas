unit uShortFx;

{ Fixture for the `side-effect-in-short-circuit` project lint rule (backlog
  1.37.0 lane B-EFFECT; INBOX-lint-rules-from-new-facts-2026-09-23 rule 5).

  A routine with a PROVEN effect called in the RIGHT operand of a Boolean
  `and` / `or` runs only when the left operand does not already decide the
  result. Every line below is a TRIGGER or a deliberate CONTROL; the runner
  reads each line number from its SC-TRIGGER-n / SC-CONTROL-n marker. }

interface

type
  TBox = class
  private
    FCount: Integer;
  public
    { Proven effect-free: reads its own field only. }
    function Peek: Boolean;
    { Writes its own field -- summary 's'. }
    function Bump: Boolean;
    { Only blocker is an UNBOUND callee -- summary '?', a gap, not an effect. }
    function Guess: Boolean;
  end;

function Pop(var AList: Integer): Boolean;
function NextId: Boolean;
function Mask: Integer;
procedure Driver;

var
  GNext: Integer;

implementation

function TBox.Peek: Boolean;
begin
  Result:= FCount > 0;
end;

function TBox.Bump: Boolean;
begin
  FCount:= FCount + 1;
  Result:= FCount > 1;
end;

function TBox.Guess: Boolean;
begin
  Result:= Trim('x') <> '';
end;

{ Writes through its var parameter -- summary 'p0'. }
function Pop(var AList: Integer): Boolean;
begin
  AList:= AList - 1;
  Result:= AList > 0;
end;

{ Writes a global -- summary 'g'. }
function NextId: Boolean;
begin
  GNext:= GNext + 1;
  Result:= GNext > 1;
end;

{ Writes a global and returns an INTEGER -- `N and Mask` is bitwise. }
function Mask: Integer;
begin
  GNext:= GNext + 1;
  Result:= GNext;
end;

procedure Driver;
var
  N : Integer;
  B : TBox;
  Ok: Boolean;
begin
  N := 3;
  Ok:= N > 0;
  B := TBox.Create;
  if (N > 0) and Pop(N) then N:= 1;           { SC-TRIGGER-1: p0 after and }
  if Ok or B.Bump then N:= 2;                  { SC-TRIGGER-2: s after or }
  Ok:= Ok and NextId();                        { SC-TRIGGER-3: g, assignment }
  while (N > 0) and
    NextId do Dec(N);                          { SC-TRIGGER-4: g, parenless, wrapped }
  if Ok and not B.Bump then N:= 4;             { SC-TRIGGER-5: s under not }
  if Ok and (Mask > 0) then N:= 5;             { SC-TRIGGER-6: integer callee under a comparison }
  if Pop(N) and Ok then N:= 6;                 { SC-CONTROL-1: left operand, always evaluated }
  if Ok and B.Peek then N:= 7;                 { SC-CONTROL-2: proven effect-free }
  if Ok and B.Guess then N:= 8;                { SC-CONTROL-3: summary '?' only }
  if Ok and SameText('a', 'b') then N:= 9;     { SC-CONTROL-4: unbound callee }
  N:= N and Mask;                              { SC-CONTROL-5: bitwise integer and }
  N:= Mask; if Ok then N:= 10;                 { SC-CONTROL-6: effect outside any and/or }
  if Ok xor NextId then N:= 11;                { SC-CONTROL-7: xor evaluates both }
  if Ok and Ok then Pop(N);                    { SC-CONTROL-8: effect in the then-branch }
  B.Free;
end;

end.
