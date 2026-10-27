unit basic;

interface

implementation

uses
  System.SysUtils;

procedure Run(const S: string);
var
  L: string;
begin
  L:= Format('%s', [S]);
  L:= Format('%s', ['abc']) + L;
end;

end.
