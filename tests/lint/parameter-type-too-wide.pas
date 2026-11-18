unit ParameterTypeTooWide;

// parameter-type-too-wide is a PROJECT rule: it needs an index (the narrow-param proof walks the class chain in
// the store). `lint <file>` with no --db therefore reports nothing here, even though Wide's body uses only
// TMid members. The firing cases, the skip-class twins and the autofix are in run_v152_PTW.ps1 over
// tests\lint\parameter-type-too-wide.project.

interface

type
  TMid = class
  public
    procedure MidOp;
  end;

  TLeaf = class(TMid)
  end;

procedure Wide(pP: TLeaf);

implementation

procedure TMid.MidOp;
begin
end;

procedure Wide(pP: TLeaf);
begin
  pP.MidOp;
end;

end.