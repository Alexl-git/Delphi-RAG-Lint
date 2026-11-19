# Guard for index-possibly-out-of-range FP classes (1.52 lane IDXRANGE3): the seven FP classes of the
# FPM2 re-measure (C:\TEMP\claude\lanes\v152\FPM2\FP-REMEASURE2.md) -- short-circuit guard over an
# index chain, while-top guard, SetLength(A, N) then an index bounded by N (a local written once, a
# record field, a callee's Result in this unit and in another unit of the index), a dominating
# Length(A) <> Length(B) Exit, an array sized through a callee's out parameter or by the enclosing routine, a counter stepped once per trip (compaction, for-in), a counter with a
# constant cap on a fixed-size array, a float-derived index behind a range guard -- each with a
# positive control (a routine named *Bad that must still fire).
# Fixture tests\lint\idxfp3\ (two units: LibLock / LibLockShort come from the index).
# Also pins the rule's default: ON again in 1.52 (re-measure on DB copies: YADF 0/12, CLIENT 0/12, SERVER 0/5).
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
$src = Join-Path $repo 'tests\lint\idxfp3'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("idxfp3-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item "$src\*.pas" $tmp
'{}' | Set-Content -Encoding ascii (Join-Path $tmp 'drag-lint.json')
$db = Join-Path $tmp 'idxfp3.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> $null }
$unit = Join-Path $tmp 'IdxFp3.pas'
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

foreach ($r in 'Chain1', 'WhileTop', 'ChainReset', 'SetLenOnce', 'SetLenField', 'SetLenOpaque', 'MakeLock', 'CalleeLen', 'CalleeLib',
               'ShapesMatch', 'Compact', 'Snapshot5', 'ForReuse', 'OutSized', 'OuterArr', 'GrowByOne', 'SnapDotted', 'KeepNames', 'LeadingComments', 'SniffUtf8', 'ShadowChain', 'OtherBranch', 'SameSized', 'Cands6', 'Handles3', 'RoundIdx', 'Gauss') {
  Assert "silent in $r (FP class fixed)" (-not $byRoutine.ContainsKey($r))
}
foreach ($r in 'Chain1Bad', 'WhileTopBad', 'WhileTopNoContinueBad', 'ChainResetBad', 'SetLenOnceBad', 'SetLenFieldBad', 'SetLenFieldNilBad', 'SetLenOpaqueBad', 'CalleeLenBad', 'CalleeLibBad',
               'ShapesMatchBad', 'CompactBad', 'Snapshot5Bad', 'ForReuseBad', 'OutSizedBad', 'OuterArrBad', 'GrowByOneBad', 'SnapDottedBad', 'KeepNamesBad', 'LeadingCommentsBad', 'SniffUtf8Bad', 'ShadowChainBad', 'OtherBranchBad', 'SameSizedBad', 'Cands6Bad', 'Handles3Bad', 'RoundIdxBad',
               'GaussBad', 'GaussBad2') {
  Assert "positive control fires in $r" ($byRoutine.ContainsKey($r))
}

# default ON (owner C3, IDXRANGE3 re-measure 0 FP / 12): no --rule, no config -> the Bad routines still fire
$raw2 = & { $ErrorActionPreference = 'Continue'; & $exe lint $unit --db $db --json 2>$null }
$d = @()
try { $d = @(($raw2 | ConvertFrom-Json) | Where-Object { $_ -and $_.rule -eq $rule }) } catch { $d = @() }
Assert "default ON: fires without --rule (got $($d.Count), narrowed $($f.Count))" (($d.Count -gt 0) -and ($d.Count -eq $f.Count))
$rj = (& { $ErrorActionPreference = 'Continue'; & $exe rules --json 2>$null } | ConvertFrom-Json).rules
$ent = @($rj | Where-Object { $_.id -eq $rule })[0]
Assert "rules --json: default_enabled true" ($ent -and $ent.default_enabled -eq $true)

try { [IO.Directory]::Delete($tmp, $true) } catch { }
if ($fail -gt 0) { Write-Host "$fail FAIL" -ForegroundColor Red } else { Write-Host "all passed" }
exit $fail
