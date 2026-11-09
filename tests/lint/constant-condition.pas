unit ConstantCondition;

interface

implementation

procedure Bad;
begin
  if True then
    Writeln('dead');
  if False then
    Writeln('also dead');
  while False do
    Writeln('never runs');
end;

procedure Good;
var
  B: Boolean;
begin
  if B then
    Writeln('ok');
  while True do  // intentional -- event loop, NOT flagged
    break;
end;

procedure WithElse(B: Boolean);
begin
  if True then Writeln('a') else Writeln('b');
  if False then
    Writeln('c')
  else
    Writeln('d');
  if B then Writeln('e') else Writeln('f');
end;

end.
