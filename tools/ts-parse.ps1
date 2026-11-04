<#
  ts-parse.ps1 -- parse a Delphi file with the tree-sitter CLI WITHOUT the grammar-cache trap.

  Trap (TS-PARSE-GRAMMAR-CACHE): a bare `tree-sitter parse x.pas` chooses the grammar from the
  CLI's parser-directories (C:\Projects holds tree-sitter-delphi13, tree-sitter-pascal and the
  tree-sitter-delphi13-wt worktree), by extension: .pas / .dpr match BOTH source.delphi and
  source.pascal, and the compiled grammar comes from %LOCALAPPDATA%\tree-sitter\lib, rebuilt
  silently from whatever the C:\Projects\tree-sitter-delphi13 working copy holds right now --
  not from the tree-sitter-delphi13.dll the engine ships. A node kind you "discover" this way
  can differ from what drag-lint's .scm rules see.

  This wrapper forces --scope (default source.delphi), prints which grammar directory it parsed
  with (git HEAD, dirty or clean) and WARNS when that working copy is newer than the
  tree-sitter-delphi13.dll beside the engine. Output: the CLI's tree on stdout, notes on stderr.

  Usage: pwsh -File tools\ts-parse.ps1 <file.pas> [-Scope source.delphi|source.dfm] [-Engine <drag-lint.exe>]
#>
param(
  [Parameter(Mandatory)][string]$File,
  [string]$Scope = 'source.delphi',
  [string]$Engine = (Join-Path $PSScriptRoot '..\third_party\dll-win64\drag-lint.exe'),
  [string]$Cli = 'C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe'
)
$ErrorActionPreference = 'Stop'
$grammarDir = if ($Scope -eq 'source.dfm') { 'C:\Projects\tree-sitter-DFM' } else { 'C:\Projects\tree-sitter-delphi13' }
$head  = (git -C $grammarDir rev-parse --short HEAD 2>$null)
$dirty = @(git -C $grammarDir status --porcelain 2>$null).Count
[Console]::Error.WriteLine("ts-parse: scope=$Scope grammar=$grammarDir HEAD=$head $(if ($dirty) { "DIRTY ($dirty path(s))" } else { 'clean' })")
$dllName = if ($Scope -eq 'source.dfm') { 'tree-sitter-dfm.dll' } else { 'tree-sitter-delphi13.dll' }
$shipped = Join-Path (Split-Path (Resolve-Path $Engine).Path) $dllName
$parserC = Join-Path $grammarDir 'src\parser.c'
if ((Test-Path $shipped) -and (Test-Path $parserC) -and ((Get-Item $parserC).LastWriteTime -gt (Get-Item $shipped).LastWriteTime)) {
  [Console]::Error.WriteLine("ts-parse: WARNING $parserC is newer than the engine's $shipped -- this tree may differ from what drag-lint rules see")
}
& $Cli parse --scope $Scope $File
exit $LASTEXITCODE