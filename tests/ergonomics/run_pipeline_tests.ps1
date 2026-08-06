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
  # ANCHORED to the summary line -- a whole line that is nothing but
  # "<N> finding(s)". The first version matched '(\d+)\s+finding' ANYWHERE, so
  # the moment the text renderer gained any other count line ahead of the
  # summary (per-file totals, suppressed counts, a baseline line) the
  # differential below would have silently measured the wrong number -- the same
  # unanchored-scan fragility this check was written to remove. Take the LAST
  # match, so a summary still wins if such a line is ever added above it.
  $ms = [regex]::Matches($text, '(?m)^\s*(\d+)\s+finding\(s\)\s*$')
  if ($ms.Count -gt 0) { return [int]$ms[$ms.Count - 1].Groups[1].Value }
  return -1
}
# -1 means "no summary line found". Say so out loud: without this, a renderer
# change that drops or reshapes the summary would surface as a confusing
# off-by-one in the differential instead of as "we could not read the count".
Ok "summary line parses in both runs" `
  ((FindingCount $all) -ge 0 -and (FindingCount $dis) -ge 0)
Ok "disabled rule drops finding"  (-not ($dis -match 'used-before-assignment'))
Ok "un-disabled run still has it" ($all -match 'used-before-assignment')
Ok "disable removes exactly one finding" `
  ((FindingCount $all) -ge 1 -and (FindingCount $dis) -eq ((FindingCount $all) - 1))

# 5. baseline round-trip: write, then re-run reports nothing new.
$base = Join-Path $PSScriptRoot 'pipeline.baseline.json'
& $exe lint $fx --write-baseline $base 2>$null | Out-Null
$new = & $exe lint $fx --baseline $base 2>$null | Out-String
# v(ADP3 T3d2): was ($new -match '0 finding') -- the same unanchored-substring
# fragility the :49-51 FindingCount fix already removed two checks above:
# "10 finding(s)" contains the literal substring "0 finding" and would have
# false-passed. Anchored to the summary line the same way.
Ok "baseline suppresses known finding" ((FindingCount $new) -eq 0)

# 6. lint-all --json: stdout is the JSON DOCUMENT and nothing else.
# Regression for docs\INBOX-lint-all-json-stdout-banner.md -- `lint-all` wrote
# "lint-all: scanning N .pas file(s)" to STDOUT ahead of the array, so
# ConvertFrom-Json died on 'l'. Every consumer had to strip lines until the
# first '['. This is the same class as the SARIF check at the top of this file
# (a human line landing inside a machine document), so it is asserted the same
# way: parse the RAW stdout, with no preamble-stripping of any kind. --quiet is
# deliberately NOT passed -- it never covered this line, and a fix that only
# works under --quiet is not a fix.
$scratch6 = Join-Path C:\TEMP 'draglint_pipeline_json'
if (Test-Path $scratch6) { Remove-Item $scratch6 -Recurse -Force }
New-Item -ItemType Directory -Path $scratch6 | Out-Null
Copy-Item $fx (Join-Path $scratch6 'pipeline_fixture.pas') -Force
$db6 = Join-Path $scratch6 'pipeline.sqlite'
& $exe index $scratch6 --db $db6 2>$null | Out-Null
$rawJson = & $exe lint-all --db $db6 --json 2>$null | Out-String
$j6 = $null; try { $j6 = $rawJson | ConvertFrom-Json } catch {}
Ok "lint-all --json stdout parses with no preamble" ($j6 -ne $null)
Ok "lint-all --json stdout starts at the array"     ($rawJson.TrimStart().StartsWith('['))
Ok "lint-all --json stdout has no scanning banner"  (-not ($rawJson -match 'lint-all: scanning'))
# The banner is not deleted, only redirected -- prove it still reaches stderr,
# or the next reader "fixes" this by silencing progress output altogether.
# NB: `2>&1 1>$null` does NOT isolate stderr in PowerShell -- 2>&1 merges the
# streams first, so 1>$null then discards both. Merge, then keep only the
# records that came from stderr (a native command's stderr surfaces as
# ErrorRecord once redirected).
$err6 = ((& $exe lint-all --db $db6 --json 2>&1 |
          Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n")
Ok "lint-all --json banner still goes to stderr"    ($err6 -match 'lint-all: scanning')
Remove-Item $scratch6 -Recurse -Force -ErrorAction SilentlyContinue

Remove-Item $cfg,$cfgD,$base -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "pipeline-tests: $pass pass / $fail fail"
if ($fail -gt 0) { exit 1 } else { exit 0 }
