unit Heritage;

// Fixture for the M1 heritage-capture test (Phase 1). Each declared
// class/interface carries an ancestor list the parser must capture into
// symbols.heritage as collapsed source text.

interface

type
  IBar = interface
    ['{11111111-1111-1111-1111-111111111111}']
  end;

  IBaz = interface
    ['{22222222-2222-2222-2222-222222222222}']
  end;

  TBar = class
  end;

  // Class with a base class AND an implemented interface.
  TFoo = class(TBar, IBaz)
  end;

  // Interface with a parent interface.
  IFoo = interface(IBar)
    ['{33333333-3333-3333-3333-333333333333}']
  end;

  // No ancestors: heritage must be empty (NULL), not a stray value.
  TLone = class
  end;

  // Qualified ancestor: stored verbatim (dotted-tail normalization is Phase 2).
  TQual = class(System.Classes.TComponent)
  end;

  // Generic ancestor: stored verbatim (strip-<> normalization is Phase 2).
  TGen = class(TBar, IList<IBaz>)
  end;

implementation

end.
