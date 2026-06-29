unit unitb;

// Base units for the Phase 2 cross-unit ancestry fixture. unita uses this unit
// and declares descendants, so ResolveAncestry must link across files.

interface

type
  TGrand = class
  end;

  TBase = class(TGrand)
  end;

  IBase = interface
    ['{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}']
  end;

implementation

end.
