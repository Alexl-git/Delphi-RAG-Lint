unit FixLibC;

{ uses-recover fixture: reached only through FixLibA's IMPLEMENTATION uses, so no header names it. }

interface

function LibCValue: Integer;

implementation

function LibCValue: Integer;
begin
  Result:= 3;
end;

end.
