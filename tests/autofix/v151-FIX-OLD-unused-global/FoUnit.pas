unit FoUnit;

interface

procedure RunAll;

implementation

const
  CUnusedLimit = 10;
  CUsed = 3;

var
  GUnusedA, GUsedB: Integer;
  GUnusedFlag: Boolean;
  GUnusedName: string;

procedure RunAll;
begin
  GUsedB:= CUsed;
  WriteLn(GUsedB);
end;

end.
