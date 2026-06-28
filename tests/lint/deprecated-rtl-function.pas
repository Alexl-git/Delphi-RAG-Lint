unit DeprecatedRtl;

interface

implementation

procedure Bad;
var
  S: string;
  P: PAnsiChar;
begin
  OemToAnsi(P, P);
  AnsiToOem(P, P);
  S := StrPas(P);
end;

procedure Good;
var
  S: string;
  I: Integer;
begin
  I := StrToInt(S);
  S := IntToStr(I);
end;

end.
