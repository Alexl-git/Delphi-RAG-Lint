unit basic;

interface

implementation

uses
  System.SysUtils;

function P(S, T: string): Boolean;
begin
  Result := S.Contains(T);
  Result := not S.Contains(T);
  Result := S.Contains(T);
end;

end.
