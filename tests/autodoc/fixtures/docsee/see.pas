unit see;

// Fixture for run_doc_seealso.ps1 -- the <seealso> doc-source.
// TSvc.DoA calls DoB(..) and DoC(..) (PARENTHESIZED call sites so the body-scan
// registers the Calls fact). DoB/DoC are both siblings (same parent TSvc) AND
// resolved callees of DoA, so DoA's <seealso> cref set = {see.TSvc.DoB,
// see.TSvc.DoC}. The list is deduped, sorted and capped at SEEALSO_CAP=5.

interface

type
  TSvc = class
  public
    procedure DoA;
    procedure DoB(AValue: Integer);
    procedure DoC(AText: string);
  end;

implementation

procedure TSvc.DoA;
begin
  DoB(1);
  DoC('x');
end;

procedure TSvc.DoB(AValue: Integer);
begin
  Writeln(AValue);
end;

procedure TSvc.DoC(AText: string);
begin
  Writeln(AText);
end;

end.
