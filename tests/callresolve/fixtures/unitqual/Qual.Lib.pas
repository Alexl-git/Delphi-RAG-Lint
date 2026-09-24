unit Qual.Lib;

{ Fixture for run_unit_qualified_call_bind.ps1 (ENG-16): free routines a
  UNIT-QUALIFIED call in uQualUse must bind to. The unit name is dotted on
  purpose -- `Qual.Lib.DoIt(1)` is the `Pipes.Commands.DispatchCommand` shape. }

interface

procedure DoIt(A: Integer);
function Twice(A: Integer): Integer;
function Ready: Boolean;
procedure Over(A: Integer); overload;
procedure Over(A, B: Integer); overload;

var
  GFlag: Boolean;

{ D22 (run_unit_qualified_value_bind.ps1, resolver 1.9.0-alpha): a unit-level
  var and const that a UNIT-QUALIFIED read / write in uQualUse must bind to. }
var
  GLimit: Integer;
  GSole: Integer;       { declared by THIS used unit only -- check 3 }

const
  CMax = 3;

implementation

procedure DoIt(A: Integer);
begin
  GFlag:= A > 0;
end;

function Twice(A: Integer): Integer;
begin
  Result:= A * 2;
end;

function Ready: Boolean;
begin
  Result:= GFlag;
end;

procedure Over(A: Integer);
begin
  GFlag:= A > 0;
end;

procedure Over(A, B: Integer);
begin
  GFlag:= A > B;
end;

end.
