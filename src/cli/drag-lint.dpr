program drag_lint;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  TreeSitterLib in '..\..\third_party\delphi-tree-sitter\TreeSitterLib.pas',
  TreeSitter.Query in '..\..\third_party\delphi-tree-sitter\TreeSitter.Query.pas',
  DRagLint.Core.Model in '..\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces in '..\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Core.Indexer in '..\core\DRagLint.Core.Indexer.pas',
  DRagLint.Storage.Schema in '..\storage\DRagLint.Storage.Schema.pas',
  DRagLint.Storage.SQLite in '..\storage\DRagLint.Storage.SQLite.pas',
  DRagLint.Parser.Delphi13 in '..\parser\DRagLint.Parser.Delphi13.pas',
  DRagLint.Parser.DFM in '..\parser\DRagLint.Parser.DFM.pas',
  DRagLint.Parser.DocComments in '..\parser\DRagLint.Parser.DocComments.pas',
  DRagLint.Query.Fuzzy in '..\query\DRagLint.Query.Fuzzy.pas',
  DRagLint.Lint.QueryRules in '..\lint\DRagLint.Lint.QueryRules.pas',
  DRagLint.Lint.Linter in '..\lint\DRagLint.Lint.Linter.pas',
  DRagLint.Lint.ProjectChecks in '..\lint\DRagLint.Lint.ProjectChecks.pas',
  DRagLint.Project.Resolver in '..\project\DRagLint.Project.Resolver.pas',
  DRagLint.MCP.Server in '..\mcp\DRagLint.MCP.Server.pas',
  DRagLint.LSP.Server in '..\lsp\DRagLint.LSP.Server.pas',
  DRagLint.Hover.Renderer in 'DRagLint.Hover.Renderer.pas',
  DRagLint.Context.Bundler in '..\context\DRagLint.Context.Bundler.pas',
  DRagLint.Resolver.TypeAt in '..\resolver\DRagLint.Resolver.TypeAt.pas',
  DRagLint.CLI in 'DRagLint.CLI.pas';

begin
  ExitCode := DRagLint.CLI.Run;
end.
