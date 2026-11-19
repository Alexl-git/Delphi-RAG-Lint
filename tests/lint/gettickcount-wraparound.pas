unit Ticks;

interface

implementation

uses System.SysUtils;

procedure P;
var
  T: Cardinal;
  S: string;
begin
  T := GetTickCount;
  T := GetTickCount64;
  if GetTickCount - T > 500 then
    T := 0;
  S := Format('tmp_%d_%d', [GetCurrentProcessId, GetTickCount]);
  S := 'seed_' + IntToStr(Int64(GetTickCount));
  Randomize;
  RandSeed := GetTickCount();
  var T1 := GetTickCount;
end;

end.