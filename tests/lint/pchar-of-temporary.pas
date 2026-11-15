unit pchar_of_temporary;

interface

uses Winapi.Windows, Winapi.Messages, System.SysUtils;

type
  TSender = class
  private
    FText: PChar;
  public
    procedure Hits(const S: string; N: Integer; H: HWND);
  end;

implementation

procedure TSender.Hits(const S: string; N: Integer; H: HWND);
var
  Ziel: PChar;
  W: PWideChar;
begin
  Ziel := PChar(S + '.bak');
  Ziel := PChar(IntToStr(N));
  FText := PChar('Name: ' + S);
  W := PWideChar(ExtractFilePath(S));
  PostMessage(H, WM_USER, 0, LPARAM(PChar(S + '!')));
  CopyFile(PChar(S), Ziel, False);
end;

end.
