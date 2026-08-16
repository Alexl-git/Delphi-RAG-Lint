<#
  run_vscode_extension_contract.ps1 -- the VS Code client's manifest and its code
  must agree, and the pieces that exist to survive an engine redeploy must still
  be there.

  WHY THIS EXISTS:
    dragLint.serverPath points at the SAME deployed binary the Delphi IDE loads
    -- deliberately, so the two can never disagree about which build answered.
    The cost is that redeploying the engine overwrites the file a running
    language server is executing from. vscode-languageclient's stock policy is
    5 crashes in 3 minutes -> never restart, and five restage cycles in three
    minutes is an ordinary engine-development afternoon. The extension
    contributed NO commands, so the only way back was reloading the window.

    Three things now prevent that, and each is easy to delete by accident:
      * a `dragLint.restartServer` command, contributed AND registered;
      * an errorHandler with a budget bigger than the stock 5;
      * a filter that drops empty strings from dragLint.databases (an empty
        entry pushed '--db' plus an argument Windows quoting drops, producing a
        trailing bare --db that fatals during argument parsing).

    A command contributed in package.json but not registered in extension.js
    gives "command 'dragLint.restartServer' not found" -- worse than no command,
    because it appears in the palette. So both halves are checked, in both
    directions.

  This is a STATIC contract check. It does not launch VS Code; there is no
  JS test harness in this repo and adding one would mean a build step the
  extension deliberately avoids (see extension.js's own header).
#>
[CmdletBinding()]
param(
  [string]$Dir = "$PSScriptRoot\..\..\editors\vscode\drag-lint"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$pkgPath = Join-Path $Dir 'package.json'
$extPath = Join-Path $Dir 'extension.js'
if (-not (Test-Path $pkgPath)) { Write-Host "FATAL: not found: $pkgPath" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $extPath)) { Write-Host "FATAL: not found: $extPath" -ForegroundColor Red; exit 2 }

$pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json
$ext = Get-Content $extPath -Raw

Write-Host 'Manifest and code agree on the contributed commands' -ForegroundColor Cyan
$declared = @($pkg.contributes.commands | ForEach-Object { $_.command })
$registered = @([regex]::Matches($ext, "registerCommand\(\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
Check 'package.json contributes at least one command' ($declared.Count -ge 1) ("declared=" + ($declared -join ','))
Check 'extension.js registers at least one command' ($registered.Count -ge 1) ("registered=" + ($registered -join ','))
$onlyDeclared  = @($declared  | Where-Object { $registered -notcontains $_ })
$onlyRegistered = @($registered | Where-Object { $declared -notcontains $_ })
Check 'every contributed command is registered (else "command not found" in the palette)' `
  ($onlyDeclared.Count -eq 0) ("missing=" + ($onlyDeclared -join ','))
Check 'every registered command is contributed (else it is unreachable from the palette)' `
  ($onlyRegistered.Count -eq 0) ("undeclared=" + ($onlyRegistered -join ','))
Check 'the restart command specifically is present on both sides' `
  (($declared -contains 'dragLint.restartServer') -and ($registered -contains 'dragLint.restartServer'))

Write-Host ''
Write-Host 'The redeploy-survival machinery is still wired' -ForegroundColor Cyan
Check 'an errorHandler is passed in the client options' ($ext -match 'errorHandler\s*:') ''
Check 'CloseAction / ErrorAction are imported (undefined enums would silently no-op)' `
  (($ext -match 'CloseAction') -and ($ext -match 'ErrorAction') -and ($ext -match "require\('vscode-languageclient/node'\)")) ''
Check 'the restart budget exceeds the stock 5-crash policy' `
  ($ext -match 'RESTART_BUDGET\s*=\s*(\d+)' -and [int]$Matches[1] -gt 5) ("budget=" + $Matches[1])
Check 'CloseAction.Restart is actually returned somewhere' ($ext -match 'CloseAction\.Restart') ''
Check 'empty dragLint.databases entries are filtered before becoming --db args' `
  ($ext -match "databases'\s*\)[\s\S]{0,200}?\.filter\(") ''

Write-Host ''
Write-Host 'The declared languageclient dependency supports what the code uses' -ForegroundColor Cyan
$dep = $pkg.dependencies.'vscode-languageclient'
Check 'vscode-languageclient is a declared dependency' ($null -ne $dep) "range=$dep"
$installed = Join-Path $Dir 'node_modules\vscode-languageclient\package.json'
if (Test-Path $installed) {
  $iv = (Get-Content $installed -Raw | ConvertFrom-Json).version
  Check 'the installed major version is 9 or later (CloseAction lives in /node from 9)' `
    ([int]($iv -split '\.')[0] -ge 9) "installed=$iv"
} else {
  Write-Host '  [NOTE] node_modules absent -- version assertion skipped (run npm install to cover it)' -ForegroundColor DarkGray
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
