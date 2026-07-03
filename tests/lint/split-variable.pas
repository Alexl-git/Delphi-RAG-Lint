unit SplitVariable;

interface

implementation

uses System.SysUtils;

{ FIRES: temp reused for two unrelated purposes -- lifetime 1 (def+read) then a
  fresh whole-var def starting lifetime 2 (def+read). Two disjoint live ranges. }
function TwoPurposes(a, b: Integer): Integer;
var
  temp: Integer;
begin
  temp := a * 2;
  WriteLn(temp);
  temp := b * 3;
  WriteLn(temp);
  Result := temp;
end;

{ NOT split-variable: normal accumulator -- reassigned but the running value is
  read on the rhs (the lifetimes are NOT disjoint; one continuous live range). }
function Accumulate(n: Integer): Integer;
var
  sum, i: Integer;
begin
  sum := 0;
  for i := 1 to n do
    sum := sum + i;
  Result := sum;
end;

{ NOT split-variable (this is overwrite-before-read, a different rule): the first
  store is clobbered before ANY read -- lifetime 1 has NO use. }
procedure DeadStore(a, b: Integer);
var
  x: Integer;
begin
  x := a;
  x := b;
  WriteLn(x);
end;

end.
