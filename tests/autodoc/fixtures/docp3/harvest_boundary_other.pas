unit harvest_boundary_other;

{ Companion fixture for run_doc_p3_harvest_boundary.ps1. Its only job is to
  DECLARE the two names harvest_boundary.pas's comments mention, so that
  "foreign" (declared in another file) is a fact the index can answer rather
  than an assumption the runner makes.

  Nothing here is compiled or documented. }

interface

// COMPOUND-CASED, so ruling D-5's "looks like a symbol reference" test accepts
// it. harvest_boundary.ForeignNote's comment opens on this name.
function SourceStampString: Integer;

// SINGLE-CASED, deliberately: an ordinary English word that also happens to be
// a symbol name in another unit. D-5 must NOT demote a summary on this, or
// every comment opening with Register / Create / Count / Backup would lose its
// summary. harvest_boundary.PlainProse's comment opens on it.
function Backup: Integer;

implementation

function SourceStampString: Integer;
begin
  Result := 1;
end;

function Backup: Integer;
begin
  Result := 2;
end;

end.
