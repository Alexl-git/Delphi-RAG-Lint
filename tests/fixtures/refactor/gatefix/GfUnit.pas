unit GfUnit;

interface

type
  Walker = interface
    ['{6F1B7B52-3C1E-4D55-9B7A-0A5C2D9E1F01}']
    procedure Walk;
  end;

  TPlain = class
  end;

procedure RunAll;

implementation

procedure Take(const AObj: TObject);
begin
  if AObj = nil then Exit;
end;

procedure UseGood;
begin
  var P: TPlain:= TPlain.Create;
  try
    Take(P as TObject);
  finally
    P.Free;
  end;
end;

procedure UseBad(const AWalk: Walker);
begin
  Take(AWalk as TObject);
end;

procedure RunAll;
begin
  UseGood;
end;

end.
