<#
  install-vsix-all-profiles.ps1 -- install dist\drag-lint-<package.json version>.vsix
  into EVERY local VS Code profile (the default profile plus each userDataProfiles
  entry of globalStorage\storage.json).

  WHY: 2026-11-11 the "DL" profile's extensions.json pointed drag-lint.drag-lint at a
  deleted 1.6.0 folder and the extension silently never loaded. Called by
  pack-lint-release.ps1 (default ON; -NoProfileInstall there skips it); verified by
  tests\autotest\run_vscode_extension_installed_guard.ps1.

  -WhatIf prints the plan (one `code --install-extension` per profile) and changes
  nothing. -UserDir / -CodeCmd are overridable for tests.
  Exit 0 when VS Code is absent (nothing to install into), 1 when the vsix is
  missing or any install fails.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$Vsix,
  [string]$UserDir = "$env:APPDATA\Code\User",
  [string]$CodeCmd = 'code'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Vsix) {
  $ver = (Get-Content (Join-Path $repo 'editors\vscode\drag-lint\package.json') -Raw | ConvertFrom-Json).version
  $Vsix = Join-Path $repo "dist\drag-lint-$ver.vsix"
}
if (-not (Test-Path -LiteralPath $Vsix)) { Write-Host "vsix missing: $Vsix (run editors\vscode\drag-lint\scripts\package.js)" -ForegroundColor Red; exit 1 }
if (-not (Test-Path -LiteralPath $UserDir)) { Write-Host "SKIP: VS Code user dir not found ($UserDir)"; exit 0 }
if (-not (Get-Command $CodeCmd -ErrorAction SilentlyContinue)) { Write-Host "SKIP: '$CodeCmd' not on PATH"; exit 0 }

$profiles = @($null)   # $null = the default profile
$st = Join-Path $UserDir 'globalStorage\storage.json'
if (Test-Path -LiteralPath $st) {
  foreach ($p in @((Get-Content -LiteralPath $st -Raw | ConvertFrom-Json).userDataProfiles)) {
    if ($p.name) { $profiles += [string]$p.name }
  }
}
$bad = 0
foreach ($p in $profiles) {
  $label = if ($p) { $p } else { '(default)' }
  $cargs = @('--install-extension', $Vsix, '--force')
  if ($p) { $cargs = @('--profile', $p) + $cargs }
  if ($PSCmdlet.ShouldProcess($label, "$CodeCmd $($cargs -join ' ')")) {
    & $CodeCmd @cargs
    if ($LASTEXITCODE -ne 0) { Write-Host "install FAILED in profile $label" -ForegroundColor Red; $bad++ }
  }
}
exit ([int]($bad -gt 0))