unit sample;

interface

type
  TWidget = class
  private
    FValue: Integer;
  end;

  TAlpha = class
  private
    FW: TWidget;
  end;

  TBeta = class
  private
    FW: TWidget;
  end;

  TGamma = class
  private
    FW: TWidget;
  end;

  TApp = class
  private
    FA: TAlpha;
    FB: TBeta;
    FC: TGamma;
  end;

  TLoner = class
  private
    FN: Integer;
  end;

implementation

end.
