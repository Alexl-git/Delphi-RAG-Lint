<#
  run_lsp_switch_params_guard.ps1 -- `drag-lint-switch --delphi --on` must be
  able to register the PARAMETERS the IDE launches the server with.

  THE DEFECT THIS PINS, measured 2026-08-29 and confirmed 2026-08-30:
    CreateEntry (drag-lint-switch.dpr:262) takes an AParams argument and writes
    it to the registry value `Parameters` (:273) -- but the argument parser
    accepted no flag that could populate it, and the ONE call site passed a
    LITERAL EMPTY STRING:

        CreateEntry(ExePath, '', 'pascal', 15000)

    So every registration this tool has ever made launches drag-lint.exe with NO
    parameters. For the plain LSP that happened to be survivable; for the merge
    proxy it is not, because the proxy is selected BY a parameter
    (`lsp --proxy ...`). A Task 5 registration made before this fix would have
    handed the IDE a server that never enters proxy mode at all -- and it would
    have looked like the proxy failing, not like the switch failing.

  WHY THIS GUARD EXISTS SEPARATELY FROM THE PROXY WORK: the proxy's own Task 5
  needs a LIVE IDE and a supervised session. This half is fully headless, and
  landing it first is what stops that supervised session being spent
  diagnosing an empty command line.

  IT READS THE REGISTRY DIRECTLY, NOT THE TOOL'S OWN --status OUTPUT. A tool
  reporting what it believes it wrote is not evidence that it wrote it; that is
  the whole shape of the bug above, where CreateEntry looked correct in
  isolation and the caller supplied ''.

  SAFE BY CONSTRUCTION: every operation is scoped to a scratch --reg-root under
  HKCU, which is what that flag exists for. The REAL Embarcadero LSP key is
  never touched, and the guard asserts that its scratch root is not the real one
  before it writes anything.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\tools\lsp-switch\Win64\Debug\drag-lint-switch.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) {
  # Not built in this tree. Say so loudly rather than passing vacuously: a
  # guard that skips when its subject is missing is a guard that never fails.
  Write-Host "SKIP-FATAL: drag-lint-switch.exe not found at $Exe" -ForegroundColor Yellow
  Write-Host "  Build src\tools\lsp-switch\drag-lint-switch.dproj (Win64 Debug) and re-run." -ForegroundColor Yellow
  exit 2
}
$Exe = (Resolve-Path $Exe).Path

$regRoot = 'Software\DragLintTest\SwitchParamsGuard'
$hkcu    = "HKCU:\$regRoot"
Check 'the scratch reg-root is NOT the real Embarcadero LSP key' `
  ($regRoot -notmatch '(?i)Embarcadero') $regRoot
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

if (Test-Path $hkcu) { Remove-Item -Path $hkcu -Recurse -Force }

$fakeExe = Join-Path $env:TEMP 'draglint-switch-guard-fake.exe'
Set-Content -LiteralPath $fakeExe -Value 'not a real exe' -Encoding Ascii
$wanted = 'lsp --proxy --delphilsp-exe C:\x\DelphiLSP.exe'

try {
  $onOut = & $Exe --delphi --on --exe $fakeExe --params $wanted --reg-root $regRoot 2>&1 | Out-String
  $onExit = $LASTEXITCODE

  Write-Host ''
  Write-Host 'The --params flag exists and reaches the registry' -ForegroundColor Cyan
  Check '--params is an accepted argument' `
    ($onOut -notmatch 'unknown argument') ($onOut -split "`r?`n" | Select-Object -First 1)
  Check '--on succeeded' ($onExit -eq 0 -or $onExit -eq 1) "exit $onExit"

  $entry = Get-ChildItem -Path $hkcu -ErrorAction SilentlyContinue | Select-Object -First 1
  Check 'an entry was created under the scratch root' ($null -ne $entry) ''

  $params = ''
  if ($null -ne $entry) {
    $params = (Get-ItemProperty -Path $entry.PSPath -Name 'Parameters' -ErrorAction SilentlyContinue).Parameters
  }
  # THE ASSERTION THE WHOLE FILE IS FOR. Against the pre-fix build this comes
  # back as the empty string, which is the RED that proves the guard discriminates.
  Check 'Parameters is NON-EMPTY' ($params -ne $null -and $params -ne '') "got: '$params'"
  Check 'Parameters is exactly what was passed' ($params -eq $wanted) "got: '$params'"

  Write-Host ''
  Write-Host 'POSITIVE CONTROLS' -ForegroundColor Cyan
  $exePath = ''
  if ($null -ne $entry) {
    $exePath = (Get-ItemProperty -Path $entry.PSPath -Name 'FileName' -ErrorAction SilentlyContinue).FileName
  }
  # Without this, "Parameters is non-empty" could pass on an entry that recorded
  # nothing else correctly -- i.e. the write path could be broken in a way this
  # guard would call green.
  Check 'the same entry also recorded the --exe path (value FileName)' `
    ($exePath -eq $fakeExe) "got: '$exePath'"

  $offOut = & $Exe --delphi --off --exe $fakeExe --reg-root $regRoot --backup-dir $env:TEMP 2>&1 | Out-String
  $left = @(Get-ChildItem -Path $hkcu -ErrorAction SilentlyContinue)
  Check '--off removes the entry again' ($left.Count -eq 0) `
    "entries left: $($left.Count)"
}
finally {
  if (Test-Path $hkcu) { Remove-Item -Path $hkcu -Recurse -Force -ErrorAction SilentlyContinue }
  $parent = 'HKCU:\Software\DragLintTest'
  if ((Test-Path $parent) -and -not (Get-ChildItem -Path $parent -ErrorAction SilentlyContinue)) {
    Remove-Item -Path $parent -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $fakeExe -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
