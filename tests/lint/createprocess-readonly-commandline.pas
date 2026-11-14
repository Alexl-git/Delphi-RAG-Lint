unit createprocess_readonly_commandline;

interface

implementation

uses Winapi.Windows;

const
  CMD_LINE = 'cmd.exe /c dir';

procedure Hits(const AFile, ACmd: string; AToken: THandle);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
begin
  CreateProcess(nil, PChar('notepad.exe ' + AFile), nil, nil, False, 0, nil, nil, SI, PI);
  CreateProcess(nil, 'calc.exe', nil, nil, False, 0, nil, nil, SI, PI);
  CreateProcess(nil, PChar(CMD_LINE), nil, nil, False, 0, nil, nil, SI, PI);
  CreateProcess(nil, PChar(ACmd), nil, nil, False, 0, nil, nil, SI, PI);
  Cmd := 'mspaint.exe';
  CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil, nil, SI, PI);
  CreateProcessAsUser(AToken, nil, PChar('x.exe'), nil, nil, False, 0, nil, nil, SI, PI);
end;

end.
