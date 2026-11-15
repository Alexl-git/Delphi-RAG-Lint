unit createprocess_readonly_commandline_clean;

interface

implementation

uses Winapi.Windows, System.SysUtils;

procedure Clean(var ACmd: string; const AFile: string);
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd, Cmd2: string;
begin
  Cmd := 'calc.exe';
  UniqueString(Cmd);
  CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil, nil, SI, PI);
  Cmd2 := Format('notepad.exe %s', [AFile]);
  CreateProcess(nil, PChar(Cmd2), nil, nil, False, 0, nil, nil, SI, PI);
  CreateProcess(nil, PChar(ACmd), nil, nil, False, 0, nil, nil, SI, PI);
  CreateProcess(PChar('app.exe'), nil, nil, nil, False, 0, nil, nil, SI, PI);
  CreateProcessA(nil, 'calc.exe', nil, nil, False, 0, nil, nil, SI, PI);
end;

end.
