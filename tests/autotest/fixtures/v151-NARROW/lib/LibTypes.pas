unit LibTypes;

interface

type
  TNpBase = class
  public
    procedure Foo;
  end;

  TNpLeaf = class(TNpBase)
  public
    procedure Extra;
  end;

implementation

procedure TNpBase.Foo;
begin
end;

procedure TNpLeaf.Extra;
begin
end;

end.
