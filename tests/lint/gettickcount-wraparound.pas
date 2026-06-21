unit Ticks;

interface

implementation

procedure P;
var
  T: Cardinal;
begin
  T := GetTickCount;
  T := GetTickCount64;
end;

end.
