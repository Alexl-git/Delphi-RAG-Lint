unit FoUnit;

interface

procedure RunAll;

implementation

const
  CUsed = 3;

var
  GUsedB: Integer;
  GUnusedName: string;

procedure RunAll;
begin
  GUsedB:= CUsed;
  WriteLn(GUsedB);
end;

end.
