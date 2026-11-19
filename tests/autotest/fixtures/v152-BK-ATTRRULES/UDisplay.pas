unit UDisplay;

{ debug-display-placeholder fixture (1.52 BK-ATTRRULES, B48). A line ending in (+) must
  carry the finding, (-) must not. Every (-) is one silence rule; every (+) its control. }

interface

type
  DebuggerDisplayAttribute = class(TCustomAttribute)
  public
    constructor Create(const ATemplate: string);
  end;

  TBase = class
  public
    BaseName: string;
  end;

  [DebuggerDisplay('Name={Name} Count={Count,nq} Len={Name.Length}')] { (-) }
  TGood = class
  public
    Name: string;
    function Count: Integer;
  end;

  [DebuggerDisplay('Nmae={Nmae}')] { (+) }
  TTypo = class
  public
    Name: string;
  end;

  [DebuggerDisplay('{BaseName} {ClassName} {Self} {{literal}} { }')] { (-) }
  TChild = class(TBase)
  end;

  [DebuggerDisplay('{Missing}')] { (+) }
  TChildBad = class(TBase)
  end;

  [DebuggerDisplay('{Anything}')] { (-) }
  TUnknownAncestor = class(TNotDeclaredAnywhere)
  end;

  [DebuggerDisplay('X={X} Z={Z}')] { (+) }
  TPoint = record
    X, Y: Integer;
  end;

  [DebuggerDisplay('{Nothing}' + 'more')] { (-) }
  TConcat = class
  end;

  [System.DebuggerDisplayAttribute('{Gone}')] { (+) }
  TQualified = class
  end;

  [OtherAttribute('{Gone}')] { (-) }
  TOtherAttr = class
  end;

implementation

constructor DebuggerDisplayAttribute.Create(const ATemplate: string);
begin
end;

function TGood.Count: Integer;
begin
  Result:= 0;
end;

end.