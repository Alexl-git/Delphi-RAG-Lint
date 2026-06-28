unit UnsafeShellExecute;

interface

implementation

uses Windows, ShellAPI;

procedure Bad(const Cmd: string);
begin
  WinExec(PAnsiChar(AnsiString(Cmd)), SW_SHOW);
  ShellExecute(0, 'open', PChar(Cmd), nil, nil, SW_SHOW);
end;

procedure Good;
begin
  WinExec('notepad.exe', SW_SHOW);
  ShellExecute(0, 'open', 'C:\Windows\notepad.exe', nil, nil, SW_SHOW);
end;

end.
