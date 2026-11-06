#Requires -Version 7
<#
  run_lsp_folding_range_guard.ps1 -- `textDocument/foldingRange` (lane 145 lsp).

  The fixture file is NOT in the index (the db holds an unrelated unit): folding is a tree-sitter feature and
  must work without one.
  Positive controls (a handler answering [] or folding every line fails them):
    initialize advertises foldingRangeProvider.
    a multi-line `uses` -> a fold of kind "imports" from its first line.
    the class declaration -> a fold from `TThing = class` to the line BEFORE `end;`.
    the routine -> a fold from its header, and the begin..end block inside it a fold from `begin`.
    a multi-line { } comment -> kind "comment".
  Controls that must NOT fold: a one-line begin..end, a one-line comment, a one-line class forward.
  A closed buffer is read from disk; an unreadable path answers [] (not an error).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-fold-$PID"
)
if (-not $Exe) { $Exe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\src\cli\Win64\Debug\drag-lint.exe' }
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lsp_stdio_helpers.ps1')
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null
$other = Join-Path $WorkDir 'other'; New-Item -ItemType Directory $other | Out-Null

WriteAnsi (Join-Path $src 'uOther.pas') "unit uOther;`ninterface`nimplementation`nend.`n"
$file = Join-Path $other 'uFold.pas'
WriteAnsi $file @'
unit uFold;

interface

uses
  System.SysUtils,
  System.Classes;

{ a block comment
  over two lines }
// one line comment

type
  TFwd = class;

  TThing = class
  private
    FValue: Integer;
  public
    procedure Run;
  end;

procedure Tiny;

implementation

procedure TThing.Run;
begin
  FValue:= 1;
  if FValue > 0 then
  begin
    FValue:= 2;
  end;
end;

procedure Tiny;
begin end;

end.
'@

$db = Join-Path $WorkDir 'fold.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $src --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'unrelated unit indexed (the fixture itself is not)' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern, [int]$from = 0) { for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } } return -1 }
$uri = 'file:///' + ($file -replace '\\', '/')
$ghost = 'file:///' + ((Join-Path $WorkDir 'nothere.pas') -replace '\\', '/')
$r = LspSession $Exe $WorkDir $db @(
  @{ method='textDocument/foldingRange'; params=@{ textDocument=@{ uri=$uri } } },     # 11
  @{ method='textDocument/foldingRange'; params=@{ textDocument=@{ uri=$ghost } } }    # 12
)
Check 'initialize advertises foldingRangeProvider' ($r.init.capabilities.foldingRangeProvider -eq $true)
Check 'foldingRange answered (not -32601)' ($r.res.ContainsKey(11)) $(if ($r.err.Count) { 'error=' + (($r.err.Values | % { $_.code }) -join ',') })
if (-not $r.res.ContainsKey(11)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }
$f = @($r.res[11][0])
function FoldAt([int]$start) { return @($f | ? { $_.startLine -eq $start }) }
$lUses = LineOf '^uses$'; $lSemi = LineOf '^  System\.Classes;'
$lClass = LineOf '^  TThing = class'; $lClassEnd = LineOf '^  end;$' $lClass
$lRun = LineOf '^procedure TThing\.Run;'; $lRunEnd = LineOf '^end;$' $lRun
$lBegin = LineOf '^begin$' $lRun
$lIfBegin = LineOf '^  begin$' $lRun; $lIfEnd = LineOf '^  end;$' $lIfBegin
$lCom = LineOf '^\{ a block comment'; $lOne = LineOf '^// one line'
$lFwd = LineOf '^  TFwd = class;'; $lTiny = LineOf '^begin end;'
Write-Host ("  folds: " + (($f | % { "$($_.startLine)-$($_.endLine)$(if ($_.kind) { ':' + $_.kind })" }) -join ' ')) -ForegroundColor DarkGray

$u = FoldAt $lUses
Check 'uses clause folds, kind imports, ending on its last line' ($u.Count -eq 1 -and $u[0].kind -eq 'imports' -and $u[0].endLine -eq $lSemi) "got=$($u.Count)/$($u[0].kind)/$($u[0].endLine) want-end=$lSemi"
$c = FoldAt $lClass
Check 'class folds from its header to the line before end;' ($c.Count -eq 1 -and $c[0].endLine -eq ($lClassEnd - 1)) "got=$($c.Count)/$($c[0].endLine) want=$($lClassEnd - 1)"
$ru = FoldAt $lRun
Check 'routine folds from its header, leaving the final end; visible' ($ru.Count -eq 1 -and $ru[0].endLine -eq ($lRunEnd - 1)) "got=$($ru.Count)/$($ru[0].endLine) want=$($lRunEnd - 1)"
$ib = FoldAt $lIfBegin
Check 'the nested begin..end block folds from its begin' ($ib.Count -eq 1 -and $ib[0].endLine -eq ($lIfEnd - 1)) "got=$($ib.Count)/$($ib[0].endLine) want=$($lIfEnd - 1)"
$cm = FoldAt $lCom
Check 'multi-line { } comment folds, kind comment' ($cm.Count -eq 1 -and $cm[0].kind -eq 'comment' -and $cm[0].endLine -eq ($lCom + 1)) "got=$($cm.Count)/$($cm[0].kind)/$($cm[0].endLine)"
Check 'one-line comment does not fold' ((FoldAt $lOne).Count -eq 0)
Check 'one-line class forward does not fold' ((FoldAt $lFwd).Count -eq 0)
Check 'one-line begin end does not fold' ((FoldAt $lTiny).Count -eq 0)
Check 'every fold spans at least two lines and stays inside the file' (@($f | ? { $_.endLine -le $_.startLine -or $_.endLine -ge $lines.Count }).Count -eq 0)
Check 'an unreadable path answers [] (not an error)' ($r.res.ContainsKey(12) -and @($r.res[12][0]).Count -eq 0 -and -not $r.err.ContainsKey(12))

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
