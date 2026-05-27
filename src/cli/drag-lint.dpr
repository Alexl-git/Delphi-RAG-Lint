program drag_lint;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  TreeSitter in '..\..\third_party\delphi-tree-sitter\TreeSitter.pas',
  TreeSitterLib in '..\..\third_party\delphi-tree-sitter\TreeSitterLib.pas',
  DRagLint.Core.Model in '..\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces in '..\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Core.Indexer in '..\core\DRagLint.Core.Indexer.pas',
  DRagLint.Storage.Schema in '..\storage\DRagLint.Storage.Schema.pas',
  DRagLint.Storage.SQLite in '..\storage\DRagLint.Storage.SQLite.pas',
  DRagLint.Parser.Delphi13 in '..\parser\DRagLint.Parser.Delphi13.pas',
  DRagLint.CLI in 'DRagLint.CLI.pas';

begin
  ExitCode := DRagLint.CLI.Run;
end.
