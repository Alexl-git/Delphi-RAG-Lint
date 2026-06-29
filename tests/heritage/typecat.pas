unit typecat;

// Fixture for ResolveTypeCategory (Phase 3). Exercises intrinsic categories
// (by name), declared class/interface/enum symbols, and type-alias chasing.

interface

type
  TMyFloat = Double;     // alias -> intrinsic float
  TMyAlias = TMyFloat;   // alias -> alias -> float (fixpoint chase)

  TColor = (clRed, clGreen, clBlue);

  IFoo = interface
    ['{CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC}']
  end;

  TFoo = class
  end;

implementation

end.
