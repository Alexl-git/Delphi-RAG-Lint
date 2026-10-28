unit uShellEx;

interface

procedure Launch;

implementation

uses
  Windows, ShellAPI;

procedure Launch;
var
  Info: TShellExecuteInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.lpFile := PChar(ParamStr(1));
  ShellExecuteEx(@Info);
end;

end.
