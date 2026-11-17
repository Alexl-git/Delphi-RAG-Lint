# Runner for lane EXPLAIN (1.52): `drag-lint explain <rule-id>` and multi-word `query --concept`.
#
# Usage: run_v152_EXPLAIN.ps1 -Exe <drag-lint.exe> [-DbPath <project.sqlite>] [-RulesDir <rules folder>]
#   -DbPath       a project index; enables the --concept block (skipped, and said so, without it)
#   -RulesDir defaults to <repo>\rules (so the wiki table rows under <repo>\docs\wiki are found)
#
# Every negative assertion has a positive control (its known-good twin runs first or beside it).
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [string]$DbPath = "",
  [string]$RulesDir = ""
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($RulesDir -eq "") { $RulesDir = Join-Path $repo "rules" }
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
# Runs the exe; returns exit code + stdout + stderr (separate files so neither stream is lost).
function Run([string[]]$argv) {
  $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
  $p = Start-Process -FilePath $Exe -ArgumentList @($argv | ForEach-Object { if ($_ -match "\s") { '"' + $_ + '"' } else { $_ } }) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  $r = [pscustomobject]@{ Code = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
  [IO.File]::Delete($o); [IO.File]::Delete($e)
  $r
}

# 1. known id (builtin rule with a wiki table row): every section, exit 0
$r = Run @("explain", "tls-verification-disabled", "--rules-dir", $RulesDir)
Write-Host "RAW (known id, first 12 lines):"; ($r.Out -split "`r?`n" | Select-Object -First 12) | ForEach-Object { Write-Host "  | $_" }
Assert "known id exits 0 (got $($r.Code))" ($r.Code -eq 0)
foreach ($sec in @("Rule:", "Meaning:", "Why it matters:", "Bad:", "Good:", "Default:", "Fixable:", "Suppress:")) {
  Assert "known id prints section '$sec'" ($r.Out -match ("(?m)^" + [regex]::Escape($sec)))
}
Assert "Why is fed from the wiki row (certificate validation)" ($r.Out -match "certificate validation")
Assert "Suppress shows the dl:ok marker" ($r.Out -match "// dl:ok tls-verification-disabled --")
Assert "Default shows ON" ($r.Out -match "(?m)^Default:\s+ON")

# 2. sidecar rule (message from rules\bare-except.json); positive control for the wiki row: no wiki row -> category sentence
$r2 = Run @("explain", "bare-except", "--rules-dir", $RulesDir)
Assert "sidecar rule exits 0" ($r2.Code -eq 0)
Assert "Meaning is the sidecar message" ($r2.Out -match "catches every exception")
Assert "no wiki row: Why falls back to the category sentence" ($r2.Out -match "(?m)^Why it matters:\s+\S")

# 3. unknown id: exit 2 with nearest ids (positive control: the known id above printed no 'Nearest')
$u = Run @("explain", "bare-excpt", "--rules-dir", $RulesDir)
Assert "unknown id exits 2 (got $($u.Code))" ($u.Code -eq 2)
Assert "unknown id names the nearest id bare-except on stderr" ($u.Err -match "(?m)^\s+bare-except\s*$")
Assert "positive control: a known id prints no 'Nearest ids'" ($r.Err -notmatch "Nearest")

# 4. --json valid; positive control: the object carries the id and the suppress marker
$j = Run @("explain", "tls-verification-disabled", "--json", "--rules-dir", $RulesDir)
$obj = $null
try { $obj = $j.Out | ConvertFrom-Json } catch { $obj = $null }
Assert "--json is one valid JSON object" ($null -ne $obj)
if ($null -ne $obj) {
  Assert "--json id" ($obj.id -eq "tls-verification-disabled")
  Assert "--json carries every fact (meaning, why, default_enabled, fixable, suppress.line_marker)" (($obj.meaning) -and ($obj.why) -and ($obj.default_enabled -eq $true) -and ($null -ne $obj.fixable) -and ($obj.suppress.line_marker -match "dl:ok"))
}
$ju = Run @("explain", "bare-excpt", "--json", "--rules-dir", $RulesDir)
$uobj = $null
try { $uobj = $ju.Out | ConvertFrom-Json } catch { $uobj = $null }
Assert "unknown id --json exits 2 with valid JSON listing nearest" (($ju.Code -eq 2) -and ($null -ne $uobj) -and (@($uobj.nearest) -contains "bare-except"))

# 5. no id: usage, exit 2
$n = Run @("explain", "--rules-dir", $RulesDir)
Assert "no id exits 2 (got $($n.Code))" ($n.Code -eq 2)

# 6. multi-word --concept ranks partial matches (needs -Db)
if ($DbPath -eq "") {
  Write-Host "SKIP  --concept block (no -DbPath)"
} else {
  $c1 = Run @("query", "--concept", "rule catalog", "--db", $DbPath, "--json", "--limit", "5")
  $c1o = $null; try { $c1o = $c1.Out | ConvertFrom-Json } catch { $c1o = $null }
  Assert "positive control: a two-word concept whose words both occur returns rows (count $($c1o.count))" (($c1.Code -eq 0) -and ($c1o.count -ge 1))
  $c2 = Run @("query", "--concept", "rule catalog zzqxjunk", "--db", $DbPath, "--json", "--limit", "5")
  $c2o = $null; try { $c2o = $c2.Out | ConvertFrom-Json } catch { $c2o = $null }
  Write-Host "RAW (concept with one unknown word): code $($c2.Code), first 200 chars: $($c2.Out.Substring(0, [Math]::Min(200, $c2.Out.Length)))"
  Assert "two real words + one word the index lacks still returns ranked rows (count $($c2o.count), code $($c2.Code))" (($c2.Code -eq 0) -and ($c2o.count -ge 1))
  if ($c2o.count -ge 2) {
    $ranks = @($c2o.hits | ForEach-Object { $_.rank })
    $scores = @($c2o.hits | ForEach-Object { [double]$_.score })
    $sorted = $true; for ($i = 1; $i -lt $scores.Count; $i++) { if ($scores[$i] -gt $scores[$i - 1]) { $sorted = $false } }
    Assert "rows are ranked 1..n with non-increasing score" (($ranks[0] -eq 1) -and $sorted)
  }
}
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host "ALL PASS"
