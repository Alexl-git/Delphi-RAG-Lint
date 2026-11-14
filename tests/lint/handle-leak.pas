unit handle_leak;

interface

implementation

uses Winapi.Windows, System.SysUtils;

procedure Hits(const AName: string);
var
  H: THandle;
  L: HMODULE;
  DC: HDC;
  SR: TSearchRec;
  K: HKEY;
  Buf: array[0..9] of Byte;
  N: DWORD;
begin
  H := CreateFile(PChar(AName), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  ReadFile(H, Buf, 10, N, nil);
  L := LoadLibrary('x.dll');
  DC := GetDC(0);
  if FindFirst(AName, faAnyFile, SR) = 0 then
    Writeln(SR.Name);
  RegOpenKeyEx(HKEY_CURRENT_USER, 'Software', 0, KEY_READ, K);
end;

end.
