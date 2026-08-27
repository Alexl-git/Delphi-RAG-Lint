<#
  run_vscode_engine_copy.ps1 -- the VS Code client must run a PRIVATE COPY of
  the engine, not the deployed binary the Delphi IDE uses.

  WHY THIS MATTERS ENOUGH TO GUARD
  --------------------------------
  A running process holds an execute lock on its own image. Until extension
  v1.4 the VS Code language server ran the DEPLOYED drag-lint.exe, so an idle
  VS Code window made `build\build_draglint_win64.bat` fail with
  "ERROR: failed to stage ...\drag-lint.exe" -- the compile succeeded and the
  deploy did not. Killing the server did not help: VS Code respawns it inside a
  second, so the build lost the race again. It cost several rebuild cycles
  before the mechanism was identified.

  The fix decouples the two editors: the Delphi IDE keeps loading the freshly
  deployed engine (it is the one that must stay current), and VS Code runs a
  snapshot refreshed only when the extension activates. If a later change
  quietly points the client back at the deployed path, the symptom returns as a
  confusing build failure with no obvious cause -- so it is pinned here.

  WHAT IT ACTUALLY EXERCISES
  --------------------------
  tests\vscode\engine-copy-harness.js loads the real extension.js with a stubbed
  `vscode` module and drives mirrorEngine()/resolveExe() directly. That reaches
  the failure modes a manual click-through cannot: a copy interrupted halfway
  (stamp says current, exe missing), a rule deleted upstream lingering in the
  copy, and the file list -- which carries its own NEGATIVE CONTROL, because
  "copy the whole folder" would satisfy every positive assertion while dragging
  ~60 MB of BPL and graph exe the language server never opens.

  Node is required. When it is absent this SKIPS rather than fails: node is not
  otherwise a dependency of this repo, and a machine without it can still be a
  perfectly good Delphi build box.

  Exit code: 0 on full pass or skip, 1 on any failure.

  Usage: pwsh -File tests\vscode\run_vscode_engine_copy.ps1
#>
[CmdletBinding()]
param(
  [string] $Harness = "$PSScriptRoot\engine-copy-harness.js"
)

$ErrorActionPreference = 'Stop'

Write-Host '== VS Code client runs a private engine copy ==' -ForegroundColor Cyan

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  Write-Host 'SKIP: node is not on PATH (it is not otherwise a dependency of this repo)' -ForegroundColor Yellow
  exit 0
}
if (-not (Test-Path -LiteralPath $Harness)) {
  Write-Host "FATAL: harness not found at $Harness" -ForegroundColor Red
  exit 1
}

# The extension requires vscode-languageclient at load time; without the
# extension's node_modules the harness would fail for a reason that has nothing
# to do with what is being tested. Say which it is.
$extDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'editors\vscode\drag-lint'
if (-not (Test-Path -LiteralPath (Join-Path $extDir 'node_modules'))) {
  Write-Host "SKIP: $extDir\node_modules is absent (run npm install there to enable this guard)" -ForegroundColor Yellow
  exit 0
}

$out = & $node.Source $Harness 2>&1
$rc  = $LASTEXITCODE

foreach ($line in $out) {
  $text = [string]$line
  if ($text -like 'PASS *')      { Write-Host ("  [PASS] " + $text.Substring(5)) -ForegroundColor Green }
  elseif ($text -like 'FAIL *')  { Write-Host ("  [FAIL] " + $text.Substring(5)) -ForegroundColor Red }
  elseif ($text -like 'HARNESS:*') { }
  else { Write-Host ("  " + $text) -ForegroundColor DarkGray }
}

# POSITIVE CONTROL on the runner itself: a harness that printed nothing would
# exit 0 and read as a clean pass.
$passCount = @($out | Where-Object { ([string]$_) -like 'PASS *' }).Count
if ($passCount -lt 10) {
  Write-Host ''
  Write-Host "VSCODE ENGINE COPY GUARD: FAIL (only $passCount assertions ran; the harness did not execute)" -ForegroundColor Red
  exit 1
}

Write-Host ''
if ($rc -ne 0) { Write-Host 'VSCODE ENGINE COPY GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host "VSCODE ENGINE COPY GUARD: PASS ($passCount assertions)" -ForegroundColor Green
exit 0
