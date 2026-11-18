#Requires -Version 7
<#
  run_v152_VSRESTART_plannedstop.ps1 -- 1.52 lane VSRESTART: a planned stop of the VS Code language client
  (Restart Language Server / Update Engine Copy Now) logs 0 error lines (write EOF, stream destroyed,
  "Server process exited with code N") and one "Server stopped for restart" line, and never spends the
  crash-restart budget; an unplanned stop passes every line through. Also pins that extension.js uses the
  gate in both stop paths and that the engine LSP exits 0 on shutdown/EOF (static check of the Run loop).
#>
[CmdletBinding()]
param([string]$Dir = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Dir) { $Dir = "$PSScriptRoot\..\..\editors\vscode\drag-lint" }
$ErrorActionPreference = 'Stop'
$fail = 0
function Check($n, $ok) { if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green } else { Write-Host "  [FAIL] $n" -ForegroundColor Red; $script:fail++ } }
$node = (Get-Command node -ErrorAction SilentlyContinue)
Check 'node available' ($null -ne $node)
if ($node) {
  $out = & node (Join-Path $Dir 'test\plannedstop.test.js') 2>&1 | Out-String
  Check 'plannedstop.test.js passes' ($LASTEXITCODE -eq 0 -and $out -match 'all assertions passed')
}
$ext = [IO.File]::ReadAllText((Join-Path $Dir 'extension.js'))
Check 'extension.js: both stop paths go through stopClientPlanned' ((([regex]::Matches($ext, 'await stopClientPlanned\(\)')).Count) -ge 2)
Check 'extension.js: client uses the shared wrapped channel' ($ext -match 'outputChannel: sharedClientChannel\(\)')
Check 'extension.js: error handler wrapped by the gate' ($ext -match 'plannedstop\.wrapErrorHandler')
$srv = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\src\lsp\DRagLint.LSP.Server.pas'))
Check 'engine: shutdown ends the Run loop (FShuttingDown) and Run is followed by Result := 0' ($srv -match 'while not FShuttingDown do')
if ($fail) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS'; exit 0
