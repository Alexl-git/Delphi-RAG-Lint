# Interprocedural object-leak test: index the fixture (callers + helpers), then
# run the store-bearing per-file check (check-ast) on callers.pas. The leak
# through the non-owning helper must surface (line 12); the owning-helper case
# (line 19) must stay clean.
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$dir = $PSScriptRoot
$db  = Join-Path $env:TEMP "objleak_interproc.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }

& $exePath index $dir --db $db | Out-Null
$raw = & $exePath check-ast (Join-Path $dir "callers.pas") --db $db --format json 2>$null
# the CLI prints a few preamble lines (FTS5 probe / loaded defaults) before the
# JSON array -- slice from the first '[' so ConvertFrom-Json sees only JSON.
$txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
$f = @(); if ($b -ge 0) { try { $f = ($txt.Substring($b) | ConvertFrom-Json) } catch { $f = @() } }
if ($null -eq $f) { $f = @() }
$leaks = @($f | Where-Object { $_.rule -eq 'object-leak' })
$leaks | ForEach-Object { Write-Host ("  object-leak:{0} [{1}]" -f $_.start_line, $_.severity) }
$at12 = @($leaks | Where-Object { $_.start_line -eq 12 }).Count -gt 0
$at19 = @($leaks | Where-Object { $_.start_line -eq 19 }).Count -gt 0
if ($at12 -and (-not $at19)) {
  Write-Host "PASS  objleak-interproc (leak via non-owning at 12; clean via owning at 19)"
  exit 0
} else {
  Write-Host "FAIL  objleak-interproc  (at12=$at12 at19=$at19; expected at12=True at19=False)"
  exit 1
}
