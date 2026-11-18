unit PtwLeaf;

// Fixture of tests\autotest\run_v152_PTW.ps1: the declared (wide) parameter type.

interface

uses
  PtwBase;

type
  TLeaf = class(TMid)
  public
    procedure LeafOp;
  end;

implementation

procedure TLeaf.LeafOp;
begin
end;

end.
