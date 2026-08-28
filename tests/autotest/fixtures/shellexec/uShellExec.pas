unit uShellExec;

{ Fixture for run_shellexec_precision.ps1.

  Every routine is named for what the rule MUST do with it. The suppressed and
  the flagged cases sit in one file on purpose: a rule change that silences the
  false positives by silencing everything would turn the SAFE_ cases green and
  the UNSAFE_ cases green too, and only the pair tells them apart. }

interface

uses
  Winapi.Windows, Winapi.ShellAPI;

type
  TShellExecProbe = class
  public
    procedure SafeOpenFolder(const pFolder: string);
    procedure SafeOpenFolderExplore(const pFolder: string);
    procedure SafeOpenWithLiteralParams(const pFile: string);
    procedure UnsafeRuntimeParameters(const pFile, pArgs: string);
    procedure UnsafeRunAsVerb(const pFile: string);
    procedure UnsafeInterpreter(const pArgs: string);
    procedure UnsafeVariableVerb(const pVerb, pFile: string);
    procedure UnsafeWinExecConcat(const pArg: string);
  end;

implementation

{ SUPPRESSED. lpParameters is nil and the verb is the literal 'open', so no
  command line exists for anything to be injected into. This is the exact shape
  reported from DataCopy on 2026-08-27. }
procedure TShellExecProbe.SafeOpenFolder(const pFolder: string);
begin
  ShellExecute(0, 'open', PChar(pFolder), nil, nil, SW_SHOWNORMAL);
end;

{ SUPPRESSED. 'explore' is as plain as 'open'. }
procedure TShellExecProbe.SafeOpenFolderExplore(const pFolder: string);
begin
  ShellExecute(0, 'explore', PChar(pFolder), nil, nil, SW_SHOWNORMAL);
end;

{ SUPPRESSED. A LITERAL lpParameters is fixed text -- the caller cannot inject
  through it either. }
procedure TShellExecProbe.SafeOpenWithLiteralParams(const pFile: string);
begin
  ShellExecute(0, 'open', PChar(pFile), '/select', nil, SW_SHOWNORMAL);
end;

{ FLAGGED. lpParameters is runtime-built: this IS a command line. }
procedure TShellExecProbe.UnsafeRuntimeParameters(const pFile, pArgs: string);
begin
  ShellExecute(0, 'open', PChar(pFile), PChar(pArgs), nil, SW_SHOWNORMAL);
end;

{ FLAGGED. 'runas' elevates; a runtime path under elevation is exactly the case
  the rule exists for. }
procedure TShellExecProbe.UnsafeRunAsVerb(const pFile: string);
begin
  ShellExecute(0, 'runas', PChar(pFile), nil, nil, SW_SHOWNORMAL);
end;

{ FLAGGED. lpParameters is runtime-built AND lpFile is a command processor --
  the classic payload. }
procedure TShellExecProbe.UnsafeInterpreter(const pArgs: string);
begin
  ShellExecute(0, 'open', 'cmd.exe', PChar(pArgs), nil, SW_SHOWNORMAL);
end;

{ FLAGGED. A verb that is not a literal is unknowable -- it could be 'runas'. }
procedure TShellExecProbe.UnsafeVariableVerb(const pVerb, pFile: string);
begin
  ShellExecute(0, PChar(pVerb), PChar(pFile), nil, nil, SW_SHOWNORMAL);
end;

{ FLAGGED. WinExec takes a whole command LINE, so a concatenated argument is
  command injection by construction. The suppression is ShellExecute-only and
  must not reach this. }
procedure TShellExecProbe.UnsafeWinExecConcat(const pArg: string);
begin
  WinExec(PAnsiChar(AnsiString('notepad.exe ' + pArg)), SW_SHOWNORMAL);
end;

end.
