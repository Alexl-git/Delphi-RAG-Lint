# Managed-type precision via the store (M1 ResolveTypeCategory). `IThing = class`
# is an I-prefixed CLASS (unmanaged): the store-free heuristic follows the I-prefix
# interface convention and WRONGLY skips it (missing a real used-before of an
# uninitialized class reference); with a store the type resolves to a class
# (unmanaged, checkable) and the finding correctly surfaces.
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$dir = $PSScriptRoot
$pas = Join-Path $dir "managedclass.pas"
$db  = Join-Path $env:TEMP "managed_class.sqlite"
if (Test-Path $db) { Remove-Item $db -Force }

function UsedBefore($raw) {
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  if ($b -lt 0) { return @() }
  try { return @(($txt.Substring($b) | ConvertFrom-Json) | Where-Object { $_.rule -eq 'used-before-assignment' }) }
  catch { return @() }
}

# heuristic (no store): I-prefix convention -> treated as managed -> skipped
$noStore = UsedBefore (& $exePath lint $pas --json 2>$null)
# store-backed: IThing resolves to a class (unmanaged) -> the read is checked
& $exePath index $dir --db $db | Out-Null
$withStore = UsedBefore (& $exePath check-ast $pas --db $db --format json 2>$null)

Write-Host ("  store-free used-before: {0}; store-backed used-before: {1}" -f $noStore.Count, $withStore.Count)
if (($noStore.Count -eq 0) -and ($withStore.Count -ge 1)) {
  Write-Host "PASS  managed-class (store resolves I-prefixed class -> precise used-before the heuristic missed)"
  exit 0
} else {
  Write-Host "FAIL  managed-class (expected store-free=0, store-backed>=1)"
  exit 1
}
