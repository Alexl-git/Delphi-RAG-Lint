unit DRagLint.LSP.Features;

{ The aggregator: its `uses` names every LSP feature unit, so that linking this
  one unit runs every feature's `initialization` (RegisterLspFeature) before the
  server builds its method table. DRagLint.LSP.Server uses this unit; a feature
  that is not listed here is never registered.

  ADDING A FEATURE: create DRagLint.LSP.Feature.<Name>.pas, register it from its
  initialization, add it below AND to drag-lint.dpr / drag-lint.dproj. }

interface

implementation

uses
  DRagLint.LSP.Feature.DocumentSymbol  // dl:ok unused-unit-in-uses@b145 -- linked for its initialization (RegisterLspFeature); no identifier is referenced
  , DRagLint.LSP.Feature.Ping  // dl:ok unused-unit-in-uses@45bf -- linked for its initialization (RegisterLspFeature); no identifier is referenced
  , DRagLint.LSP.Feature.CodeLens  // dl:ok unused-unit-in-uses@ed85 -- linked for its initialization (RegisterLspFeature); no identifier is referenced
  , DRagLint.LSP.Feature.ImplDecl  // dl:ok unused-unit-in-uses@5294 -- linked for its initialization (RegisterLspFeature); no identifier is referenced
  , DRagLint.LSP.Feature.Rename  // dl:ok unused-unit-in-uses@6450 -- linked for its initialization (RegisterLspFeature); no identifier is referenced
  ;

end.
