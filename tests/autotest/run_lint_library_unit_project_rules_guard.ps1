<#
  run_lint_library_unit_project_rules_guard.ps1 -- E29 (LSP report, 2026-10-26)

  `lint <Studio>\source\rtl\common\System.IOUtils.pas --json` never finished:
  > 490 CPU-s with `--db library-Win64.sqlite`, and the same with NO --db,
  because with no --db the manifest resolves library-Win32.sqlite, which
  CONTAINS the file. (The 5.5 s figure that looked like the fast case was a
  `--rule parser-error` run.)

  WHERE THE TIME WENT (DRAGLINT_PROFILE, engine copy, DB copy):
      setup 1.6 / scm-rules 2.9 / library-store 1.2 / ast 0.4 / type-aware 1.9
      flow 23.3 (wall, 100%-CPU box) / naming 0.3 / dead-code 0.3 / clone 0.1
      project-rules  -> never returned (killed at 150 s)
  Per rule, with --rule, 45 s cap each: unused-public-symbol, circular-uses,
  cycle-participant-unit, global-only-uses-edge, dfm-property-not-declared,
  duplicate-global-decl, uses-global-census all TIMED OUT; even
  unused-private-member took 28 s, all of it in the two whole-refs-table scans
  that run before any rule (GetReferencedSymbolIds / GetReferencedNamesLower).

  ROOT CAUSE. DoLint gives the project-rules block to ANY store that contains
  the file. The platform library contains every RTL/VCL unit, so a library unit
  got the WHOLE-STORE relational passes run over ~7,000 files -- to keep one
  file's answers. And those answers mean nothing for a library unit: who calls
  an RTL routine, or whether an RTL import is used, is a question about the
  CONSUMERS, which are not in the library index. ResolveFrameworkContextDb
  already rules the same way ("a library index is never the context"), with the
  same `library-` filename test.

  FIX. A store whose file name starts with `library-` still serves the per-file
  checkers (flow, type-aware, naming) but does not get the project-rules pass.

  A1  library-named store: no project-rules phase, no circular-uses finding,
      store still used by the per-file checkers (store=True, fid>0).
  A2  POSITIVE CONTROL -- the SAME fixture in a project-named store still runs
      the phase and reports circular-uses. A fix that switched the rules off for
      every store turns A2 red.
  A3  (opt-in, -LibraryDb + -LibraryUnit) the real E29 file against a COPY of the
      platform library: finishes under -CpuBudgetSec CPU seconds.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_lib_unit_projrules_$PID",
  [string]$LibraryDb   = '',
  [string]$LibraryUnit = '',
  [int]   $CpuBudgetSec = 30
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
Push-Location $WorkDir

# An interface-section uses cycle: circular-uses must fire for uCycA in a
# project store, and is the cheapest whole-store rule to observe.
Write-Ascii (Join-Path $src 'uCycA.pas') @'
unit uCycA;

interface

uses
  uCycB;

/// <summary>Fixture routine.</summary>
function A1: Integer;

implementation

function A1: Integer;
begin
  Result:= B1;
end;

end.
'@
Write-Ascii (Join-Path $src 'uCycB.pas') @'
unit uCycB;

interface

uses
  uCycA;

/// <summary>Fixture routine.</summary>
function B1: Integer;

implementation

function B1: Integer;
begin
  Result:= 1;
end;

end.
'@

$fileA  = Join-Path $src 'uCycA.pas'
$libDb  = Join-Path $WorkDir 'library-Fixture.sqlite'
$projDb = Join-Path $WorkDir 'Fixture.sqlite'
foreach ($d in $libDb, $projDb) {
  $idx = & $exePath index $src --db $d 2>&1 | Out-String
  Check "SANITY: fixture indexed into $(Split-Path $d -Leaf)" ($LASTEXITCODE -eq 0) $idx
}

function LintDbg($db) {
  $env:DRAGLINT_DEBUG = '1'
  try { & $exePath lint $fileA --db $db --rules-dir $rules 2>&1 | Out-String }
  finally { Remove-Item Env:\DRAGLINT_DEBUG }
}

$lib  = LintDbg $libDb
$proj = LintDbg $projDb

Check 'SANITY: the library-named store still serves the per-file checkers (store=True, fid>0)' `
      ($lib -match 'store=True' -and $lib -notmatch 'fid=0\b') `
      (($lib -split "`n" | Where-Object { $_ -match '\[flowdb\]' }) -join ' ')
Check 'A1  library-named store: the project-rules phase does not run' `
      ($lib -notmatch '\[lint-checker\] project-rules') ''
Check 'A1b library-named store: no circular-uses finding for a library unit' `
      ($lib -notmatch '\] circular-uses:') (($lib -split "`n" | Where-Object { $_ -match '\] circular-uses:' }) -join ' | ')
Check 'A2  CONTROL: a project-named store runs the phase' `
      ($proj -match '\[lint-checker\] project-rules') ''
Check 'A2b CONTROL: a project-named store reports circular-uses' `
      ($proj -match '\] circular-uses:') ''

if ($LibraryDb -ne '' -and $LibraryUnit -ne '') {
  if (-not (Split-Path $LibraryDb -Leaf).StartsWith('library-', [StringComparison]::OrdinalIgnoreCase)) {
    Check 'A3  -LibraryDb must be named library-*.sqlite (a COPY of the platform library)' $false $LibraryDb
  } else {
    $out = Join-Path $WorkDir 'a3.out'; $err = Join-Path $WorkDir 'a3.err'
    $p = Start-Process -FilePath $exePath -PassThru -NoNewWindow -WorkingDirectory $WorkDir `
           -RedirectStandardOutput $out -RedirectStandardError $err `
           -ArgumentList @('lint', ('"' + $LibraryUnit + '"'), '--db', ('"' + $LibraryDb + '"'), '--json', '--rules-dir', ('"' + $rules + '"'))
    $done = $p.WaitForExit(($CpuBudgetSec * 10) * 1000)
    $p.Refresh(); $cpu = $p.TotalProcessorTime.TotalSeconds
    if (-not $done) { $p.Kill() }
    Check ("A3  real library unit finishes within {0} CPU-s (cpu={1:N1}, exit={2})" -f $CpuBudgetSec, $cpu, $(if ($done) { $p.ExitCode } else { 'KILLED' })) `
          ($done -and $cpu -lt $CpuBudgetSec) ''
  }
} else {
  Write-Host '[INFO] A3 not run (pass -LibraryDb <copy of library-*.sqlite> -LibraryUnit <file in it>)'
}

Write-Host ''
if ($fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0 }
}
finally {
  Pop-Location -ErrorAction SilentlyContinue
}
