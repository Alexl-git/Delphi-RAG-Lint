unit SyntaxErrorIfEnd;

interface

implementation

procedure UsesIfEnd;
begin
  {$IF Defined(MSWINDOWS)}
  Writeln('win');
  {$IFEND}
end;

procedure RealTypo;
begin
  if x > 0 then
    ;;;garbage syntax here@@@
end;

end.
