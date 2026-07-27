$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path "third_party\dll-win64\drag-lint.exe").Path
$fx  = (Resolve-Path "tests\ergonomics\pipeline_fixture.pas").Path
$pass = 0; $fail = 0
function Ok($n,$c){ if($c){$script:pass++; Write-Host "PASS  $n"} else {$script:fail++; Write-Host "FAIL  $n"} }

# 1. SARIF: --format sarif emits parseable SARIF with our rule.
$sarif = & $exe lint $fx --format sarif 2>$null | Out-String
$j = $null; try { $j = $sarif | ConvertFrom-Json } catch {}
Ok "sarif parses"            ($j -ne $null)
Ok "sarif version 2.1.0"     ($j.version -eq '2.1.0')
Ok "sarif has used-before-assignment" ($sarif -match 'used-before-assignment')

# 2. --fail-on: warning-level finding.
& $exe lint $fx --fail-on error  2>$null | Out-Null; $ecErr  = $LASTEXITCODE
& $exe lint $fx --fail-on warning 2>$null | Out-Null; $ecWarn = $LASTEXITCODE
& $exe lint $fx --fail-on none    2>$null | Out-Null; $ecNone = $LASTEXITCODE
Ok "fail-on error => 0 (only warning)" ($ecErr  -eq 0)
Ok "fail-on warning => 1"              ($ecWarn -eq 1)
Ok "fail-on none => 0"                 ($ecNone -eq 0)

# 3. severity override via --config: bump the rule to error, fail-on error now trips.
$cfg = Join-Path $PSScriptRoot 'pipeline_sev.json'
'{ "severity": { "used-before-assignment": "error" } }' | Set-Content -Encoding ASCII $cfg
& $exe lint $fx --config $cfg --fail-on error 2>$null | Out-Null; $ecSev = $LASTEXITCODE
Ok "severity bump => fail-on error trips" ($ecSev -eq 1)

# 4. disable via --config drops THAT rule's finding.
# This used to assert the whole run reports '0 finding'. That was only ever true
# while used-before-assignment was the ONLY rule firing on the fixture; once
# local-var-casing shipped it also fires on `var n: Integer`, the total became
# 1, and the check went red without the disable ever having broken. Assert the
# rule-specific effect plus "exactly one fewer finding than the un-configured
# run" -- both stay true no matter how many unrelated rules land later.
$cfgD = Join-Path $PSScriptRoot 'pipeline_dis.json'
'{ "disabled": ["used-before-assignment"] }' | Set-Content -Encoding ASCII $cfgD
$all = & $exe lint $fx 2>$null | Out-String
$dis = & $exe lint $fx --config $cfgD 2>$null | Out-String
function FindingCount([string]$text) {
  $m = [regex]::Match($text, '(\d+)\s+finding')
  if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}
Ok "disabled rule drops finding"  (-not ($dis -match 'used-before-assignment'))
Ok "un-disabled run still has it" ($all -match 'used-before-assignment')
Ok "disable removes exactly one finding" `
  ((FindingCount $all) -ge 1 -and (FindingCount $dis) -eq ((FindingCount $all) - 1))

# 5. baseline round-trip: write, then re-run reports nothing new.
$base = Join-Path $PSScriptRoot 'pipeline.baseline.json'
& $exe lint $fx --write-baseline $base 2>$null | Out-Null
$new = & $exe lint $fx --baseline $base 2>$null | Out-String
Ok "baseline suppresses known finding" ($new -match '0 finding')

Remove-Item $cfg,$cfgD,$base -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "pipeline-tests: $pass pass / $fail fail"
if ($fail -gt 0) { exit 1 } else { exit 0 }
