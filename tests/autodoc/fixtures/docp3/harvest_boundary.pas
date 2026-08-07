unit harvest_boundary;

{ Fixture for PHASE A1 -- the harvest BOUNDARY rule (a blank source line ends
  the block), ruling D-5 (a first sentence naming a FOREIGN symbol is demoted to
  <remarks>), and ruling D-1 (a re-run must not duplicate prose a human has
  taken ownership of).

  Every declaration below is called by Driver with EXPLICIT PARENTHESES so it
  carries a caller fact. Without at least one fact the engine writes no doc
  block at all ("nothing to document") and every assertion about the harvest
  would be vacuous -- the same device harvest_text.pas and harvest_impl.pas use,
  and the parentheses are load-bearing for the same reason theirs are (a bare
  parameterless call as a binary-expression operand records no reference). }

interface

uses
  harvest_boundary_other;

// This note belongs to the section ABOVE and is not BlockBoundary's comment.
// It is deliberately ordinary prose, NOT a banner: the leading-banner drop in
// HarvestText would catch a row of dashes, so a banner here would pass even
// without the boundary rule and the case would prove nothing.

// Real prose that must become the summary.
function BlockBoundary: Integer;

// SourceStampString used to live here. It MOVED to harvest_boundary_other so
// that both callers share one copy instead of two.
function ForeignNote: Integer;

// LocalHelper does the actual work; this wrapper only adapts the result. A
// summary that mentions a symbol declared in ITS OWN unit is an ordinary
// cross-reference and must keep its summary.
function LocalMention: Integer;

// Backup happens before the copy step. The first word is an ordinary English
// word that is ALSO a symbol name in another unit, and a single-cased word is
// not a symbol reference -- so this summary must survive.
function PlainProse: Integer;

// Owned prose stays the summary.
//
// A second paragraph that a human adopts by deleting its provenance marker.
function OwnershipHandover: Integer;

function LocalHelper: Integer;

function Driver: Integer;

implementation

function BlockBoundary: Integer;
begin
  Result := 1;
end;

function ForeignNote: Integer;
begin
  Result := 2;
end;

function LocalHelper: Integer;
begin
  Result := 3;
end;

function LocalMention: Integer;
begin
  Result := LocalHelper();
end;

function PlainProse: Integer;
begin
  Result := 4;
end;

function OwnershipHandover: Integer;
begin
  Result := 5;
end;

function Driver: Integer;
begin
  Result := BlockBoundary() + ForeignNote() + LocalMention() + PlainProse() +
            OwnershipHandover() + LocalHelper();
end;

end.
