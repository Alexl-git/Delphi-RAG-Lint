unit chararray;

interface

implementation

{ A bare Char-array local cannot be an if-expression operand beside a string:
  `Result:= if C then Buf else 'x'` is E2010 (array[0..255] of Char vs string).
  The fixer must decline; the rule still fires. Found by the ORM3 --fix --apply build
  proof (uPipesBase.GetClientWindowsUsername). }
function Pick(C: Boolean): string;
var
  Buf: array [0 .. 255] of Char;
begin
  Buf[0]:= #0;
  if C then Result:= Buf
  else Result:= 'Unknown';
end;

end.
