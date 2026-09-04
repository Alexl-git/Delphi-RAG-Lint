unit objleaksplitlib;

// The LIBRARY half of the split-chain fixture (FP2b). Indexed into its OWN
// database and passed with --library-db, so that the project half's ancestor
// edge `TMyForm = class(TForm)` is UNRESOLVED in the project index -- exactly
// the shape a real `TMyForm = class(TForm)` has, where TForm lives in Vcl.Forms
// and no project index carries it.

interface

type
  TComponent = class
    constructor Create(AOwner: TComponent);
  end;

  TForm = class(TComponent)
  end;

implementation

constructor TComponent.Create(AOwner: TComponent);
begin
end;

end.
