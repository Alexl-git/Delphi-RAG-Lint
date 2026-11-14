unit handle_leak_clean;

interface

implementation

uses Winapi.Windows, System.SysUtils, System.Classes;

type
  TOwner = class
  private
    FLib: HMODULE;
    FStream: THandleStream;
  public
    procedure Clean(const AName: string);
  end;

procedure TOwner.Clean(const AName: string);
var
  H, H2: THandle;
  L: HMODULE;
  DC: HDC;
  SR: TSearchRec;
  K: HKEY;
begin
  H := CreateFile(PChar(AName), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
  try
  finally
    CloseHandle(H);
  end;
  L := LoadLibrary('x.dll');
  FLib := L;
  DC := GetDC(0);
  ReleaseDC(0, DC);
  if FindFirst(AName, faAnyFile, SR) = 0 then
    FindClose(SR);
  RegOpenKeyEx(HKEY_CURRENT_USER, 'Software', 0, KEY_READ, K);
  RegCloseKey(K);
  H2 := CreateFile(PChar(AName), GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);
  FStream := THandleStream.Create(H2);
end;

end.
