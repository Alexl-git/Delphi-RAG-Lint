unit hides_ancestor_virtual;

{ Fixture for hides-ancestor-virtual (warning).
  Hit: a method declared without override / reintroduce / overload whose name
  equals a virtual / dynamic (or override) method of a same-file ancestor.
  Silent: override, reintroduce, overload, a message handler, a method whose
  ancestor virtual does not exist (static ancestor method), a class whose
  ancestor is not resolvable. }

interface

type
  TBase = class
  public
    procedure Run; virtual;
    procedure Paint; dynamic;
    procedure Plain;
    procedure Quiet; virtual; abstract;
  end;

  TMid = class(TBase)
  public
    procedure Run; override;
    procedure Tick; virtual;
  end;

  TLeaf = class(TMid)
  public
    procedure Run;
    procedure Paint;
    procedure Tick; override;
    procedure Plain;
    procedure Quiet;
    procedure WmFoo(var Msg: Integer); message 1;
  end;

  TLeafOk = class(TMid)
  public
    procedure Run; override;
    procedure Paint; reintroduce;
    procedure Tick; overload;
    procedure Tick(A: Integer); overload;
  end;

  TStranger = class(TUnknownAncestor)
  public
    procedure Run;
  end;

implementation

end.
