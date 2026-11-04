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
function Take(var AList: Integer): Integer;
function TryNext: Boolean;
function Cached: Boolean;
function StoredCount: Boolean;
function Grow(ACount: Integer): Integer;
function GrowIf(ACount: Integer): Integer;
procedure Driver;

var
  GNext: Integer;
  GLoaded: Boolean;
  GMemo: Boolean;
  GMax: Integer;

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

{ Writes through its var parameter and returns an INTEGER -- not the fetch shape. }
function Take(var AList: Integer): Integer;
begin
  AList:= AList - 1;
  Result:= AList;
end;

{ The TryX idiom by NAME: its effect is a global write, and it is still a try. }
function TryNext: Boolean;
begin
  GNext:= GNext + 1;
  Result:= GNext > 1;
end;

{ A memo: the only write fills a cache the condition itself tests. }
function Cached: Boolean;
begin
  if not GLoaded then
  begin
    GLoaded:= True;
    GMemo:= GNext > 0;
  end;
  Result:= GMemo;
end;

{ A read-only query: the stored 'g' stands for READS SQL, nothing changes. }
function StoredCount: Boolean;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  Q.SQL.Text:= 'SELECT COUNT(*) FROM T';
  Q.Open;
  Result:= Q.Fields[0].AsInteger > 0;
end;

{ Tests what it assigns, like a memo, but moves GNext unconditionally: no memo. }
function Grow(ACount: Integer): Integer;
begin
  if GNext + ACount > GMax then GMax:= GNext + ACount;
  GNext:= GNext + ACount;
  Result:= GNext;
end;

{ Every write under a test of what it assigns, like a stream's Write: it takes a
  parameter, so it does a job per call and is no memo. }
function GrowIf(ACount: Integer): Integer;
begin
  if GMax >= 0 then
  begin
    GMax:= GMax + ACount;
  end;
  Result:= GMax;
end;

procedure Driver;
var
  N : Integer;
  B : TBox;
  B2: TBox;
  Ok: Boolean;
begin
  N := 3;
  Ok:= N > 0;
  B := TBox.Create;
  if (N > 0) and (Take(N) > 0) then N:= 1;     { SC-TRIGGER-1: p0, integer callee }
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
  if (N > 0) and Pop(N) then N:= 12;           { SC-CONTROL-9: Boolean fetch through a param only }
  if Ok and TryNext then N:= 13;               { SC-CONTROL-10: TryX idiom, by name }
  if Ok and Cached then N:= 14;                { SC-CONTROL-11: memoizing callee }
  if Ok and StoredCount then N:= 15;           { SC-CONTROL-12: read-only SQL }
  if Assigned(B) and B.Bump then N:= 16;       { SC-CONTROL-13: nil guard of the receiver }
  if (B <> nil) and B.Bump then N:= 17;        { SC-CONTROL-14: nil guard of the receiver }
  Ok:= Ok and Pop(N);                          { SC-TRIGGER-7: accumulator, the fetch shape still loses the call }
  Ok:= Ok or TryNext;                          { SC-TRIGGER-8: accumulator, the TryX idiom still loses the call }
  Ok:= (Ok or NextId) or Cached;               { SC-TRIGGER-9: accumulator over a chain, memo or not }
  if Assigned(B2) and B.Bump then N:= 18;      { SC-TRIGGER-10: the guard tests another object }
  if (N > 0) and (Grow(N) > 0) then N:= 19;    { SC-TRIGGER-11: tests what it assigns, yet no memo }
  if (N > 0) and (GrowIf(N) > 0) then N:= 20;  { SC-TRIGGER-12: guarded writes, but it takes a parameter }
  B.Free;
end;

end.
