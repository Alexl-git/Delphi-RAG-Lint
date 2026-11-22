unit nouses;

interface

implementation

uses
  System.Classes;

function P(S, T: string): Boolean;
begin
  Result := Pos('ab', S) > 0;
end;

end.
