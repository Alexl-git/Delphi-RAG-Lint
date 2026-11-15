unit pchar_of_temporary_clean;

interface

implementation

uses Winapi.Windows, Winapi.Messages, System.SysUtils;

procedure Clean(const S: string; P: PChar; H: HWND);
var
  Ziel: PChar;
  Tmp: string;
begin
  CopyFile(PChar(S + '.bak'), PChar(IntToStr(1)), False);
  Ziel := PChar(S);
  Tmp := S + '.bak';
  Ziel := PChar(Tmp);
  Ziel := PChar(P + 1);
  SendMessage(H, WM_SETTEXT, 0, LPARAM(PChar(S + '!')));
  OutputDebugString(Ziel);
end;

end.
