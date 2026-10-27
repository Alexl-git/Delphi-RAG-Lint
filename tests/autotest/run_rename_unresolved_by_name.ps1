<#
  run_rename_unresolved_by_name.ps1 -- E5 (ENGINE wave 1026c, lane X-RES).

  TRenameRefactoring.Build finds reference sites by NAME and filters them by
  the resolver's binding. A ref the resolver could NOT bind (symbol_id 0) used
  to be renamed unconditionally (Rename.pas, the `Ref.SymbolId <> 0` test), so
  renaming Unit1.TA.Process also rewrote `ExtThing.Process` in Unit3 -- a call
  whose receiver comes from a unit the index does not cover, and which may
  well be Unit2.TB.Process or a library method.

  Contract, renaming Unit1.TA.Process to Run:
    * a ref BOUND to the target is edited (Unit3 `A.Process`, A: TA);
    * an UNBOUND ref is edited only when no other indexed symbol carries the
      name (fixture P: Unit2 absent -> `ExtThing.Process` IS edited);
    * when another indexed symbol carries the name (fixture J/A: Unit2.TB.Process)
      the unbound ref is a CANDIDATE: it is not edited, and
      TRenameRefactoring.UnresolvedCandidateNotes names it (file:line:col and
      the other bearers) for the CLI / MCP to report;
    * Unit2 is byte-identical after --apply.
  Positive control: the pre-fix engine edits Unit3.pas:17 in fixtures J and A
  (watched RED before the fix).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-unresolved-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$Files = [ordered]@{}
$Files['Unit1.pas'] = @'
unit Unit1;

interface

type
  TA = class
  public
    procedure Process;
  end;

implementation

procedure TA.Process;
begin
end;

end.
'@
$Files['Unit2.pas'] = @'
unit Unit2;

interface

type
  TB = class
  public
    procedure Process;
  end;

implementation

procedure TB.Process;
begin
end;

end.
'@
# ExtLib is NOT in the fixture: ExtThing's type is unknown to the index, so
# `ExtThing.Process` (line 17) stays an unbound ref; `A.Process` (line 16) binds.
$Files['Unit3.pas'] = @'
unit Unit3;

interface

procedure Go;

implementation

uses
  Unit1, ExtLib;

procedure Go;
var
  A: TA;
begin
  A.Process;
  ExtThing.Process;
end;

end.
'@

function New-Fixture([string]$Tag, [string[]]$Skip = @()) {
  $dir = Join-Path $WorkDir $Tag
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src -Force | Out-Null
  foreach ($k in $Files.Keys) {
    if ($Skip -contains $k) { continue }
    Write-Ascii (Join-Path $src $k) $Files[$k]
  }
  $db = Join-Path $dir 'fx.sqlite'
  Push-Location $dir
  try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
  [pscustomobject]@{ Dir = $dir; Src = $src; Db = $db }
}
function Run-Rename($fx, [string[]]$RenameArgs) {
  Push-Location $fx.Dir
  try { $o = & $Exe rename @RenameArgs --db $fx.Db 2>&1 } finally { Pop-Location }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($o -join "`n") }
}
function FileHash($fx, [string]$Leaf) {
  [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fx.Src $Leaf)))
}
function Edit-Set($fx) {
  $r = Run-Rename $fx ($RenArgs + '--json')
  $edits = @()
  try { $edits = @(($r.Out -split "`n" | Where-Object { $_ -notmatch '^drag-lint: note:' -and $_ -notmatch '^\(loaded' }) -join "`n" | ConvertFrom-Json) } catch { }
  [pscustomobject]@{
    Exit = $r.Exit
    Out  = $r.Out
    Got  = @($edits | ForEach-Object { '{0}:{1}' -f (Split-Path -Leaf $_.file), $_.line } | Sort-Object)
  }
}

$RenArgs = @('--kind', 'symbol', '--name', 'Unit1.TA.Process', '--to', 'Run')

Write-Host 'Fixture J: an unbound ref whose name another symbol carries is not edited' -ForegroundColor Cyan
$j = New-Fixture 'J'
# Precondition: the fixture really has one bound and one unbound Process ref in Unit3.
$sq = "SELECT r.start_line AS l, r.symbol_id AS s FROM refs r JOIN files f ON f.id = r.file_id " +
      "WHERE f.path LIKE '%Unit3.pas' AND r.name_text = 'Process' ORDER BY r.start_line"
$raw = (& $Exe sql --db $j.Db --json --query $sq 2>$null) -join "`n"
$rows = @()
try { $rows = @(($raw | ConvertFrom-Json).rows) } catch { }
$unbound17 = (@($rows | Where-Object { $_[0] -eq 17 }).Count -gt 0) -and (@($rows | Where-Object { $_[0] -eq 17 -and $_[1] }).Count -eq 0)
$bound16   = @($rows | Where-Object { $_[0] -eq 16 -and $_[1] }).Count -gt 0
Check 'precondition: Unit3.pas:16 A.Process is bound'          $bound16   "rows=$(@($rows | ForEach-Object { $_ -join '/' }) -join ';')"
Check 'precondition: Unit3.pas:17 ExtThing.Process is unbound' $unbound17 "rows=$(@($rows | ForEach-Object { $_ -join '/' }) -join ';')"
$e = Edit-Set $j
Check 'J json exits 0' ($e.Exit -eq 0) "exit=$($e.Exit)"
$exp = @('Unit1.pas:13', 'Unit1.pas:8', 'Unit3.pas:16')
Check 'J edit set is exact (no Unit3.pas:17, no Unit2)' (($e.Got -join ',') -ceq (($exp | Sort-Object) -join ',')) "got=$($e.Got -join ',')"

Check 'J note names the candidate (E5, wired in CLI)' ($e.Out -cmatch 'drag-lint: note: .*Unit3\.pas:17:\d+: unresolved reference to "Process" not renamed') "out=$($e.Out)"

Write-Host 'Fixture A: --apply leaves the candidate and Unit2 alone' -ForegroundColor Cyan
$a = New-Fixture 'A'
$h2 = FileHash $a 'Unit2.pas'
$r = Run-Rename $a ($RenArgs + @('--apply', '--no-backup'))
Check 'A apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
$u3 = Get-Content -Raw (Join-Path $a.Src 'Unit3.pas')
Check 'A Unit3 bound call renamed'        ($u3 -cmatch '  A\.Run;\r\n')
Check 'A Unit3 unbound candidate kept'    ($u3 -cmatch '  ExtThing\.Process;\r\n')
Check 'A Unit2.pas byte-identical'        ((FileHash $a 'Unit2.pas') -ceq $h2)

Write-Host 'Fixture P (positive control): a name no other symbol carries is still renamed' -ForegroundColor Cyan
$p = New-Fixture 'P' @('Unit2.pas')
$e = Edit-Set $p
$exp = @('Unit1.pas:13', 'Unit1.pas:8', 'Unit3.pas:16', 'Unit3.pas:17')
Check 'P edit set includes the unbound ref' (($e.Got -join ',') -ceq (($exp | Sort-Object) -join ',')) "got=$($e.Got -join ',')"
Check 'P no candidate note when nothing else carries the name' ($e.Out -cnotmatch 'unresolved reference') "out=$($e.Out)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d25 in @("$env:TEMP\drag-lint-rename-unresolved-$PID")) { if (Test-Path -LiteralPath $d25) { Remove-Item -LiteralPath $d25 -Recurse -Force -ErrorAction SilentlyContinue } }
}
