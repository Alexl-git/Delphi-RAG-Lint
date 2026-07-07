<#
  run_enum_helper_separate_units.ps1 -- enum-helper-separate-units lint rule (Task 7).

  Consumes ISymbolStore.FindHelpersOfType (Task 1's whole-DB helper edge) via
  TProjectLintRules.Run, so it needs the store-backed project path -- exercised
  through BOTH `lint-all --db --json` and `lint-project --db --json`.

  Fixtures (reused from tests\refactor\fixtures\enumhelper, proven cross-unit by
  the enum-helper generator's own RESOLVE-stage tests):
    Mode.pas + ModeHelperUnit.pas -- TMode enum in Mode.pas, TModeHelper record
      helper for TMode in ModeHelperUnit.pas (uses Mode) -> DIFFERENT units ->
      rule FIRES, message names BOTH units.
    already_has_helper.pas -- TStatus enum + TStatusHelper in the SAME unit ->
      NO finding (co-located).

  Plus the mandatory ADF/AutoDocument-lesson regression: the rule is ON by
  default in the catalog (`rules --json`) AND fires in a BARE (no-config) run
  through BOTH lint-all and lint-project -- proving it was not accidentally
  added to either function's DefDisabled/inline-disabled array (the exact gap
  that made missing-doc fire when it should not have, ADF Task 13 / e038503).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$enumHelperFixtures = (Resolve-Path (Join-Path $PSScriptRoot '..\..\refactor\fixtures\enumhelper')).Path

$scratch = Join-Path C:\TEMP 'draglint_enumhelper_sepunits'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Get-Findings($rawOut) {
  $raw = ($rawOut -join "`n")
  $arrStart = $raw.IndexOf('[')
  $arrEnd   = $raw.LastIndexOf(']')
  if ($arrStart -ge 0 -and $arrEnd -gt $arrStart) {
    $jsonText = $raw.Substring($arrStart, $arrEnd - $arrStart + 1)
    return @(ConvertFrom-Json $jsonText)
  }
  return @()
}

Push-Location C:\TEMP
try {

  # ===================================================================
  # Case A: cross-unit -- Mode.pas (enum) + ModeHelperUnit.pas (helper),
  # different units -> rule FIRES, message names both units.
  # ===================================================================
  $crossDir = Join-Path $scratch 'cross'
  New-Item -ItemType Directory -Path $crossDir | Out-Null
  Copy-Item (Join-Path $enumHelperFixtures 'Mode.pas') $crossDir
  Copy-Item (Join-Path $enumHelperFixtures 'ModeHelperUnit.pas') $crossDir
  $crossDb = Join-Path $scratch 'cross.sqlite'
  & $exePath index $crossDir --db $crossDb 2>$null | Out-Null

  $crossAllOut = & $exePath lint-all --db $crossDb --json 2>$null
  $crossAllFindings = Get-Findings $crossAllOut
  $crossAllHits = @($crossAllFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  Check 'lint-all: cross-unit fixture FIRES enum-helper-separate-units' ($crossAllHits.Count -ge 1)
  if ($crossAllHits.Count -ge 1) {
    Check 'lint-all: message names the helper unit (ModeHelperUnit)' ($crossAllHits[0].message -match 'ModeHelperUnit')
    Check 'lint-all: message names the enum unit (Mode)' ($crossAllHits[0].message -match '\bMode\b')
    Check 'lint-all: message names the helper type (TModeHelper)' ($crossAllHits[0].message -match 'TModeHelper')
    Check 'lint-all: message names the enum type (TMode)' ($crossAllHits[0].message -match 'TMode')
  }

  $crossProjOut = & $exePath lint-project --db $crossDb --json 2>$null
  $crossProjFindings = Get-Findings $crossProjOut
  $crossProjHits = @($crossProjFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  Check 'lint-project: cross-unit fixture FIRES enum-helper-separate-units' ($crossProjHits.Count -ge 1)

  # ===================================================================
  # Case B: same-unit -- already_has_helper.pas (TStatus + TStatusHelper,
  # one unit) -> NO finding.
  # ===================================================================
  $sameDir = Join-Path $scratch 'same'
  New-Item -ItemType Directory -Path $sameDir | Out-Null
  Copy-Item (Join-Path $enumHelperFixtures 'already_has_helper.pas') $sameDir
  $sameDb = Join-Path $scratch 'same.sqlite'
  & $exePath index $sameDir --db $sameDb 2>$null | Out-Null

  $sameAllOut = & $exePath lint-all --db $sameDb --json 2>$null
  $sameAllFindings = Get-Findings $sameAllOut
  $sameAllHits = @($sameAllFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  Check 'lint-all: same-unit fixture -> NO enum-helper-separate-units finding' ($sameAllHits.Count -eq 0)

  $sameProjOut = & $exePath lint-project --db $sameDb --json 2>$null
  $sameProjFindings = Get-Findings $sameProjOut
  $sameProjHits = @($sameProjFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  Check 'lint-project: same-unit fixture -> NO enum-helper-separate-units finding' ($sameProjHits.Count -eq 0)

  # ===================================================================
  # Case C (Task 9b false-positive regression): two UNRELATED same-named
  # TMode enums indexed together -- Mode.pas + ModeHelperUnit.pas (the
  # genuine cross-unit pair from Case A, TModeHelper resolves its
  # target_symbol_id to Mode.pas's TMode) PLUS ModeUnrelated.pas (a THIRD,
  # unrelated TMode with no helper of its own, not `uses`d by
  # ModeHelperUnit). Before the Task 9b fix, FindHelpersOfType('TMode') was
  # name-only, so the rule paired TModeHelper's edge with BOTH TMode enums --
  # a spurious finding on ModeUnrelated.pas's TMode. After the fix (symbol-id
  # identity match), the rule must fire ONLY for Mode.pas's TMode (the
  # genuine target) and produce NOTHING for ModeUnrelated.pas.
  # ===================================================================
  $fpDir = Join-Path $scratch 'fp'
  New-Item -ItemType Directory -Path $fpDir | Out-Null
  Copy-Item (Join-Path $enumHelperFixtures 'Mode.pas') $fpDir
  Copy-Item (Join-Path $enumHelperFixtures 'ModeHelperUnit.pas') $fpDir
  Copy-Item (Join-Path $enumHelperFixtures 'ModeUnrelated.pas') $fpDir
  $fpDb = Join-Path $scratch 'fp.sqlite'
  & $exePath index $fpDir --db $fpDb 2>$null | Out-Null

  $fpAllOut = & $exePath lint-all --db $fpDb --json 2>$null
  $fpAllFindings = Get-Findings $fpAllOut
  $fpAllHits = @($fpAllFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  $fpGenuineHits   = @($fpAllHits | Where-Object { $_.message -match 'ModeUnrelated' })
  Check 'lint-all: genuine TMode/TModeHelper pair still FIRES (identity match preserved)' (@($fpAllHits | Where-Object { $_.message -match '\bMode\.pas\b|\bMode\b' -and $_.message -match 'ModeHelperUnit' }).Count -ge 1)
  Check 'lint-all: unrelated ModeUnrelated.pas TMode produces NO finding (symbol-id match kills the FP)' ($fpGenuineHits.Count -eq 0)
  Check 'lint-all: exactly 1 finding total (genuine pair only, no FP duplicate)' ($fpAllHits.Count -eq 1)

  $fpProjOut = & $exePath lint-project --db $fpDb --json 2>$null
  $fpProjFindings = Get-Findings $fpProjOut
  $fpProjHits = @($fpProjFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  $fpProjGenuineHits = @($fpProjHits | Where-Object { $_.message -match 'ModeUnrelated' })
  Check 'lint-project: unrelated ModeUnrelated.pas TMode produces NO finding' ($fpProjGenuineHits.Count -eq 0)
  Check 'lint-project: exactly 1 finding total (genuine pair only, no FP duplicate)' ($fpProjHits.Count -eq 1)

  # ===================================================================
  # Catalog: rule is ON by default (rules --json).
  # ===================================================================
  $rulesOut = & $exePath rules --json 2>$null
  $rulesRaw = ($rulesOut -join "`n")
  $rulesJson = $rulesRaw | ConvertFrom-Json
  $ruleEntry = $rulesJson.rules | Where-Object { $_.id -eq 'enum-helper-separate-units' }
  Check 'catalog: enum-helper-separate-units is registered' ($null -ne $ruleEntry)
  if ($null -ne $ruleEntry) {
    Check 'catalog: enum-helper-separate-units is ON by default (default_enabled=true)' ($ruleEntry.default_enabled -eq $true)
  }

  # ===================================================================
  # Regression (mirrors the missing-doc / ADF Task 13 fix, e038503):
  # the ON-by-default state must be honored at RUNTIME in BOTH lint-all
  # AND lint-project on a BARE run (no --config, no --disable) -- proving
  # enum-helper-separate-units was NOT accidentally added to either
  # function's DefDisabled/inline-disabled array. Reuses the cross-unit db.
  # ===================================================================
  $bareAllOut = & $exePath lint-all --db $crossDb --json 2>$null
  $bareAllFindings = Get-Findings $bareAllOut
  $bareAllHits = @($bareAllFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  Check 'BARE lint-all (no config/disable) FIRES enum-helper-separate-units (ON by default at runtime)' ($bareAllHits.Count -ge 1)

  $bareProjOut = & $exePath lint-project --db $crossDb --json 2>$null
  $bareProjFindings = Get-Findings $bareProjOut
  $bareProjHits = @($bareProjFindings | Where-Object { $_.rule -eq 'enum-helper-separate-units' })
  Check 'BARE lint-project (no config/disable/--rule) FIRES enum-helper-separate-units (ON by default at runtime)' ($bareProjHits.Count -ge 1)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
