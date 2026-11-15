unit FoUnit;

interface

type
  TBase = class
  end;

  TLeaf = class(TBase)
  end;

procedure RunAll;

implementation

{ ALeaf is declared TLeaf, already a TBase: the test only asks for nil }
function HasLeaf(ALeaf: TLeaf): Boolean;
begin
  Result:= Assigned(ALeaf);
end;

procedure RunAll;
var
  L: TLeaf;
begin
  L:= TLeaf.Create;
  try
    WriteLn(HasLeaf(L), HasLeaf(nil));
  finally
    L.Free;
  end;
end;

end.
