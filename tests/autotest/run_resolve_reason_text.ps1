<#
  run_resolve_reason_text.ps1 -- the log text of a --resolve-only pass tells the truth.

  Two lines, both on the resolver surface but TEXT ONLY (no edge changes):
    * RESOLVE-REASON-TEXT: --resolve-only on a DB with no file writes names the
      CLEAR as the reason for the whole-DB pass, not "recorded no file writes".
    * WITHHELD-LOG-TEXT: after the clear, a file whose source changed since it
      was indexed has NO edges; the WITHHELD line must not say they were
      "left alone" (that is true only on a scoped pass).
  Positive control: run it with -Exe pointing at a 1.42 engine; it must FAIL.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_resolve_reason_$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
[System.IO.Directory]::CreateDirectory("$WorkDir\src") | Out-Null
$src = "$WorkDir\src"
function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $src $name), ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}
Emit 'uCallee.pas' "unit uCallee;`ninterface`nprocedure Target;`nimplementation`nprocedure Target;`nbegin`nend;`nend.`n"
Emit 'uCaller.pas' "unit uCaller;`ninterface`nuses uCallee;`nprocedure Go;`nimplementation`nprocedure Go;`nbegin`n  Target;`nend;`nend.`n"
$db = "$WorkDir\r.sqlite"
Push-Location C:\TEMP
try {
  & $Exe index $src --db $db 2>&1 | Out-Null
  Check 'fixture indexed' (Test-Path $db)
  $plain = & $Exe index $src --db $db --resolve-only 2>&1 | Out-String
  Check 'unchanged DB: reason names the clear' ($plain -match 'whole database because a full edge clear was asked for') ''
  Check 'unchanged DB: the vague reason is gone' (-not ($plain -match 'recorded no file writes')) ''
  # make uCaller stale: change its bytes after indexing, do NOT reindex
  Emit 'uCaller.pas' "unit uCaller;`ninterface`nuses uCallee;`nprocedure Go;`nimplementation`nprocedure Go;`nbegin`n  Target;`n  Target;`nend;`nend.`n"
  $stale = & $Exe index $src --db $db --resolve-only 2>&1 | Out-String
  Check 'stale file: WITHHELD line present (control that the scenario fires)' ($stale -match 'WITHHELD')
  Check 'stale file: text does not claim edges were left alone' (-not ($stale -match 'WITHHELD[^\r\n]*left alone')) ''
  Check 'stale file: text says the clear removed them' ($stale -match 'WITHHELD[^\r\n]*cleared all call edges') ''
} finally { Pop-Location; [System.IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }