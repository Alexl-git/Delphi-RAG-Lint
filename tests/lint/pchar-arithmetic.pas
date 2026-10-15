unit PCharArith;

interface

implementation

procedure Bad;
var
  PStr: PChar;
  N: Integer;
begin
  PStr := PStr + N;
  PStr := PStr + 1;
end;

procedure Good;
var
  S: string;
  N: Integer;
begin
  N := N + 1;
  S := S + 'x';
end;

var
  GBuf: PByte;

{ The rule decides on the DECLARED type, so a pointer whose name has no P
  prefix still fires: a parameter, an inline var, a ^Char, a unit global seen
  from a nested routine. }
procedure BadByType(const Src: PAnsiChar; var Cur: PWideChar);
var
  Hat: ^Char;
  procedure Inner;
  begin
    GBuf := GBuf + 1;
  end;
begin
  Cur := Cur - 1;
  Hat := Hat + 2;
  var Walk: PChar := nil;
  Walk := Walk + 1;
  Inner;
  if Src + 1 = nil then Exit;
end;

end.