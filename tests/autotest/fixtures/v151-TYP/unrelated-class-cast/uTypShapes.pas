unit uTypShapes;

{ Class tree in its own unit: the cast rule must learn it from the index. }

interface

type
  TShape = class
  public
    FName: string;
  end;

  TCircle = class(TShape)
  public
    FRadius: Double;
  end;

  TSquare = class(TShape)
  public
    FSide: Double;
  end;

  TOther = class
  public
    FValue: Integer;
  end;

implementation

end.
