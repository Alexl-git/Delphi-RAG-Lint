<#
  run_unused_unit_helpers.ps1 -- unused-unit-in-uses must count TYPE HELPER
  members as references, and must set its severity PER FINDING.

  THE DEFECT THIS PINS (T4 / U1, blind spot 1):
    The rule's export surface was the unit's interface-section children BY NAME.
    That is right for ordinary types -- a method name is not addressable without
    its receiver's type, and folding members in would keep alive any unit that
    exports something called `Add`. A HELPER member is the exception:

        TPath.GetFileName(X).ToUpper.Contains(Y)

    names nothing from System.SysUtils, yet ToUpper and Contains are
    TStringHelper members declared there, and removing the import fails E2671.

    DataCopy measured the cost rather than guessing it: of 66 findings they
    commented out and compiled 23 -- 20 were genuinely safe, 1 broke the COMPILE,
    2 built clean and broke at RUNTIME. Wrong ~13% of the time in the direction
    of breaking the product is what got the rule downgraded to `info`.

    type_helpers has carried the answer since c09715c (schema v15). The rule was
    simply not reading it.

  THE SEVERITY SPLIT:
    With both named blind spots closed (DFM shipped earlier, helpers here), what
    remains is a unit whose only contribution is its `initialization` section --
    which no index can settle, and which the compiler cannot catch either.
    Measured on library-Win64: 1,899 of 5,671 units have an initialization
    section, so a blanket severity is wrong in either direction. No init ->
    warning; has init -> info, with a message that says why.

  THE CONTROLS, and what each rules out:
    * a unit imported and genuinely unused IS still flagged -- the helper read
      must not have silenced the rule wholesale;
    * BOTH severities appear in ONE run -- "always info" and "always warning"
      each satisfy half the assertion, so neither alone is checked;
    * the project-local helper AND the library helper (System.SysUtils) are both
      exercised, since they take different halves of ExportNamesFor's two-store
      fallback;
    * the fixture's own premise -- that the helper rows exist in the index -- is
      asserted before anything leans on it.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-unusedunit-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== unused-unit-in-uses: type-helper members + the severity split ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$srcDir = (Resolve-Path "$PSScriptRoot\fixtures\unusedunit").Path

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$fixDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force -Path $fixDir | Out-Null
Copy-Item (Join-Path $srcDir '*.pas') $fixDir
$db      = Join-Path $WorkDir 'unusedunit.sqlite'
$errFile = Join-Path $WorkDir 'stderr.txt'

& $Exe index $fixDir --db $db 2>$errFile | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host "FATAL: indexing the fixture failed ($LASTEXITCODE)" -ForegroundColor Red
  Write-Host (Get-Content -LiteralPath $errFile -Raw)
  exit 1
}

# ---------------------------------------------------------------------------
# Premise first. Every assertion below assumes the extractor recorded the
# project-local helper; if it did not, a silent uUuHelperConsumer would prove
# nothing about the fix.
Write-Host ''
Write-Host '-- fixture premise' -ForegroundColor Cyan
$helperRows = (& $Exe sql --db $db --query "select count(*) as n from type_helpers" 2>$errFile | Out-String)
Check 'the fixture index recorded a type_helpers row' ($helperRows -match '\b1\b') `
  (($helperRows -split "`r?`n" | Where-Object { $_ -match '\S' }) -join ' / ')

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the false positive: helper-only references' -ForegroundColor Cyan
$out = (& $Exe lint-project --db $db --rule unused-unit-in-uses 2>$errFile | Out-String) -replace "`r`n", "`n"
Write-Host ("  findings:`n    " + (($out -split "`n" | Where-Object { $_ -match 'unused-unit-in-uses' }) -join "`n    ")) -ForegroundColor DarkGray

# The project-local half: ZzShout is a member of a helper declared in
# uUuHelpProvider, and nothing else from that unit is named.
Check 'a project-local helper member counts as a use of its unit' `
  ($out -notmatch "Unit 'uUuHelpProvider'") `
  ("looked for a finding naming uUuHelpProvider" )

# The library half: ToUpper is TStringHelper, declared in System.SysUtils, which
# lives in the platform library index -- a different branch of ExportNamesFor's
# two-store fallback.
Check 'a LIBRARY helper member (System.SysUtils.TStringHelper.ToUpper) counts too' `
  ($out -notmatch "Unit 'System\.SysUtils'") ''

# CONTROL -- the rule must still fire. Silencing it wholesale would satisfy both
# checks above.
Check 'CONTROL: a genuinely unused import IS still flagged' `
  ($out -match "Unit 'uUuNoInit'") ''
Check 'CONTROL: and so is the second one' ($out -match "Unit 'uUuWithInit'") ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- the severity split, both values in ONE run' -ForegroundColor Cyan
$warnLine = @($out -split "`n" | Where-Object { $_ -match 'uUuNoInit'   -and $_ -match 'unused-unit-in-uses' }) | Select-Object -First 1
$infoLine = @($out -split "`n" | Where-Object { $_ -match 'uUuWithInit' -and $_ -match 'unused-unit-in-uses' }) | Select-Object -First 1
Check 'no initialization section -> warning' `
  ($null -ne $warnLine -and $warnLine -match '\[warning\]') ("matched: " + $warnLine)
Check 'HAS an initialization section -> info' `
  ($null -ne $infoLine -and $infoLine -match '\[info\]') ("matched: " + $infoLine)
Check 'CONTROL: the two differ -- neither "always info" nor "always warning" passes' `
  ($null -ne $warnLine -and $null -ne $infoLine -and $warnLine -match '\[warning\]' -and $infoLine -match '\[info\]') ''
Check 'the info finding SAYS why it is only info' `
  ($null -ne $infoLine -and $infoLine -match 'initialization section') ''
Check 'the warning finding does NOT repeat the old helper confession' `
  ($null -ne $warnLine -and $warnLine -notmatch 'invisible to this check') ''

# ---------------------------------------------------------------------------
# The catalogue advertises the ceiling of a per-finding severity. If it drifts
# back to info, `drag-lint rules` understates what the rule can emit.
Write-Host ''
Write-Host '-- DOCS-IN-SYNC: the catalogue advertises the higher severity' -ForegroundColor Cyan
$cat = (& $Exe rules --json 2>$null | Out-String) | ConvertFrom-Json
$rows = if ($cat.rules) { $cat.rules } else { $cat }
$row  = @($rows | Where-Object { $_.id -eq 'unused-unit-in-uses' }) | Select-Object -First 1
Check 'the rule is in the catalogue (scan is not vacuous)' ($null -ne $row) ''
if ($null -ne $row) {
  Check 'its default severity is warning, the higher of the two it emits' `
    ($row.default_severity -eq 'warning') "default_severity=$($row.default_severity)"
}

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
