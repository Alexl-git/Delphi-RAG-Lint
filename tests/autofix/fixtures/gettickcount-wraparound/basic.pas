unit basic;

interface

implementation

uses
  Winapi.Windows;

procedure Run;
var
  T: Int64;
  U: UInt64;
begin
  T:= GetTickCount;
  U:= GetTickCount();
  if T = U then Exit;
end;

end.
