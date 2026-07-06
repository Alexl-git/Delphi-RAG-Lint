<#
  run_closure_preprocess.ps1 -- PP-Task-10: the preprocess stage is now wired
  into the CLOSURE / uses scanner (behind the same --no-preprocess flag Task 9
  added). Where Task 9 proved per-config SYMBOL EXTRACTION, this test proves
  per-config FILE DISCOVERY: a unit `uses`d only under an INACTIVE {$IFDEF}
  branch is NOT pulled into the compile closure.

  Fixture fixtures\closure_cond\main.dpr has a conditional uses clause:
    uses
      System.SysUtils
      {$IFDEF POSIX}, PosixOnly{$ENDIF}
      {$IFDEF WIN64}, Win64Only{$ENDIF}
      ;
  plus stub units PosixOnly.pas (procedure PosixMarker) and Win64Only.pas
  (procedure Win64Marker) sitting in the same directory.

  The `selftest closure --project <main.dpr>` verb runs TClosureResolver.Resolve
  and prints, one per line, every project-local file the project would compile.
  That printed set IS the closure output verbatim -- the most direct proof of
  per-config discovery (no round-trip through symbol extraction needed).

  Two runs against the SAME .dpr:
    (a) DEFAULT   -- preprocess ON, Win64 built-in profile (--platform win64, no
                     .dproj, so the fallback profile is PlatformBuiltins('Win64')).
                     Per-config: the WIN64 branch survives -> Win64Only.pas is
                     discovered; the POSIX branch is blanked -> PosixOnly.pas is
                     NOT discovered.
    (b) NO-PREPROC -- `--no-preprocess`: the OLD all-branch behaviour. Both
                     conditional branches are scanned, so BOTH Win64Only.pas AND
                     PosixOnly.pas are discovered (unchanged).

  STRICT presence check (the Task-8/9 lesson: avoid anything that can flip on a
  fuzzy/partial match). The closure prints ABSOLUTE file paths, so we count lines
  whose FILE NAME (leaf) EXACTLY equals the target -- Win64Only.pas / PosixOnly.pas.
  Absent == zero exact-leaf matches; present == at least one. We do NOT rely on
  the exit code alone.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$srcDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\closure_cond')).Path

# Copy the fixture to a fresh scratch dir so the closure scan runs against a
# clean, isolated tree (no sibling files, no drag-lint config interference).
$scratchRoot = Join-Path C:\TEMP 'draglint_closurepp'
if (Test-Path $scratchRoot) { Remove-Item $scratchRoot -Recurse -Force }
New-Item -ItemType Directory -Path $scratchRoot | Out-Null
Copy-Item (Join-Path $srcDir '*') $scratchRoot -Force
$proj = Join-Path $scratchRoot 'main.dpr'

# Count lines in the closure output whose FILE NAME (leaf) EXACTLY equals $leaf.
# The closure prints one absolute path per line (Warnings, if any, are prefixed
# with WARN and won't match a bare leaf). Returns an integer; 0 == not discovered.
function Get-LeafCount([string[]]$lines, [string]$leaf) {
  $n = 0
  foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -eq '') { continue }
    if ([System.IO.Path]::GetFileName($t) -ieq $leaf) { $n++ }
  }
  return $n
}

Push-Location C:\TEMP
try {
  # ============================================================
  # (a) DEFAULT: preprocess ON, Win64 built-in profile. Per-config narrowing.
  # ============================================================
  $ppOut = & $exePath selftest closure --project $proj --platform win64 2>$null
  Check 'DEFAULT: selftest closure exited 0 (preprocess wired into the closure)' ($LASTEXITCODE -eq 0)

  $ppWin   = Get-LeafCount $ppOut 'Win64Only.pas'
  $ppPosix = Get-LeafCount $ppOut 'PosixOnly.pas'
  Write-Host ("  DEFAULT: Win64Only.pas matches = {0}, PosixOnly.pas matches = {1}" -f $ppWin, $ppPosix)
  Check 'DEFAULT (per-config): Win64Only.pas IS discovered (active WIN64 branch survives)' ($ppWin -ge 1)
  Check 'DEFAULT (per-config): PosixOnly.pas is NOT discovered (inactive POSIX branch blanked)' ($ppPosix -eq 0)

  # ============================================================
  # (b) NO-PREPROC: --no-preprocess reverts to the OLD all-branch behaviour.
  # ============================================================
  $rawOut = & $exePath selftest closure --project $proj --platform win64 --no-preprocess 2>$null
  Check 'NO-PREPROC: selftest closure exited 0' ($LASTEXITCODE -eq 0)

  $rawWin   = Get-LeafCount $rawOut 'Win64Only.pas'
  $rawPosix = Get-LeafCount $rawOut 'PosixOnly.pas'
  Write-Host ("  NO-PREPROC: Win64Only.pas matches = {0}, PosixOnly.pas matches = {1}" -f $rawWin, $rawPosix)
  Check 'NO-PREPROC (all-branch): Win64Only.pas IS discovered' ($rawWin -ge 1)
  Check 'NO-PREPROC (all-branch): PosixOnly.pas IS discovered (raw all-branch scan -- old behaviour)' ($rawPosix -ge 1)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
