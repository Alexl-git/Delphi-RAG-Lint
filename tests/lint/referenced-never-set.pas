unit rns;
interface
type
  TThing = class
  strict private
    FNeverSet: Integer;
    FOk: Integer;
    procedure Init;
    function DoIt: Integer;
  end;
implementation
procedure TThing.Init;
begin
  FOk:= 5;
end;
function TThing.DoIt: Integer;
begin
  Result:= FNeverSet + FOk;
end;
end.