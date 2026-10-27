unit uCmd;

interface

procedure RunCmdFromArg;
procedure RunCmdConst;

implementation

uses
  Windows;

procedure RunCmd(const ACmd: string);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
begin
  CreateProcess(nil, PChar('cmd.exe /c ' + ACmd), nil, nil, False, 0, nil, nil, SI, PI);
end;

procedure RunCmdFromArg;
begin
  RunCmd(ParamStr(1));
end;

procedure RunCmdConst;
begin
  RunCmd('dir');
end;

end.
