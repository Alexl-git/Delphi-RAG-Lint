unit FoUnit;

interface

procedure RunAll;

implementation

uses
  System.Variants;

{ Width is written and never read; the named argument's label Width := 3 is a
  dispatch parameter name, not a use of the local. }
procedure Resize(const AObj: OleVariant);
var
  Width: Integer;
begin
  Width:= 5;
  AObj.Resize(Width := 3);
end;

procedure RunAll;
begin
  if VarIsNull(Null) then Exit;
  Resize(Unassigned);
end;

end.
