unit uY7Shapes;

interface

type
  TShape = class
    FName: string;
  end;

  TSquare = class(TShape)
    FSide: Integer;
  end;

  TCircle = class(TShape)
    FRadius: Integer;
  end;

  TOther = class
    FX: Integer;
  end;

  { the ancestor is declared nowhere: the chain stays unresolved }
  TOrphan = class(TMissingBase)
    FY: Integer;
  end;

implementation

end.
