unit unita;

// Descendants whose ancestors live in unitb. Exercises cross-unit ancestry
// resolution (in-scope via the uses graph) and transitive walking.

interface

uses
  unitb;

type
  // Transitive class chain: TChild -> TBase -> TGrand (across units).
  // Also implements an interface declared in unitb.
  TChild = class(TBase, IBase)
  end;

  // Interface parent chain across units: IChild -> IBase.
  IChild = interface(IBase)
    ['{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}']
  end;

implementation

end.
