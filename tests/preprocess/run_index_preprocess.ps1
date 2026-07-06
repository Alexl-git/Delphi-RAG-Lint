<#
  run_index_preprocess.ps1 -- PP-Task-9: the preprocess stage is now WIRED into
  the real index pipeline (behind the --no-preprocess flag). Unlike Task 8's
  gate (which pre-resolved bytes with `preprocess-file`, wrote them to disk, then
  indexed the resolved file), this test indexes the RAW on-disk fixture and lets
  the INDEXER run Preprocess internally per-config before parsing.

  Fixture fixtures\platform_heavy.pas has platform-branching blocks:
    - {$IFDEF MSWINDOWS} WinOnlyProc {$ENDIF}   -- active under Win64 profile
    - {$IFDEF POSIX} PosixOnlyProc ... {$ENDIF} -- INACTIVE under Win64 profile
    - {$IFDEF WIN64}...{$ELSE}...{$ENDIF}       -- WIN64 branch active

  Two index runs to two SEPARATE scratch DBs:
    (a) DEFAULT   -- preprocess ON, Win64 built-in profile (no --project given,
                     so the fallback profile is PlatformBuiltins('Win64')).
                     Per-config: the MSWINDOWS/WIN64 branch survives; the POSIX
                     branch is blanked, so PosixOnlyProc is NOT indexed.
    (b) NO-PREPROC -- `--no-preprocess`: the OLD all-branch behaviour. The raw
                     file is parsed as-is, so BOTH WinOnlyProc and PosixOnlyProc
                     are indexed (POSIX is not resolved away).

  STRICT presence check (a Task-8-review note: `query --name` falls back to
  FUZZY matching when the exact name misses, so a bare exit code could flip on a
  coincidental fuzzy hit). We query `--name <Name> --json` (FindSymbolsByExactName
  runs first; the fuzzy fallback fires ONLY when the exact match returns ZERO)
  and COUNT the JSON entries whose "name" field EXACTLY equals the target. This
  is fuzzy-proof: a fuzzy fallback for an ABSENT symbol returns DIFFERENT names,
  none of which equal the target, so the exact count stays 0. Absent == zero
  exact-name matches; present == at least one. We do NOT rely on exit code, and
  we do NOT match on qualified_name -- preprocessing improves the parse enough
  that the unit prefix appears (raw broken parse: "WinOnlyProc"; clean
  preprocessed parse: "platform_heavy.WinOnlyProc"), so only the bare "name"
  field is stable across both index modes.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\platform_heavy.pas')).Path

# Fresh scratch dirs: one for the DEFAULT (preprocess-on) index, one for the
# --no-preprocess index. Each gets its own copy of the raw fixture + its own DB.
$scratchRoot = Join-Path C:\TEMP 'draglint_indexpp'
if (Test-Path $scratchRoot) { Remove-Item $scratchRoot -Recurse -Force }
$ppDir  = Join-Path $scratchRoot 'pp'
$rawDir = Join-Path $scratchRoot 'raw'
New-Item -ItemType Directory -Path $ppDir  | Out-Null
New-Item -ItemType Directory -Path $rawDir | Out-Null
Copy-Item $fixture (Join-Path $ppDir  'platform_heavy.pas') -Force
Copy-Item $fixture (Join-Path $rawDir 'platform_heavy.pas') -Force
$ppDb  = Join-Path $scratchRoot 'pp.sqlite'
$rawDb = Join-Path $scratchRoot 'raw.sqlite'

# Count JSON entries whose "name" EXACTLY equals $name in the output of
# `query --name <name> --json`. FindSymbolsByExactName runs first; the fuzzy
# fallback only fires when the exact match returns zero, and it returns entries
# with DIFFERENT names -- none of which equal $name -- so counting exact-name
# matches is fuzzy-proof. Returns an integer; 0 means genuinely absent.
function Get-ExactCount([string]$db, [string]$name) {
  $out = & $exePath query --name $name --db $db --json 2>$null
  $joined = ($out -join "`n").Trim()
  if ($joined -eq '' -or $joined -eq '[]') { return 0 }
  try { $arr = $joined | ConvertFrom-Json } catch { return 0 }
  if ($null -eq $arr) { return 0 }
  # ConvertFrom-Json returns a single object (not an array) for a 1-element list.
  $items = @($arr)
  return @($items | Where-Object { $_.name -eq $name }).Count
}

Push-Location C:\TEMP
try {
  # ============================================================
  # (a) DEFAULT: preprocess ON, Win64 built-in profile. Per-config narrowing.
  # ============================================================
  & $exePath index $ppDir --db $ppDb 2>&1 | Out-Null
  Check 'DEFAULT: index run exited 0 (preprocess wired into the pipeline)' ($LASTEXITCODE -eq 0)

  $ppWin   = Get-ExactCount $ppDb 'WinOnlyProc'
  $ppPosix = Get-ExactCount $ppDb 'PosixOnlyProc'
  Write-Host ("  DEFAULT: WinOnlyProc exact matches = {0}, PosixOnlyProc exact matches = {1}" -f $ppWin, $ppPosix)
  Check 'DEFAULT (per-config): WinOnlyProc IS present (active MSWINDOWS/WIN64 branch survives)' ($ppWin -ge 1)
  Check 'DEFAULT (per-config): PosixOnlyProc is ABSENT (inactive POSIX branch blanked, not indexed)' ($ppPosix -eq 0)

  # ============================================================
  # (b) NO-PREPROC: --no-preprocess reverts to the OLD all-branch behaviour.
  # ============================================================
  & $exePath index $rawDir --db $rawDb --no-preprocess 2>&1 | Out-Null
  Check 'NO-PREPROC: index run exited 0' ($LASTEXITCODE -eq 0)

  $rawWin   = Get-ExactCount $rawDb 'WinOnlyProc'
  $rawPosix = Get-ExactCount $rawDb 'PosixOnlyProc'
  Write-Host ("  NO-PREPROC: WinOnlyProc exact matches = {0}, PosixOnlyProc exact matches = {1}" -f $rawWin, $rawPosix)
  Check 'NO-PREPROC (all-branch): WinOnlyProc IS present' ($rawWin -ge 1)
  Check 'NO-PREPROC (all-branch): PosixOnlyProc IS present (raw parse indexes both branches -- old behaviour)' ($rawPosix -ge 1)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
