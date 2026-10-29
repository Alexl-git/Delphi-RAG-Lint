# g8-common.ps1 -- shared helpers for the four lane-G8 project-wide rule guards
# (run_dfm_event_handler_missing / run_dfm_password_edit_unmasked /
#  run_uses_movable_to_implementation / run_virtual_never_overridden.ps1).
# Dot-sourced; not a guard itself. Each guard indexes a COPY of its tests\lint-project fixture
# (everything except the fixture's expected\ folder) into a scratch DB, so a --fix --apply run
# never touches the checked-in fixture.
$script:Failed = $false
. (Join-Path $PSScriptRoot exe-hint.ps1)   # Get-ExeStartFailureHint (lane CLIFIX C2)
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
function New-G8Scratch([string]$Fixture, [string]$WorkDir) {
  $src = Join-Path $PSScriptRoot "..\lint-project\$Fixture"
  $dst = Join-Path $WorkDir 'fx'
  New-Item -ItemType Directory -Force $dst | Out-Null
  Get-ChildItem $src -File | ForEach-Object { Copy-Item $_.FullName $dst -Force }
  return $dst
}
function Invoke-G8Index([string]$Exe, [string]$Dir, [string]$Db) {
  if (Test-Path $Db) { [IO.File]::Delete($Db) }
  & $Exe index $Dir --db $Db 2>&1 | Out-Null
  $code = $LASTEXITCODE
  $hint = Get-ExeStartFailureHint $code
  if ($hint) { Write-Host "  [FATAL] $hint" -ForegroundColor Red }
  return $code
}
function Get-G8Findings([string]$Exe, [string]$Db, [string]$Rule, [string[]]$Extra = @(), [switch]$AllRules) {
  # -AllRules: no --rule flag (an explicit --rule opts an OFF-by-default rule in, so it cannot test OFF).
  $ruleArgs = if ($AllRules) { @() } else { @('--rule', $Rule) }
  $raw = & $Exe lint-all --db $Db @ruleArgs --format json @Extra 2>$null
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $f = @(); if ($b -ge 0) { try { $f = @($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
  return ,@($f | Where-Object { $_.rule -eq $Rule })
}
function Test-G8BytesEqual([string]$A, [string]$B) {
  $x = [IO.File]::ReadAllBytes($A); $y = [IO.File]::ReadAllBytes($B)
  if ($x.Length -ne $y.Length) { return $false }
  for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { return $false } }
  return $true
}
function Show-G8Findings($Findings) {
  @($Findings) | Where-Object { $_ } | ForEach-Object { Write-Host ("    {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) -ForegroundColor DarkGray }
}