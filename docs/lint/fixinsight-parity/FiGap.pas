unit FiGap;

interface

procedure P1(pFlag: Boolean);
procedure P2(pFlag: Boolean);
procedure P3(pFlag: Boolean);
procedure P4(pFlag: Boolean);

implementation

var
  GX: Integer;

procedure P1(pFlag: Boolean);
begin
  if pFlag then
    GX := 1
  else
    GX := 1;
end;

procedure P2(pFlag: Boolean);
begin
  if pFlag then
  begin
    GX := 2;
  end
  else
  begin
    GX := 2;
  end;
end;

procedure P3(pFlag: Boolean);
begin
  if pFlag then
  else
    GX := 3;
end;

procedure P4(pFlag: Boolean);
begin
  if pFlag then
  begin
  end
  else
    GX := 4;
end;

end.