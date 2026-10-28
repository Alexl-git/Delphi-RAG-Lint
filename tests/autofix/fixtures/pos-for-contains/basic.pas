unit basic;

interface

implementation

uses
  System.SysUtils;

function P(S, T: string): Boolean;
begin
  Result := Pos(T, S) > 0;
  Result := Pos(T, S) = 0;
  Result := Pos(T, S) <> 0;
end;

end.
