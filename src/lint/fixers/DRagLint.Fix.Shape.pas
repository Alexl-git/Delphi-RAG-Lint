unit DRagLint.Fix.Shape;

{ Lane G2 -- shape fixers (interface-without-guid, collection-modified-in-loop, constructor-call-on-instance) of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md). Created EMPTY by lane
  A0 and already listed in drag-lint.dpr / .dproj, so the lane edits only this
  unit: one per-finding or per-file fixer per id, registered from
  RegisterFixers with DRagLint.Lint.Autofix.RegisterFixer / RegisterFileFixer. }

interface

/// <summary>Registers this unit's fixers with DRagLint.Lint.Autofix.</summary>
/// <remarks>Called once from DRagLint.Lint.Autofix's initialization, before any
/// lint runs. Empty until lane G2 lands.</remarks>
procedure RegisterFixers;

implementation

procedure RegisterFixers;
begin
  { empty until lane G2 registers its fixers here }
end;

end.