unit nouses;

interface

implementation

uses
  System.Classes;

function P(S, T: string): Boolean;
begin
  Result := Pos(T, S) > 0;
end;

end.
