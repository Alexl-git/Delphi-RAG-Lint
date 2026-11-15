unit unsafe_string_api_ansi_call_clean;

interface

implementation

uses Winapi.Windows;

procedure Clean(const S: string; const A: AnsiString);
begin
  MessageBoxW(0, PChar(S), nil, 0);
  MessageBoxA(0, 'literal', nil, 0);
  MessageBoxA(0, PAnsiChar(A), nil, 0);
  DoItA(PAnsiChar(AnsiString(Undeclared)));
end;

end.
