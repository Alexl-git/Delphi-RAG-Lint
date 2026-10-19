<#
  run_rename_inc_refuse.ps1 -- wave 3 lane I (stopgap until extractor 1.22
  emits references for {$I} included text).

  An .inc file gets a `files` row, but a code-fragment include parses on its
  own with errors and 0 refs, and the {$I} site in the host unit emits none.
  So `rename` used to rewrite the declaration and silently miss every use
  inside the include -- the renamed project no longer compiles.

  STOPGAP: rename (plan AND --apply, legacy --qname and --kind symbol) REFUSES
  with exit 2 and a message naming the .inc file(s) when the old name occurs
  as an identifier token (comments and string literals skipped) in an .inc
  file the index holds.

  FIXTURE A (bug): uHost.pas declares Helper and {$I body.inc}; body.inc
    calls Helper.  ASSERT: every rename form exits 2, names body.inc, and the
    sources are byte-identical afterwards.
  FIXTURE B (positive control): same host, but body.inc mentions Helper only
    in a comment and a string literal.  ASSERT: rename --apply exits 0 and
    the declaration IS rewritten (so the refusal in A is the .inc check, not
    a broken rename).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-inc-$PID"
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

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
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

$HostUnit = @'
unit uHost;

interface

function Helper: Integer;
procedure DoWork;

implementation

function Helper: Integer;
begin
  Result:= 1;
end;

procedure DoWork;
var
  X: Integer;
begin
  {$I body.inc}
end;

end.
'@

function New-Fixture([string]$Name, [string]$IncBody) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  Write-Ascii (Join-Path $src 'uHost.pas') $HostUnit
  Write-Ascii (Join-Path $src 'body.inc')  $IncBody
  $db = Join-Path $dir 'idx.sqlite'
  Push-Location $dir
  try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
  Check "$Name index exits 0" ($LASTEXITCODE -eq 0)
  [pscustomobject]@{ Dir = $dir; Src = $src; Db = $db }
}

function Snapshot($fx) {
  (Get-ChildItem $fx.Src -File | Sort-Object Name | ForEach-Object { $_.Name + '=' + (Get-Content -Raw $_.FullName) }) -join '|'
}

function Run-Rename($fx, [string[]]$RenameArgs) {
  Push-Location $fx.Dir
  try { $o = & $Exe rename @RenameArgs --db $fx.Db 2>&1 } finally { Pop-Location }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($o -join "`n") }
}

# ---------------- A: the include USES the name -> refuse ----------------
Write-Host 'Fixture A: body.inc calls Helper' -ForegroundColor Cyan
$a = New-Fixture 'A' "  X:= Helper; { Helper }`r`n"
$before = Snapshot $a
$forms = @(
  @{ N = 'legacy --dry-run';       A = @('--qname', 'uHost.Helper', '--to', 'Helper2', '--dry-run') },
  @{ N = 'legacy --apply';         A = @('--qname', 'uHost.Helper', '--to', 'Helper2', '--apply') },
  @{ N = '--kind symbol plan';     A = @('--kind', 'symbol', '--name', 'uHost.Helper', '--to', 'Helper2') },
  @{ N = '--kind symbol --apply';  A = @('--kind', 'symbol', '--name', 'uHost.Helper', '--to', 'Helper2', '--apply') }
)
foreach ($f in $forms) {
  $r = Run-Rename $a $f.A
  Check "A $($f.N) exits 2"          ($r.Exit -eq 2)                 "exit=$($r.Exit)"
  Check "A $($f.N) names body.inc"   ($r.Out -match 'body\.inc')     ($r.Out -split "`n" | Select-Object -Last 1)
  Check "A $($f.N) says include"     ($r.Out -match '(?i)include')
}
Check 'A sources unchanged' ((Snapshot $a) -ceq $before)

# ------- B (positive control): name only in comment / string -> proceeds -------
Write-Host 'Fixture B: body.inc mentions Helper only in a comment and a string' -ForegroundColor Cyan
$b = New-Fixture 'B' "  // Helper`r`n  X:= Length('Helper'); (* Helper *)`r`n"
$r = Run-Rename $b @('--qname', 'uHost.Helper', '--to', 'Helper2', '--apply')
Write-Host $r.Out
Check 'B legacy --apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
$hostAfter = Get-Content -Raw (Join-Path $b.Src 'uHost.pas')
Check 'B declaration rewritten' ($hostAfter -cmatch 'function Helper2: Integer;')

} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  $script:Failed = $true
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:Failed) { Write-Host 'run_rename_inc_refuse: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_rename_inc_refuse: PASS' -ForegroundColor Green
exit 0
