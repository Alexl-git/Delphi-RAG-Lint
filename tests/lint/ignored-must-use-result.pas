unit IgnoredMustUseResult;

interface

implementation

uses
  Winapi.Windows, System.SysUtils;

procedure Bad(const F: string; H: THandle);
var
  N: Integer;
begin
  DeleteFile(F);
  RenameFile(F, F + '.bak');
  ForceDirectories(F);
  ReleaseMutex(H);
  TryStrToInt(F, N);
  SetCurrentDir(F);
end;

procedure Good(const F: string; H: THandle);
var
  N: Integer;
begin
  if not DeleteFile(F) then
    Exit;
  if TryStrToInt(F, N) then
    Exit;
  Win32Check(CloseHandle(H));
  FileExists(F);
  Sleep(1);
end;

end.
