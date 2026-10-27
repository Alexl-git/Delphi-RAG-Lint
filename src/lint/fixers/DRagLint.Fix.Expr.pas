unit DRagLint.Fix.Expr;

{ Lane A2 -- expression-level code fixers (16 ids) of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md). Created EMPTY by lane
  A0 and already listed in drag-lint.dpr / .dproj, so lane A2 edits only this
  unit. The shape every fixer unit follows:

    implementation
    uses DRagLint.Core.Model, DRagLint.Refactor.TextEdit, DRagLint.Lint.Autofix, ...;
    function FixFoo(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
    ...
    initialization
      RegisterFixer('foo-rule', FixFoo);              (or RegisterFileFixer; True = risky)

  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. }

interface

implementation

end.