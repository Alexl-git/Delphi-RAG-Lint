unit pubfield;
interface
implementation

uses
  Vcl.Controls;

type
  TWidget = class
  private
    FHidden: Integer;
  public
    FFoo: Integer;
  published
    FBar: TControl;
  end;

  TImplicitPublic = class
    FImplicit: Integer;
  end;

  TCoord = record
  public
    RX: Integer;
  end;

end.
