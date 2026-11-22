unit basic;

interface

implementation

uses
  System.SysUtils;

function P(S, T: string): Boolean;
begin
  Result := S.Contains('ab');
  Result := not S.Contains('ab');
  Result := S.Contains('ab');
end;

end.
