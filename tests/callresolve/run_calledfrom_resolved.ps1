<#
  run_calledfrom_resolved.ps1 -- THE D5 REGRESSION LOCK (Task 7 bug fix).

  AutoDocument's Called-from used to be name-based: `document --qname TAlpha.Run`
  listed EVERY caller of ANY method named Run. D5 built call_edges (per-site
  resolved targets); this test locks that Called-from is now RESOLVED.

  Fixture calledfrom.pas: TAlpha.Run + TBeta.Run share the name 'Run'.
    CallsAlpha   -> FAlpha.Run  (FAlpha: TAlpha) resolves CERTAIN to TAlpha.Run
    CallsBeta    -> FBeta.Run   (FBeta: TBeta)   resolves CERTAIN to TBeta.Run
    CallsUnknown -> U.Run       (U: undeclared type) -> NO call_edge -> '?' bucket

  After `document --qname calledfrom.TAlpha.Run --apply`, the Called-from line:
    - INCLUDES CallsAlpha, PLAIN (no '?')            -- real resolved caller
    - EXCLUDES CallsBeta                             -- THE BUG FIX (it calls TBeta.Run)
    - lists CallsUnknown WITH a trailing ' ?'        -- honest: name-match, untypable

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\calledfrom.pas')).Path

# Fresh scratch dir; keep the unit name so unit-name-matches-file stays quiet.
$scratch = Join-Path C:\TEMP 'draglint_calledfrom'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'calledfrom.pas'
$db      = Join-Path $scratch 'cf.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  & $exePath document --qname calledfrom.TAlpha.Run --db $db --apply 2>$null | Out-Null
  Check 'apply: .bak written' (Test-Path "$target.bak")

  $txt = [IO.File]::ReadAllText($target)
  # The single 'Called from:' fact line.
  $line = ($txt -split "`r?`n" | Where-Object { $_ -match 'Called from:' } | Select-Object -First 1)
  Check 'Called from: line present' ($null -ne $line -and $line -ne '')

  # --- CallsAlpha: present, and PLAIN (its own entry has NO trailing ' ?'). We
  # match the entry text up to the closing paren and assert no ' ?' immediately
  # follows it.
  Check 'INCLUDES CallsAlpha (resolved certain to TAlpha.Run)' `
    ($line -match 'calledfrom\.TDispatcher\.CallsAlpha \(calledfrom\.pas\)')
  Check 'CallsAlpha is PLAIN (no trailing ?)' `
    ($line -match 'calledfrom\.TDispatcher\.CallsAlpha \(calledfrom\.pas\)(?! \?)')

  # --- CallsBeta: THE BUG FIX. It resolved certain to TBeta.Run, so it is NOT a
  # caller of TAlpha.Run -> must be entirely absent from this line.
  Check 'EXCLUDES CallsBeta (resolved certain to TBeta.Run -- the bug fix)' `
    (-not ($line -match 'CallsBeta'))

  # --- CallsUnknown: name-match with no call_edge (receiver untypable) -> listed
  # WITH a trailing ' ?'.
  Check 'INCLUDES CallsUnknown WITH trailing ? (untypable receiver)' `
    ($line -match 'calledfrom\.TDispatcher\.CallsUnknown \(calledfrom\.pas\) \?')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
