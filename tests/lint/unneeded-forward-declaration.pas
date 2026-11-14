unit UnneededForwardDeclaration;

interface

type
  TNode = class;

  TNode = class
  end;

  TNeeded = class;

  TUser = class
    FOther: TNeeded;
  end;

  TNeeded = class
  end;

implementation

end.
