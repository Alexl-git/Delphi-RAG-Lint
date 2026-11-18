unit PtwBase;

// Fixture of tests\autotest\run_v152_PTW.ps1 (lane v152 PTW): the two upper classes of the chain.
// TLeaf lives in PtwLeaf, so a parameter narrowed from TLeaf to TMid must add PtwBase to its unit's uses.

interface

type
  TRoot = class
  public
    procedure RootOp;
  end;

  TMid = class(TRoot)
  public
    procedure MidOp;
  end;

implementation

procedure TRoot.RootOp;
begin
end;

procedure TMid.MidOp;
begin
end;

end.
