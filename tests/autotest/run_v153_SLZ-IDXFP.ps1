# Guard for index-possibly-out-of-range (1.53 lane SLZ-IDXFP): with --db an index passed to another unit's
# routine that takes it BY VALUE stays proven (PurityStage:1221 BeatProgress(I)); a VAR parameter does not.
# Fixture tests\lint\index-possibly-out-of-range-byval\ (two units). The one-file classes are in
# tests\lint\index-possibly-out-of-range-fp53.pas (run_lint_tests.ps1).
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
$src = Join-Path $repo 'tests\lint\index-possibly-out-of-range-byval'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("idxbv-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item "$src\*.pas" $tmp
'{}' | Set-Content -Encoding ascii (Join-Path $tmp 'drag-lint.json')
$db = Join-Path $tmp 'idxbv.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> $null }
$unit = Join-Path $tmp 'BvUse.pas'
$raw = & { $ErrorActionPreference = 'Continue'; & $exe lint $unit --db $db --rule $rule --json 2>$null }
$f = @()
try { $f = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object { $_ -and $_.rule -eq $rule }) } catch { $f = @() }
$lines = [IO.File]::ReadAllLines($unit)
$owner = @{}
$cur = ''
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^function\s+(\w+)') { $cur = $Matches[1] }
  $owner[$i + 1] = $cur
}
$hit = @($f | ForEach-Object { $owner[[int]$_.start_line] })
Write-Host ("findings: " + (($f | ForEach-Object { "$($owner[[int]$_.start_line]):$($_.start_line)" }) -join ', '))
Assert "the index was read (a database exists)" (Test-Path $db)
Assert "CountRuns: silent" ($hit -notcontains 'CountRuns')
Assert "CtlCountRuns: reported" ($hit -contains 'CtlCountRuns')
try { [IO.Directory]::Delete($tmp, $true) } catch { }
if ($fail -gt 0) { Write-Host "$fail FAIL" -ForegroundColor Red } else { Write-Host "all passed" }
exit $fail
