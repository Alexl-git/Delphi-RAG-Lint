unit FoUnit;

interface

type
  TBox = class
  public
    Width, Height: Integer;
  end;

procedure RunAll;

implementation

{ every bare name of the body that TBox declares gets the ABox. prefix }
function Area(ABox: TBox): Integer;
begin
  Result:= ABox.Width * ABox.Height;
end;

procedure RunAll;
var
  B: TBox;
begin
  B:= TBox.Create;
  try
    B.Width:= 2;
    B.Height:= 3;
    WriteLn(Area(B));
  finally
    B.Free;
  end;
end;

end.
