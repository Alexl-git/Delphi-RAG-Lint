#Requires -Version 7.3
<#
  run_fieldrepo_constgen.ps1 -- the field-repository registry-constant generator (repo gen-const):
    A. builds and runs tests\fieldrepo\ConstGenTests.dpr (unit DRagLint.FieldRepo.ConstGen);
    B. the compile + round-trip proof: for the golden (v1), edge (v1) and golden_v2 fixtures it restores a temp
       repository with the engine, runs `repo gen-const --memtable`, compiles tests\fixtures\fieldrepo\constgen\
       ConstProbe.dpr (dcc32) against the generated unit, runs it and requires its dump to equal the
       `repo backup` sections of the four generated tables;
    C. the CLI exits: unknown / refused --table, bad --unit, missing --output, missing folder = 2; --dry-run writes nothing.

  A MISSING Delphi toolchain, engine exe or test exe is a FAIL here, never a skip.

  Parameters:
    -Repo       repo root (default: two levels above this script)
    -Exe        drag-lint.exe that has the gen-const verb (default: <Repo>\src\cli\Win64\Debug\drag-lint.exe)
    -SkipBuild  run the test exe already on disk
#>
[CmdletBinding()]
param([string]$Repo = '',
      [string]$Exe = '',
      [switch]$SkipBuild)
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
if (-not $Exe) { $Exe = Join-Path $Repo 'src\cli\Win64\Debug\drag-lint.exe' }
$ErrorActionPreference = 'Stop'
Write-Host '== field repository constant generator ==' -ForegroundColor Cyan
$script:fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { Write-Host "  PASS $name" } else { $script:fail++; Write-Host "  FAIL $name $detail" -ForegroundColor Red }
}
$work = Join-Path $env:TEMP "drag-lint-fieldrepo-constgen-$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
try {
  # ---- A. unit tests ----
  $bat = Join-Path $Repo 'build\_build_fieldrepo_constgen_tests_local.bat'
  $bin = Join-Path $Repo 'tests\fieldrepo\ConstGenTests.exe'
  if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $bat)) { Write-Host "FIELDREPO CONSTGEN: FAIL -- build script missing: $bat" -ForegroundColor Red; exit 1 }
    $blog = Join-Path $work 'build.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $bat + [char]34 + ' > ' + [char]34 + $blog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $bl = Get-Content -LiteralPath $blog -Raw
    if (($bl -notmatch 'BUILD_EXITCODE=0') -or ($bl -match '\[dcc\w*\] Error|: error ')) {
      Write-Host "FIELDREPO CONSTGEN: FAIL -- the test runner did not build (log: $blog)" -ForegroundColor Red; exit 1
    }
  }
  if (-not (Test-Path -LiteralPath $bin)) { Write-Host "FIELDREPO CONSTGEN: FAIL -- test exe not found: $bin" -ForegroundColor Red; exit 1 }
  $log = Join-Path $work 'run.log'
  & { $ErrorActionPreference = 'Continue'; & $bin *> $log }
  $code = $LASTEXITCODE
  $sum = Select-String -LiteralPath $log -Pattern '^SUMMARY ' | Select-Object -Last 1
  Select-String -LiteralPath $log -Pattern '^FAIL|^SKIP' | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
  Check 'A1 unit tests: SUMMARY present, fail=0, exit 0, no SKIP' (($null -ne $sum) -and ($code -eq 0) -and ($sum.Line -match 'fail=0\b') -and (@(Select-String -LiteralPath $log -Pattern '^SKIP').Count -eq 0)) "$($sum.Line)"
  if ($sum) { Write-Host "  $($sum.Line)" }

  # ---- B / C. engine + compile ----
  if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FIELDREPO CONSTGEN: FAIL -- engine exe not found: $Exe" -ForegroundColor Red; exit 1 }
  if (-not (Test-Path -LiteralPath $rsvars)) { Write-Host "FIELDREPO CONSTGEN: FAIL -- rsvars.bat not found (no Delphi toolchain)" -ForegroundColor Red; exit 1 }
  $fix = Join-Path $Repo 'tests\fixtures\fieldrepo'
  $probeSrc = Join-Path $Repo 'tests\fixtures\fieldrepo\constgen\ConstProbe.dpr'
  $gen4 = @('DL_FIELDS_INFO', 'DL_DATASETS_INFO', 'DL_ENUMVALUES', 'DL_ERROR_MESSAGES')

  function Get-Sections([string[]]$lines) {
    $out = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
      $cur.Add($l)
      if ($l -match '^#end (\S+) \d+$') {
        if ($gen4 -contains $Matches[1]) { foreach ($c in $cur) { $out.Add($c) } }
        $cur.Clear()
      }
    }
    return ,$out.ToArray()
  }

  $cases = @(@{ n = 'golden v1'; f = 'golden.dlrepo.txt'; v = 1 }, @{ n = 'edge v1'; f = 'edge.dlrepo.txt'; v = 1 }, @{ n = 'golden v2'; f = 'golden_v2.txt'; v = 2 })
  $k = 0
  foreach ($c in $cases) {
    $k++
    $d = Join-Path $work "case$k"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $repoFile = Join-Path $d 'r.dlrepo'
    $unitFile = Join-Path $d 'uFieldRegistry.pas'
    $bk = Join-Path $d 'bk.txt'
    $r = & $Exe repo restore --repo $repoFile --in (Join-Path $fix $c.f) 2>&1
    Check "B$k.1 $($c.n): restore into a temp repository" ($LASTEXITCODE -eq 0) "$r"
    $r = & $Exe repo gen-const --repo $repoFile --unit uFieldRegistry --output $unitFile --memtable 2>&1
    Check "B$k.2 $($c.n): gen-const writes the unit" (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $unitFile)) "$r"
    $r1 = [IO.File]::ReadAllBytes($unitFile)
    & $Exe repo gen-const --repo $repoFile --unit uFieldRegistry --output (Join-Path $d 'again.pas') --memtable *> $null
    $r2 = [IO.File]::ReadAllBytes((Join-Path $d 'again.pas'))
    Check "B$k.3 $($c.n): two runs give identical bytes" ([System.Linq.Enumerable]::SequenceEqual([byte[]]$r1, [byte[]]$r2))
    $r = & $Exe repo backup --repo $repoFile --output $bk 2>&1
    Check "B$k.4 $($c.n): backup of the same repository" ($LASTEXITCODE -eq 0) "$r"
    # compile the probe against the generated unit
    $pdir = Join-Path $d 'probe'
    New-Item -ItemType Directory -Path $pdir -Force | Out-Null
    Copy-Item -LiteralPath $probeSrc -Destination $pdir
    $cb = Join-Path $d 'c.bat'
    $sql = Join-Path $Repo 'src\sql'
    Set-Content -LiteralPath $cb -Encoding Ascii -Value @(
      '@echo off', "call `"$rsvars`"", "cd /D `"$pdir`"", 'if not exist dcu mkdir dcu',
      "dcc32 -B -NUdcu -E. -U`"$sql`";`"$d`" -NSSystem;Winapi;System.Win;Data;FireDAC ConstProbe.dpr", 'echo BUILD_EXITCODE=%errorlevel%')
    $clog = Join-Path $d 'compile.log'
    Start-Process -FilePath cmd.exe -ArgumentList (('/c ' + [char]34 + [char]34 + $cb + [char]34 + ' > ' + [char]34 + $clog + [char]34 + ' 2>&1' + [char]34)) -Wait -NoNewWindow
    $cl = Get-Content -LiteralPath $clog -Raw
    $built = ($cl -match 'BUILD_EXITCODE=0') -and ($cl -notmatch '\[dcc\w*\] Error|: error ') -and (Test-Path -LiteralPath (Join-Path $pdir 'ConstProbe.exe'))
    Check "B$k.5 $($c.n): the probe compiles against the generated unit" $built "(log: $clog)"
    if ($built) {
      $dump = & (Join-Path $pdir 'ConstProbe.exe') $c.v
      Check "B$k.6 $($c.n): the probe ran" ($LASTEXITCODE -eq 0) "$($dump | Select-Object -First 2)"
      $want = Get-Sections ([IO.File]::ReadAllLines($bk))
      $got = @($dump)
      $same = ($want.Count -eq $got.Count) -and ((Compare-Object $want $got -SyncWindow 0).Count -eq 0)
      Check "B$k.7 $($c.n): memtable dump equals the backup of the four tables ($($want.Count) lines)" $same "want $($want.Count) got $($got.Count)"
    }
  }

  # ---- C. CLI exits ----
  $d = Join-Path $work 'cli'
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  $rf = Join-Path $d 'r.dlrepo'
  & $Exe repo restore --repo $rf --in (Join-Path $fix 'golden.dlrepo.txt') *> $null
  $o = Join-Path $d 'o.pas'
  $null = & $Exe repo gen-const --repo $rf --table NOPE --output $o 2>&1;                Check 'C1 unknown --table exits 2' ($LASTEXITCODE -eq 2)
  $null = & $Exe repo gen-const --repo $rf --table DL_META --output $o 2>&1;            Check 'C2 DL_META in --table exits 2' ($LASTEXITCODE -eq 2)
  $null = & $Exe repo gen-const --repo $rf --table DL_GENERATORS --output $o 2>&1;      Check 'C3 DL_GENERATORS in --table exits 2' ($LASTEXITCODE -eq 2)
  $null = & $Exe repo gen-const --repo $rf --unit 1bad --output $o 2>&1;                Check 'C4 --unit not an identifier exits 2' ($LASTEXITCODE -eq 2)
  $null = & $Exe repo gen-const --repo $rf 2>&1;                                        Check 'C5 no --output exits 2' ($LASTEXITCODE -eq 2)
  $null = & $Exe repo gen-const --repo $rf --output (Join-Path $d 'nofolder\o.pas') 2>&1; Check 'C6 missing output folder exits 2' ($LASTEXITCODE -eq 2)
  Check 'C7 no refused call wrote a file' (-not (Test-Path -LiteralPath $o))
  $r = & $Exe repo gen-const --repo $rf --dry-run --output $o 2>&1
  Check 'C8 --dry-run exits 0, prints counts, writes nothing' (($LASTEXITCODE -eq 0) -and (($r -join "`n") -match 'DL_FIELDS_INFO: 6 rows') -and (-not (Test-Path -LiteralPath $o)))
  $null = & $Exe repo gen-const --repo $rf --table dl_enumvalues,DL_ERROR_MESSAGES --output $o 2>&1
  $txt = if (Test-Path -LiteralPath $o) { Get-Content -LiteralPath $o -Raw } else { '' }
  Check 'C9 --table subset (case-insensitive, comma list) emits only those tables' (($LASTEXITCODE -eq 0) -and ($txt -match 'TDL_ENUMVALUESRow') -and ($txt -notmatch 'TDL_FIELDS_INFORow'))

  if ($script:fail -gt 0) { Write-Host "FIELDREPO CONSTGEN: FAIL ($($script:fail) check(s))" -ForegroundColor Red; exit 1 }
  Write-Host 'FIELDREPO CONSTGEN: PASS' -ForegroundColor Green
  exit 0
} finally {
  if (Test-Path -LiteralPath $work) { [IO.Directory]::Delete($work, $true) }
}
