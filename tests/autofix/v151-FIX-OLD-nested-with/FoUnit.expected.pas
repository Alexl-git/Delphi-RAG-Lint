unit FoUnit;

interface

type
  TSize = class
  public
    Width, Height: Integer;
  end;

  TBox = class
  public
    Size: TSize;
    Depth: Integer;
  end;

procedure RunAll;

implementation

{ nested with: every bare name binds to the innermost target that declares it }
function Volume(ABox: TBox; ASize: TSize): Integer;
begin
  with ABox do
    Result:= ASize.Width * ASize.Height * Depth;
end;

procedure RunAll;
var
  B: TBox;
begin
  B:= TBox.Create;
  try
    B.Size:= TSize.Create;
    try
      B.Size.Width:= 2;
      B.Size.Height:= 3;
      B.Depth:= 4;
      WriteLn(Volume(B, B.Size));
    finally
      B.Size.Free;
    end;
  finally
    B.Free;
  end;
end;

end.