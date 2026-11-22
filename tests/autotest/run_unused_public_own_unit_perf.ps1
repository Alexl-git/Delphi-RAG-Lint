<#
  run_unused_public_own_unit_perf.ps1 -- v1523 EXPORT-PERF-FIX: unused-public-symbol's own-unit tier
  (TProjectLintRules.Run / IsOwnUnitOnly) asks idx_refs_name_nocase per queried symbol instead of
  loading every reference of the index.

  Part 1 (behaviour, generated fixture, no timing): three exported routines in uOwnA.
    OwnOnlyProc  referenced only inside uOwnA            -> own-unit hint MUST still fire
    SharedProc   referenced from uOwnB                   -> silent
    HomoProc     referenced in uOwnA and, case-different (HOMOPROC), in uOwnB -> silent (NOCASE homonym)
    NeverProc    never referenced                        -> flagged by the plain unused tier (control)
  Part 2 (timing, only with -BigDb and -BigFile): lint of ONE file against a big index; the
    unused-public-symbol stage in DRAGLINT_PROFILE output must stay under -StageBudgetSec (default 1.0 s;
    before the fix 8.1-10.8 s on a 712k-ref index, after 0.00 s) and wall under -WallBudgetSec when given.
  RED on a pre-fix build: Part 2 stage 8-10 s. Part 1 is behaviour-preserving by design (guards the predicate).
#>
[CmdletBinding()]
param(
  [string]$Exe = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-ownunit-perf-$PID",
  [string]$BigDb = '',
  [string]$BigFile = '',
  [double]$StageBudgetSec = 1.0,
  [double]$WallBudgetSec = 0
)
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = 0; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray } }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory -Force $Fx | Out-Null
$Db = Join-Path $WorkDir 'own.sqlite'
if (Test-Path $Db) { [IO.File]::Delete($Db) }

$a = @'
unit uOwnA;

interface

procedure OwnOnlyProc;
procedure SharedProc;
procedure HomoProc;
procedure NeverProc;
procedure Driver;

implementation

procedure OwnOnlyProc;
begin
end;

procedure SharedProc;
begin
end;

procedure HomoProc;
begin
end;

procedure NeverProc;
begin
end;

procedure Driver;
begin
  OwnOnlyProc;
  HomoProc;
end;

end.
'@
$b = @'
unit uOwnB;

interface

procedure UseIt;

implementation

uses
  uOwnA;

procedure UseIt;
begin
  SharedProc;
  HOMOPROC;
end;

end.
'@
[IO.File]::WriteAllText((Join-Path $Fx 'uOwnA.pas'), $a, [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $Fx 'uOwnB.pas'), $b, [Text.Encoding]::ASCII)

$null = & { $ErrorActionPreference = 'Continue'; & $Exe index $Fx --db $Db 2>&1 | ForEach-Object { "$_" } }
if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }

Write-Host "== own-unit tier of unused-public-symbol ($Exe)"
Push-Location $WorkDir
try { $raw = & { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --json 2>$null } | Out-String } finally { Pop-Location }
$f = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) | Where-Object { $_.rule -eq 'unused-public-symbol' }
function Hits($n) { @($f | Where-Object { $_.message -match "\b$n\b" }).Count }
Check 'OwnOnlyProc (referenced only in its own unit) is still hinted' ((Hits 'OwnOnlyProc') -ge 1) "got $(Hits 'OwnOnlyProc')"
Check 'SharedProc (referenced from another unit) is silent' ((Hits 'SharedProc') -eq 0) "got $(Hits 'SharedProc')"
Check 'HomoProc (case-different reference in another unit) is silent' ((Hits 'HomoProc') -eq 0) "got $(Hits 'HomoProc')"
Check 'CONTROL NeverProc (no reference) is flagged' ((Hits 'NeverProc') -ge 1) "got $(Hits 'NeverProc')"

if ($BigDb -and $BigFile) {
  Write-Host "== timing: 1-file lint against $BigDb"
  $env:DRAGLINT_PROFILE = '1'
  try {
    # run twice: the first run may be a rule-cache MISS; the second is the steady state
    foreach ($i in 1, 2) {
      $sw = [Diagnostics.Stopwatch]::StartNew()
      $out = & { $ErrorActionPreference = 'Continue'; & $Exe lint $BigFile --db $BigDb --json 2>&1 } | Out-String
      $sw.Stop()
    }
  } finally { Remove-Item Env:DRAGLINT_PROFILE -ErrorAction SilentlyContinue }
  $m = [regex]::Match($out, 'unused-public-symbol\s+([0-9.]+) s')
  $stage = if ($m.Success) { [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) } else { 0 }
  Check "unused-public-symbol stage <= $StageBudgetSec s (got $stage s)" ($m.Success -and $stage -le $StageBudgetSec)
  if ($WallBudgetSec -gt 0) { Check "wall <= $WallBudgetSec s (got $([math]::Round($sw.Elapsed.TotalSeconds,1)) s)" ($sw.Elapsed.TotalSeconds -le $WallBudgetSec) }
}

Write-Host ("== {0} passed, {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 } else { exit 0 }
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
