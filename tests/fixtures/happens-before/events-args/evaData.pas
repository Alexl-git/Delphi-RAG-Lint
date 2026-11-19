unit evaData;

interface

var
  GFill: Integer;
  GOut: TObject;
  GConst: Integer;
  GFillTwice: Integer;
  GInc: Integer;
  GDpr: Integer;

procedure Fill(var pX: Integer);
procedure Run;

implementation

procedure Fill(var pX: Integer);
begin
  pX := 1;
end;

procedure Get(out pO: TObject);
begin
  pO := nil;
end;

procedure Show(const pX: Integer);
begin
  if pX > 0 then
    Exit;
end;

procedure ShowV(pX: Integer);
begin
  if pX > 0 then
    Exit;
end;

procedure Run;
begin
  Fill(GFill);
  Get(GOut);
  Show(GConst);
  ShowV(GConst);
  Fill(GFillTwice);
  Fill(GFillTwice);
  Inc(GInc);
end;

end.
