unit char_to_pchar;

interface

implementation

uses Winapi.Windows;

procedure Hits(const AC: Char; W: WideChar);
var
  C: Char;
  A: AnsiChar;
begin
  C := 'x';
  A := 'y';
  OutputDebugString(PChar(C));
  OutputDebugStringW(PWideChar(W));
  OutputDebugStringA(PAnsiChar(A));
  MessageBox(0, PChar(AC), nil, 0);
end;

end.
