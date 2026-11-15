unit unsafe_string_api_ansi_call;

interface

implementation

uses Winapi.Windows;

procedure Hits(const S, AName: string);
begin
  MessageBoxA(0, PAnsiChar(AnsiString(S)), nil, 0);
  LoadLibraryA(PAnsiChar(AnsiString(AName)));
end;

end.
