unit markedprose;

// The two shapes this fixture exists to separate, and why one file holds both.
//
// The defect (session 74): a <summary> carrying AUTO_MARK but holding a HUMAN's
// prose was DELETED outright by --apply, because the engine read the marker as
// "mine", found it had nothing harvested to refill the tag with, and applied the
// omit-when-empty rule to words it did not write. Reproduced on real source
// first: DRagLint.Lint.Linter.pas's HarvestExceptions lost 53 words.
//
// The fix must not be "marked means the human's", because the engine emits its
// OWN harvested summaries under that same bare marker -- 102 of them in src\ at
// the time of the fix, and NONE with a blank body. A blanket reading would
// freeze every one of them on the next run. So Refreshable below is not
// decoration: it is the regression guard that the narrow fix stayed narrow.
//
// EVERY EXPLANATION LIVES IN THIS HEADER, AND THAT IS A CONSTRAINT, NOT A STYLE
// CHOICE. NothingToHarvest must have NO // comment above EITHER its interface
// declaration OR its implementation -- the harvest scans both. Two successive
// drafts of this fixture put an explanatory comment in each of those places;
// each time the engine harvested that very sentence into the summary, the
// refill arm fired instead of the arm under test, and the runner failed
// IDENTICALLY before and after the fix. That reads as "the fix does not work"
// when it actually means "the fixture does not reproduce the shape".
//
// Helper and Refreshable are far enough from this block not to pick it up (the
// boundary scan stops at `interface`); if that ever changes, Helper gaining a
// summary is the canary.

interface

function Helper(const AName: string): Boolean;

/// <summary><!-- drag-lint:auto -->The first literal inside the argument list is
/// taken deliberately: that is the STATIC PREFIX, which is what a class name can
/// be derived from. Ruling 2 is still open and gates stage 3, not this.</summary>
function NothingToHarvest(const AName: string): Boolean;

// Real prose that the engine harvests into the summary.
/// <summary><!-- drag-lint:auto -->Stale engine text from an earlier run.</summary>
function Refreshable(const AName: string): Boolean;

implementation

function Helper(const AName: string): Boolean;
begin
  Result := AName <> '';
end;

function NothingToHarvest(const AName: string): Boolean;
begin
  Result := Helper(AName);
end;

function Refreshable(const AName: string): Boolean;
begin
  Result := Helper(AName);
end;

end.
