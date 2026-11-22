# Guard for index-possibly-out-of-range (1.52.3 lane IDXRANGE-TP): the accessed array is a constant
# array declared in ANOTHER unit (uINSPRSLT:5575 reads MscConst.NssDistConvert[i] with i = 5). Its
# bounds come from the index (lint --db); an ambiguous name (two shapes) and a local shadow stay silent.
# Fixture tests\lint\index-possibly-out-of-range-xunit\ (three units).
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$rule = 'index-possibly-out-of-range'
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
$src = Join-Path $repo 'tests\lint\index-possibly-out-of-range-xunit'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("idxtp-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item "$src\*.pas" $tmp
'{}' | Set-Content -Encoding ascii (Join-Path $tmp 'drag-lint.json')
$db = Join-Path $tmp 'idxtp.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> $null }
$unit = Join-Path $tmp 'XuUse.pas'
$raw = & { $ErrorActionPreference = 'Continue'; & $exe lint $unit --db $db --rule $rule --json 2>$null }
$f = @()
try { $f = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object { $_ -and $_.rule -eq $rule }) } catch { $f = @() }

# map each line to its routine (method names keep their class prefix)
$lines = [IO.File]::ReadAllLines($unit)
$owner = @{}
$cur = ''
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^(procedure|function)\s+([\w.]+)') { $cur = $Matches[2] }
  $owner[$i + 1] = $cur
}
$byRoutine = @{}
foreach ($x in $f) { $r = $owner[[int]$x.start_line]; $byRoutine[$r] = @($byRoutine[$r]) + @([string]$x.message) }
Write-Host ("findings: " + (($f | ForEach-Object { "$($owner[[int]$_.start_line]):$($_.start_line)" }) -join ', '))

# positive controls: the finding names the FOREIGN array, not the in-range loop array
Assert "TInsp.DisplayFire: NssDistConvert[i] reported" (@($byRoutine['TInsp.DisplayFire'] | Where-Object { $_ -match 'NssDistConvert\[i\]' }).Count -ge 1)
Assert "ConvFire: NssConv[i] reported" (@($byRoutine['ConvFire'] | Where-Object { $_ -match 'NssConv\[i\]' }).Count -ge 1)
foreach ($r in 'ConvSilent', 'ForSilent', 'AmbigSilent', 'ShadowSilent', 'ClampSilent', 'WhileHighSilent', 'CorrelatedSilent', 'ParallelSilent') {
  Assert "silent in $r" (-not $byRoutine.ContainsKey($r))
}

try { [IO.Directory]::Delete($tmp, $true) } catch { }
if ($fail -gt 0) { Write-Host "$fail FAIL" -ForegroundColor Red } else { Write-Host "all passed" }
exit $fail
