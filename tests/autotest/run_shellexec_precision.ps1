<#
  run_shellexec_precision.ps1 -- `unsafe-shellexecute` must separate a benign
  Explorer open from actual command injection.

  WHY THIS EXISTS
  ---------------
  The rule fired `error` on real user code:

      ShellExecute(Handle, 'open', PChar(FConfigService.DataFolder), nil, nil, SW_SHOWNORMAL);

  which opens a config-derived folder in Explorer. It was flagged because lpFile
  is not a string literal -- but with lpParameters nil and lpOperation the
  literal 'open' there is no command line at all, so CWE-78 cannot occur. An
  `error` on a pervasive benign idiom is worse than no rule: it teaches people
  to ignore the rule, and the owner's standard is that a large finding count IS
  the defect, to be fixed in the rule rather than suppressed per site.

  THE PAIRING IS THE WHOLE POINT
  ------------------------------
  Every SAFE_ case and every UNSAFE_ case lives in ONE fixture file and is
  asserted in ONE run. A change that silenced the false positives by weakening
  the rule into uselessness would turn the SAFE_ assertions green -- and only
  the UNSAFE_ assertions, checked at the same time, say whether the rule still
  does its job. Neither half means anything alone.

  IT ALSO PINS A FALSE NEGATIVE THE FIXTURE FOUND
  -----------------------------------------------
  While building this, the probe showed the rule NEVER flagged

      ShellExecute(0, 'open', 'cmd.exe', PChar(pArgs), nil, SW_SHOWNORMAL);

  -- command injection in its purest form -- because the rule only ever
  inspected lpFile, and 'cmd.exe' is a literal. The one call that most deserved
  an error got none. Check 3 exists so narrowing the rule cannot quietly trade
  a false positive for a false negative.

  Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_shellexec_precision.ps1
#>
[CmdletBinding()]
param(
  [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== unsafe-shellexecute: precision ==' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe     = (Resolve-Path $Exe).Path
$Fixture = (Resolve-Path "$PSScriptRoot\fixtures\shellexec\uShellExec.pas").Path

$errFile = Join-Path ([IO.Path]::GetTempPath()) ("draglint-shellexec-" + [Guid]::NewGuid().ToString('N') + ".txt")
$out = & $Exe lint $Fixture --rule unsafe-shellexecute 2>$errFile
$rc  = $LASTEXITCODE
$text = ($out -join "`n")
Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue

# The lint prints "<file>(<line>): [severity] <rule>: <message>" or
# "<file>:<line>:<col>  [severity] <rule>: <message>" depending on formatter;
# match the line number either way.
function FlaggedLineOf([string]$RoutineName) {
  $src = Get-Content -LiteralPath $Fixture
  $idx = [Array]::FindIndex([string[]]$src, [Predicate[string]]{
    param($l) $l -match ('^procedure TShellExecProbe\.' + $RoutineName + '\b') })
  if ($idx -lt 0) { return -1 }
  # the call is the line after 'begin', i.e. two lines below the header
  for ($i = $idx; $i -lt [Math]::Min($idx + 6, $src.Count); $i++) {
    if ($src[$i] -match '(ShellExecute|WinExec)\s*\(') { return $i + 1 }
  }
  return -1
}

function SeverityAt([int]$Line) {
  if ($Line -lt 1) { return '' }
  foreach ($l in ($text -split "`n")) {
    if ($l -match ("[\(:]" + $Line + "[\):]") -and $l -match '\[(error|warning|info)\]') { return $Matches[1] }
  }
  return ''
}
function IsFlagged([int]$Line) { return (SeverityAt $Line) -ne '' }

Write-Host ''
Write-Host "-- lint output ($rc finding pass) --" -ForegroundColor DarkGray
$text -split "`n" | Where-Object { $_ -match 'unsafe-shellexecute|finding' } | ForEach-Object { "     $_" }

# ---------------------------------------------------------------------------
# CHECK 1 -- the benign idiom is SILENT
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 1: an Explorer open with no parameters is not injection' -ForegroundColor Cyan

# NOT silence -- `warning`. run_shellexec_fixed_scheme.ps1 already ruled, with a
# fixture, that anything which can still CHOOSE THE PROGRAM must fire, and a bare
# runtime lpFile is exactly that; there is no AST difference between a config
# folder and an attacker's path. What was wrong was the SEVERITY and the CWE:
# with nil parameters this is not command injection. So it stays a finding, and
# says what is true of it.
foreach ($safe in 'SafeOpenFolder', 'SafeOpenFolderExplore', 'SafeOpenWithLiteralParams') {
  $ln = FlaggedLineOf $safe
  Check "$safe is a WARNING, not a CWE-78 error" ((SeverityAt $ln) -eq 'warning') `
    "line $ln -> '$(SeverityAt $ln)'"
}
# PER LINE, not across the whole output. The first version of this searched
# the entire text for a CWE-73 message followed by a CWE-78 one -- which is
# always true here, because the warnings and the errors are printed together.
# It asserted nothing and failed anyway.
$dgLine = ''
foreach ($l in ($text -split "`n")) {
  if ($l -match ('[\(:]' + (FlaggedLineOf 'SafeOpenFolder') + '[\):]')) { $dgLine = $l }
}
Check 'the downgraded message cites CWE-73, not CWE-78' `
  (($dgLine -match 'CWE-73') -and ($dgLine -notmatch 'CWE-78')) $dgLine

# ---------------------------------------------------------------------------
# CHECK 2 -- POSITIVE CONTROL: the rule still fires on real injection
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 2: the dangerous shapes still error' -ForegroundColor Cyan

foreach ($bad in 'UnsafeRuntimeParameters', 'UnsafeRunAsVerb', 'UnsafeVariableVerb', 'UnsafeWinExecConcat') {
  $ln = FlaggedLineOf $bad
  Check "$bad is an ERROR" ((SeverityAt $ln) -eq 'error') "line $ln -> '$(SeverityAt $ln)'"
}

# ---------------------------------------------------------------------------
# CHECK 3 -- the false negative the fixture exposed
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 3: an interpreter with runtime args (was NEVER flagged)' -ForegroundColor Cyan

$ln = FlaggedLineOf 'UnsafeInterpreter'
Check 'UnsafeInterpreter is an ERROR' ((SeverityAt $ln) -eq 'error') `
  "line $ln -- literal lpFile meant the old rule could not see this at all"
Check 'and it says WHY, not the generic non-literal message' `
  ($text -match 'command interpreter with runtime-built parameters') $text

# ---------------------------------------------------------------------------
# CHECK 4 -- the totals, so a silent drift in either direction shows up
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- check 4: exact finding count' -ForegroundColor Cyan

$n    = ([regex]::Matches($text, 'unsafe-shellexecute')).Count
$nErr = ([regex]::Matches($text, '\[error\] unsafe-shellexecute')).Count
$nWarn= ([regex]::Matches($text, '\[warning\] unsafe-shellexecute')).Count
Check 'every call site is accounted for: 8 findings' ($n -eq 8) "got $n"
Check '5 are errors (real injection)'   ($nErr  -eq 5) "got $nErr"
Check '3 are warnings (path, not args)' ($nWarn -eq 3) "got $nWarn"

Write-Host ''
if ($script:Failed) { Write-Host 'SHELLEXEC PRECISION: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'SHELLEXEC PRECISION: PASS' -ForegroundColor Green
exit 0
