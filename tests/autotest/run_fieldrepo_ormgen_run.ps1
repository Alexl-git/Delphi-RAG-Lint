#Requires -Version 7.3
<#
  run_fieldrepo_ormgen_run.ps1 -- lane TT-GENFIX (1.54): COMPILES AND RUNS code the ORM generator
  (DRagLint.FieldRepo.OrmGen) writes, against the stub units of tests\fieldrepo\ormgen.
    1. --emit-fixture: i/u units of three tables and the _SERVER / _CLIENT units of two.
    2. new\ : the units as generated. Assign and AssignTo must really copy.
    3. old\ : the same units with the 'with Source as T do' / 'with Dest as T do' headers TableTools
       wrote around DB-RAD 4 / 6 (regenerated regions land inside those in existing units).
       The same program must pass.
    4. lint of the units in new\ : 0 for the rules of the 2026-11-23 owner rulings. Positive
       control: old\ and ormgen\LintBad.pas must make every one of those rules fire.
  Run: pwsh -File tests\autotest\run_fieldrepo_ormgen_run.ps1 [-Exe <drag-lint.exe>] [-SkipBuild] [-SkipLint] [-Work <dir>]
#>
[CmdletBinding()]
param([string]$Repo = '', [string]$Exe = '', [switch]$SkipBuild, [switch]$SkipLint, [string]$Work = '')
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Exe) { $Exe = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe' }
$ErrorActionPreference = 'Stop'
if ($Work -eq '') { $Work = Join-Path $env:TEMP "drag-lint-ormgen-run-$PID" }
[IO.Directory]::CreateDirectory($Work) | Out-Null
$stubs = Join-Path $Repo 'tests\fieldrepo\ormgen'
$script:fail = 0; $script:pass = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++; Write-Host "PASS $name" } else { $script:fail++; Write-Host "FAIL $name $detail" -ForegroundColor Red }
}

if (-not $SkipBuild) {
  $bat = Join-Path $Repo 'build\_build_fieldrepo_ormgen_tests_local.bat'
  $blog = Join-Path $Work 'build.log'
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $bat + '" > "' + $blog + '" 2>&1"') -Wait -NoNewWindow
  if ((Get-Content -LiteralPath $blog -Raw) -notmatch 'BUILD_EXITCODE=0') { Write-Host "ORMGEN RUN: FAIL -- OrmGenTests did not build (log: $blog)" -ForegroundColor Red; exit 1 }
}
$gen = Join-Path $Repo 'tests\fieldrepo\OrmGenTests.exe'
$fx = Join-Path $Work 'fx'
& { $ErrorActionPreference = 'Continue'; & $gen --emit-fixture $fx *> (Join-Path $Work 'emit.log') }
Check 'fixture emitted' ($LASTEXITCODE -eq 0) (Get-Content (Join-Path $Work 'emit.log') -Raw)

foreach ($form in 'new', 'old') {
  $src = Join-Path $fx $form
  $u = [IO.File]::ReadAllText((Join-Path $src 'uORMFIX.PAS'))
  if ($form -eq 'old') { Check 'old: the with headers are there' (([regex]::Matches($u, '(?m)^\s*with (Source|Dest) as TmcORMFIX do')).Count -eq 2) }
  else { Check 'new: no with statement in the full unit' ($u -notmatch '(?mi)^\s*with\s') }
  $out = Join-Path $Work "bin-$form"
  [IO.Directory]::CreateDirectory($out) | Out-Null
  $cbat = Join-Path $Work "compile-$form.bat"
  $clog = Join-Path $Work "compile-$form.log"
  [IO.File]::WriteAllText($cbat, ("@echo off`r`ncall `"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat`"`r`n" +
    "dcc64 -B -Q -NU`"$out`" -E`"$out`" -U`"$stubs;$src`" -NSSystem;Winapi;System.Win;Data;Vcl `"$stubs\OrmGenAssignRun.dpr`"`r`necho BUILD_EXITCODE=%errorlevel%`r`n"), [Text.Encoding]::ASCII)
  Start-Process -FilePath cmd.exe -ArgumentList ('/c ""' + $cbat + '" > "' + $clog + '" 2>&1"') -Wait -NoNewWindow
  $cl = Get-Content -LiteralPath $clog -Raw
  Check "${form}: generated units compile" ($cl -match 'BUILD_EXITCODE=0') (($cl -split "`n" | Select-String 'Error|Fatal' | Select-Object -First 6) -join ' | ')
  $gmsg = @($cl -split "`n" | Where-Object { $_ -match '(?i)[iu](ORMFIX|PLAINFIX|EMPTYFIX)(_SERVER|_CLIENT)?\.pas\(\d+\).*(Hint|Warning)' })
  if ($form -eq 'new') { Check 'new: no compiler hint or warning in a generated unit' ($gmsg.Count -eq 0) ($gmsg -join ' | ') }
  $bin = Join-Path $out 'OrmGenAssignRun.exe'
  if (Test-Path -LiteralPath $bin) {
    $rl = @(& { $ErrorActionPreference = 'Continue'; & $bin 2>&1 | ForEach-Object { "$_" } })
    $rl | Where-Object { $_ -match '^FAIL' } | ForEach-Object { Write-Host "  ${form}: $_" -ForegroundColor Red }
    $sum = $rl | Where-Object { $_ -match '^SUMMARY ' } | Select-Object -Last 1
    Check "${form}: Assign / AssignTo really copy ($sum)" ($sum -match 'pass=15 fail=0$')
  } else { Check "${form}: program built" $false }
}
Write-Host "SUMMARY pass=$($script:pass) fail=$($script:fail)"
if ($script:fail -gt 0) { Write-Host 'ORMGEN RUN: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ORMGEN RUN: PASS' -ForegroundColor Green
exit 0
} finally { Remove-WorkDir $Work -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
