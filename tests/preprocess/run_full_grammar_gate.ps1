<#
  run_full_grammar_gate.ps1 -- Task 8: the empirical de-risk GATE.

  Question the spec asks: does the CURRENT full grammar parse PREPROCESSED
  input at least as well as RAW input? Preprocessing should remove the
  cross-branch {$IFDEF} noise (both a live branch AND a dead branch's stray
  tokens) that can trip a parser reading the raw file.

  Fixture fixtures\platform_heavy.pas is a small unit with platform-branching
  blocks:
    - {$IFDEF MSWINDOWS} WinOnlyProc {$ENDIF}      -- should SURVIVE (active)
    - {$IFDEF POSIX} PosixOnlyProc ... begin        -- should be BLANKED
        {$ENDIF}                                     (inactive; the dangling
                                                       'begin' with no matching
                                                       'end' is deliberately
                                                       left broken so the RAW
                                                       file trips the parser --
                                                       this is exactly the
                                                       failure class preprocessing
                                                       is supposed to fix)
    - {$IFDEF WIN64}...{$ELSE}...{$ENDIF}           -- WIN64 branch active

  Design: index the fixture TWO ways to two SEPARATE scratch DBs:
    (a) RAW         -- current path, no preprocessing, straight index.
    (b) PREPROCESSED -- run preprocess-file --include-mode defines-only
                        --define win64 --define mswindows (WIN64 + MSWINDOWS
                        active, POSIX inactive), write the resolved bytes to
                        a temp platform_heavy.pas in its own scratch dir, then
                        index THAT dir.

  Assertions (the whole gate):
    1. (errors)      preprocessed parse-error count for the file <= raw's.
    2. (per-config, inactive branch absent) query --name PosixOnlyProc against
       the PREPROCESSED db returns NO hit (exit code 1 / 0 matches) -- proves
       the POSIX branch was blanked, not indexed.
    3. (per-config, active branch present) query --name WinOnlyProc against the
       PREPROCESSED db returns a HIT (exit code 0 / >=1 match) -- proves the
       MSWINDOWS branch survived.

  Error counts are read from the indexer's own per-file progress line, e.g.:
    "  raw\platform_heavy.pas -> 5 symbols, 5 refs, 1 errors"
  (TIndexer.ReportProgress, src/core/DRagLint.Core.Indexer.pas). We run
  `index` WITHOUT suppressing stdout so that line is capturable, then parse
  out the trailing "<N> errors" token with a regex.

  IF THE GATE FAILS (preprocessed errors > raw errors, OR per-config assertion
  2 or 3 fails): this script exits 1 and prints FAIL lines. Per the plan, a
  failure here is NOT something to patch around -- it means the pure grammar
  DLL becomes a prerequisite (a plan-level decision), so a failing run must be
  reported honestly, not "fixed" by loosening the checks.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\platform_heavy.pas')).Path

# Fresh scratch dirs: one for the RAW index, one for the PREPROCESSED index.
$scratchRoot = Join-Path C:\TEMP 'draglint_fullgrammargate'
if (Test-Path $scratchRoot) { Remove-Item $scratchRoot -Recurse -Force }
$rawDir = Join-Path $scratchRoot 'raw'
$ppDir  = Join-Path $scratchRoot 'pp'
New-Item -ItemType Directory -Path $rawDir | Out-Null
New-Item -ItemType Directory -Path $ppDir  | Out-Null

$rawTarget = Join-Path $rawDir 'platform_heavy.pas'
$ppTarget  = Join-Path $ppDir  'platform_heavy.pas'
$rawDb     = Join-Path $scratchRoot 'raw.sqlite'
$ppDb      = Join-Path $scratchRoot 'pp.sqlite'

Copy-Item $fixture $rawTarget -Force

# Extract the trailing "<N> errors" count from an indexer progress line for
# a given file-name (matches on the basename so raw\ vs pp\ dir prefixes in
# the printed path don't matter).
function Get-ErrorCount([string[]]$indexOutput, [string]$fileBaseName) {
  $line = $indexOutput | Where-Object { $_ -match [regex]::Escape($fileBaseName) -and $_ -match '->\s*\d+\s*symbols' } | Select-Object -First 1
  if ($null -eq $line) { return $null }
  if ($line -match '(\d+)\s*errors\s*$') { return [int]$Matches[1] }
  return $null
}

Push-Location C:\TEMP
try {
  # ============================================================
  # (a) RAW: index the fixture as-is (current path, no preprocessing).
  # ============================================================
  $rawOut = & $exePath index $rawDir --db $rawDb
  $rawErrors = Get-ErrorCount $rawOut 'platform_heavy.pas'
  Check 'RAW: index run produced a parseable progress line with an error count' ($null -ne $rawErrors)
  Write-Host ("  RAW errors: {0}" -f $rawErrors)

  # ============================================================
  # (b) PREPROCESSED: run preprocess-file (win64+mswindows active, posix
  # inactive), write resolved bytes to a temp .pas, index THAT dir.
  # ============================================================
  $ppBytes = & $exePath preprocess-file --file $rawTarget --include-mode defines-only --define win64 --define mswindows
  # Capture RAW stdout bytes (no text-pipeline mangling) via cmd.exe redirection,
  # matching the byte-exact-capture convention used by run_include_modes.ps1.
  function Q([string]$s) { return '"' + $s + '"' }
  $line = ((Q $exePath) + ' preprocess-file --file ' + (Q $rawTarget) + ' --include-mode defines-only --define win64 --define mswindows > ' + (Q $ppTarget))
  $p = Start-Process cmd.exe -ArgumentList '/c', ('"' + $line + '"') -NoNewWindow -Wait -PassThru
  Check 'preprocess-file: exited 0' ($p.ExitCode -eq 0)

  $rawBytes = [System.IO.File]::ReadAllBytes($rawTarget)
  $ppBytesOnDisk = [System.IO.File]::ReadAllBytes($ppTarget)
  Check 'offset-identity: preprocessed byte length == raw byte length' ($ppBytesOnDisk.Length -eq $rawBytes.Length)

  $ppOut = & $exePath index $ppDir --db $ppDb
  $ppErrors = Get-ErrorCount $ppOut 'platform_heavy.pas'
  Check 'PREPROCESSED: index run produced a parseable progress line with an error count' ($null -ne $ppErrors)
  Write-Host ("  PREPROCESSED errors: {0}" -f $ppErrors)

  # ============================================================
  # THE GATE -- assertion 1: preprocessed must parse at least as well as raw.
  # ============================================================
  if (($null -ne $rawErrors) -and ($null -ne $ppErrors)) {
    Check ("GATE: preprocessed errors ({0}) <= raw errors ({1})" -f $ppErrors, $rawErrors) ($ppErrors -le $rawErrors)
  } else {
    Check 'GATE: preprocessed errors <= raw errors' $false
  }

  # ============================================================
  # per-config assertion 2: inactive POSIX branch is ABSENT from the
  # preprocessed index (blanked, not indexed).
  # ============================================================
  & $exePath query --name PosixOnlyProc --db $ppDb *> $null
  $posixExit = $LASTEXITCODE
  Check 'PER-CONFIG: PosixOnlyProc is ABSENT from the preprocessed index (inactive branch blanked)' ($posixExit -ne 0)

  # ============================================================
  # per-config assertion 3: active MSWINDOWS branch IS present in the
  # preprocessed index.
  # ============================================================
  & $exePath query --name WinOnlyProc --db $ppDb *> $null
  $winExit = $LASTEXITCODE
  Check 'PER-CONFIG: WinOnlyProc IS present in the preprocessed index (active branch survives)' ($winExit -eq 0)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
