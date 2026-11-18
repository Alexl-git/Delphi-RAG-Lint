unit PtwLib;

// Fixture of tests\autotest\run_v152_PTW.ps1: a unit OUTSIDE the project's own roots (reached through the search
// path), standing in for library code. Scoped run: silent. Unscoped (ad-hoc --db) run: it fires -- the positive
// control that the silence comes from the scoping, not from the body.

interface

uses
  PtwLeaf;

procedure LibMid(pP: TLeaf); // SILENT outside-roots

implementation

procedure LibMid(pP: TLeaf);
begin
  pP.MidOp;
end;

end.
