unit uOut;

interface

procedure UseOut;

implementation

uses
  Windows;

procedure GetName(out S: string);
begin
  S := ParamStr(1);
end;

procedure UseOut;
var
  N: string;
begin
  GetName(N);
  WinExec(PAnsiChar(AnsiString(N)), 0);
end;

end.
