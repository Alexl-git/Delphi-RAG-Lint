unit DRagLint.Fix.Store;

{ Lane A5 -- store-backed fixers (9 ids; every edit proved by the index) of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md). Created EMPTY by lane
  A0 and already listed in drag-lint.dpr / .dproj, so the lane edits only this
  unit: one per-finding or per-file fixer per id, registered from
  RegisterFixers with DRagLint.Lint.Autofix.RegisterFixer / RegisterFileFixer. }

interface

/// <summary>Registers this unit's fixers with DRagLint.Lint.Autofix.</summary>
/// <remarks>Called once from DRagLint.Lint.Autofix's initialization, before any
/// lint runs. Empty until lane A5 lands.</remarks>
procedure RegisterFixers;

implementation

procedure RegisterFixers;
begin
  { empty until lane A5 registers its fixers here }
end;

end.