unit rnsg;
interface
type
  TGuarded = class
  strict private
    FVarArg: Integer;
    FUnused: Integer;
    procedure Init(var AOut: Integer);
    procedure UseAll;
  protected
    FProtected: Integer;
  end;
implementation
procedure TGuarded.Init(var AOut: Integer);
begin
  AOut:= 42;
  Init(FVarArg);
end;
procedure TGuarded.UseAll;
begin
  FProtected:= FProtected + 1;
end;
end.