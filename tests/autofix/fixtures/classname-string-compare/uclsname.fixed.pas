unit uclsname;

interface

type
  TShape = class
  end;

  TBox = class(TShape)
  public
    function Kind(X: TObject): Integer;
  end;

implementation

function TBox.Kind(X: TObject): Integer;
begin
  Result:= 0;
  if X.ClassType = TBox then Result:= 1;
  if X.ClassType <> TShape then Inc(Result);
end;

end.
