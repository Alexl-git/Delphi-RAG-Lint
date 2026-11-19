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
  DRagLint.LSP.Feature.DocumentSymbol
  , DRagLint.LSP.Feature.Ping
  , DRagLint.LSP.Feature.CodeLens
  , DRagLint.LSP.Feature.ImplDecl
  , DRagLint.LSP.Feature.Rename
  , DRagLint.LSP.Feature.SemanticTokens
  , DRagLint.LSP.Feature.InlayHint
  , DRagLint.LSP.Feature.CallHierarchy
  , DRagLint.LSP.Feature.TypeHierarchy
  , DRagLint.LSP.Feature.TypeDefinition
  , DRagLint.LSP.Feature.DocumentHighlight
  , DRagLint.LSP.Feature.FoldingRange
  , DRagLint.LSP.Feature.ExecuteCommand
  ;

end.
