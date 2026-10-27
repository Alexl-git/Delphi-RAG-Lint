unit DRagLint.Fix.Decl;

{ Lane A4 -- declaration / directive fixers (8 ids) of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md). Created EMPTY by lane
  A0 and already listed in drag-lint.dpr / .dproj, so the lane edits only this
  unit: one per-finding or per-file fixer per id, registered from
  RegisterFixers with DRagLint.Lint.Autofix.RegisterFixer / RegisterFileFixer. }

interface

/// <summary>Registers this unit's fixers with DRagLint.Lint.Autofix.</summary>
/// <remarks>Called once from DRagLint.Lint.Autofix's initialization, before any
/// lint runs. Empty until lane A4 lands.</remarks>
procedure RegisterFixers;

implementation

procedure RegisterFixers;
begin
  { empty until lane A4 registers its fixers here }
end;

end.