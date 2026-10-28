<#
  run_find_callees_external.ps1 -- item 4, lane C skeleton (spec s.8). RED until
  lane C: `find-callees` on the project-only DB, with the library DB passed as a (repeated --db; lane C decides the exact CLI form)
  second --db, must show an external callee marked "(library" for P1 (S.Read).
  Lane C completes this with the text + --json `via` edge/oracle rows for P1/P2/P6.
  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
$scratch = Join-Path C:\TEMP "draglint_fcext_$PID"
try {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
  $libDir = Join-Path $scratch 'lib'; $appDir = Join-Path $scratch 'app'
  New-Item -ItemType Directory -Path $libDir,$appDir -Force | Out-Null
  Copy-Item (Join-Path $fixDir 'xt_lib.pas') $libDir -Force
  Copy-Item (Join-Path $fixDir 'xt_app.pas'),(Join-Path $fixDir 'xt_app2.pas') $appDir -Force
  $libDb = Join-Path $scratch 'lib.sqlite'; $appDb = Join-Path $scratch 'app.sqlite'
  Push-Location C:\TEMP
  try {
    & $exePath index $libDir --db $libDb 2>$null | Out-Null
    & $exePath index $appDir --db $appDb 2>$null | Out-Null
    Check 'indexes built' ($LASTEXITCODE -eq 0)
    $out = (& $exePath find-callees --qname xt_app.Go --db $appDb --db $libDb 2>&1 | Out-String)
    Check 'find-callees Go lists the library callee Read marked "(library"' (($out -match 'Read') -and ($out -match '\(library')) $out
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }