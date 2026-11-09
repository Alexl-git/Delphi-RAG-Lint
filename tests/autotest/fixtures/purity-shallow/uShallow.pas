unit uShallow;
{ Fixture for tests\autotest\run_purity_shallow_library.ps1 (146 g1, wave 148
  lane PB). Indexed twice: DEEP (usage refs) and SHALLOW (--shallow, the
  library mode: call refs only). The expected verdict per mode is in the
  comment beside each declaration. }
interface
type
  TGate = class
  private
    FActive: Boolean;
  public
    procedure Open;                 { deep: s (writes FActive); shallow: ? (no usage facts) }
    function IsOpen: Boolean;       { deep: proven; shallow: ? }
  end;
var
  GFlag: Boolean;
procedure SetFlag;                  { deep: g; shallow: ? }
function Twice(A: Integer): Integer; { deep: proven; shallow: ? }
implementation

procedure TGate.Open;
begin
  FActive:= True;
end;

function TGate.IsOpen: Boolean;
begin
  Result:= FActive;
end;

procedure SetFlag;
begin
  GFlag:= True;
end;

function Twice(A: Integer): Integer;
begin
  Result:= A + A;
end;

end.
