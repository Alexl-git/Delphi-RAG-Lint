# Guard for index-possibly-out-of-range FP classes (1.52 lane BK-RULEFP, B01): the six FP classes
# of the IDXRANGE2 12-sample (YADF.Tokens:208, STATS:1988, uINSPRSLT:1871, Pipes.Protocol:1069,
# uBroadcastServer:373, Blueprint4.ViewModel:2009) plus Blueprint4.ViewModel:1722, each with a
# positive control (a routine named *Bad that must still fire).
# Fixture tests\lint\idxfp\ (two units: the foreign constant array of F3 comes from the index).
# Also pins the rule's default: ON (owner C3; the FP gate classes fixed here).
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
$src = Join-Path $repo 'tests\lint\idxfp'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("idxfp-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item "$src\*.pas" $tmp
'{}' | Set-Content -Encoding ascii (Join-Path $tmp 'drag-lint.json')
$db = Join-Path $tmp 'idxfp.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> $null }
$unit = Join-Path $tmp 'IdxFp.pas'
$raw = & { $ErrorActionPreference = 'Continue'; & $exe lint $unit --db $db --rule $rule --json 2>$null }
$f = @()
try { $f = @(($raw | ConvertFrom-Json) | Where-Object { $_ -and $_.rule -eq $rule }) } catch { $f = @() }

# map each line to its routine
$lines = [IO.File]::ReadAllLines($unit)
$owner = @{}
$cur = ''
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^(procedure|function)\s+(\w+)') { $cur = $Matches[2] }
  $owner[$i + 1] = $cur
}
$byRoutine = @{}
foreach ($x in $f) { $r = $owner[[int]$x.start_line]; $byRoutine[$r] = 1 + [int]$byRoutine[$r] }
Write-Host ("findings: " + (($f | ForEach-Object { "$($owner[[int]$_.start_line]):$($_.start_line)" }) -join ', '))

foreach ($r in 'MarkAfter', 'PickSx', 'PickSxRange', 'NssFrom', 'TryParse', 'Targets', 'Rows6', 'Rows7', 'Rows8', 'MarkOne') {
  Assert "silent in $r (FP class fixed)" (-not $byRoutine.ContainsKey($r))
}
foreach ($r in 'MarkAfterBad', 'PickSxBad', 'NssFromBad', 'TryParseBad', 'TargetsBad', 'Rows6Bad', 'Rows8Bad') {
  Assert "positive control fires in $r" ($byRoutine.ContainsKey($r))
}

# default ON: no --rule, no config
$raw2 = & { $ErrorActionPreference = 'Continue'; & $exe lint $unit --db $db --json 2>$null }
$d = @()
try { $d = @(($raw2 | ConvertFrom-Json) | Where-Object { $_ -and $_.rule -eq $rule }) } catch { $d = @() }
Assert "default ON: the rule runs without a config (got $($d.Count), narrowed $($f.Count))" (($d.Count -eq $f.Count) -and ($f.Count -gt 0))
$rj = (& { $ErrorActionPreference = 'Continue'; & $exe rules --json 2>$null } | ConvertFrom-Json).rules
$ent = @($rj | Where-Object { $_.id -eq $rule })[0]
Assert "rules --json: default_enabled true" ($ent -and $ent.default_enabled -eq $true)

try { [IO.Directory]::Delete($tmp, $true) } catch { }
if ($fail -gt 0) { Write-Host "$fail FAIL" -ForegroundColor Red } else { Write-Host "all passed" }
exit $fail