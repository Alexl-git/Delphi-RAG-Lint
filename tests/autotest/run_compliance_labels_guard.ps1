<#
  run_compliance_labels_guard.ps1 -- guard for the compliance labels (rules\compliance.json).
  Plan: docs\superpowers\plans\2026-10-27-rule-gaps-and-compliance-plan.md section 4.1.4,
  items 1-7 (6-7 = SARIF taxonomies and the built-in profile cwe, added by lane K2).

  Every check runs against the exe passed as -Exe and the rules\ of THIS tree
  (--rules-dir), so a stale deployed exe or a stale <exe-dir>\rules cannot fool it.

  1. every id in `rules --json` has an entry in compliance.json (except $Pending, the ids
     INT adds with their lane) and every entry names an existing id; keys sorted ordinally;
  2. id formats; no duplicate inside a list; `weak` is a subset of the entry own ids;
  3. positive controls: hardcoded-credential carries CWE-798, used-before-assignment carries
     EXP33-C, type-name-prefix carries nothing -- read back through `rules --json`;
  4. negative control: a temp copy of the rules dir whose compliance.json has a bogus id makes
     `rules --json` exit non-zero;
  5. `lint --json` finding of hardcoded-credential has compliance.cwe containing CWE-798 and a
     type-name-prefix finding has no `compliance` key;
  6. `--format sarif` on hardcoded-credential.pas: tag external/cwe/cwe-798, a taxonomies entry named CWE,
     a relationship targeting 798;
  7. `--profile cwe`: 0 findings on type-name-prefix.pas, >= 1 at >= warning on hardcoded-credential.pas.
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exe = (Resolve-Path $Exe).Path
$rulesDir = Join-Path $repo "rules"
$labelFile = Join-Path $rulesDir "compliance.json"
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

# Ids whose compliance row INT adds when their lane merges (plan section 5 rows marked NEW).
# INT removes an id from this list in the same change that adds its row.
$Pending = @()

$rulesJson = & $exe rules --json --rules-dir $rulesDir 2>$null
Assert "rules --json exits 0" ($LASTEXITCODE -eq 0)
$cat = ($rulesJson -join "`n") | ConvertFrom-Json
$ids = @($cat.rules | ForEach-Object { $_.id })

# ---- item 1: completeness, both directions ------------------------------------------------
Assert "compliance.json exists" (Test-Path $labelFile)
$labels = $null
if (Test-Path $labelFile) { $labels = Get-Content $labelFile -Raw | ConvertFrom-Json }
$keys = @(); if ($labels) { $keys = @($labels.PSObject.Properties.Name) }
$missing = @($ids | Where-Object { ($keys -notcontains $_) -and ($Pending -notcontains $_) })
$extra   = @($keys | Where-Object { ($ids -notcontains $_) -and ($Pending -notcontains $_) })
Assert "every catalog rule has a compliance.json entry (missing: $($missing.Count))" ($keys.Count -gt 0 -and $missing.Count -eq 0)
Assert "every compliance.json entry names an existing rule (extra: $($extra.Count))" ($keys.Count -gt 0 -and $extra.Count -eq 0)
$sorted = [string[]]$keys.Clone()
[Array]::Sort($sorted, [StringComparer]::Ordinal)
Assert "compliance.json keys are sorted (ordinal)" ($keys.Count -gt 0 -and (($sorted -join "`n") -ceq ($keys -join "`n")))

# ---- item 2: formats ----------------------------------------------------------------------
$reCwe   = '^CWE-\d+$'
$reCert  = '^[A-Z]{3}\d{2}-(C|CPP|J)$'
$reMisra = '^MISRA-(C-2012-(R\d+\.\d+|D\d+\.\d+)|CPP-2008-\d+-\d+-\d+|CPP-2023-\d+\.\d+\.\d+)$'
$badFmt = 0; $dup = 0; $badWeak = 0
foreach ($k in $keys) {
  $e = $labels.$k
  $own = @()
  foreach ($p in @(@('cwe', $reCwe), @('cert', $reCert), @('misra', $reMisra))) {
    $list = @($e.($p[0]) | Where-Object { $_ })
    if (($list | Select-Object -Unique).Count -ne $list.Count) { $dup++ }
    foreach ($x in $list) { if ($x -notmatch $p[1]) { $badFmt++ } }
    $own += $list
  }
  foreach ($w in @($e.weak | Where-Object { $_ })) { if ($own -notcontains $w) { $badWeak++ } }
}
Assert "all ids match their format (bad: $badFmt)" ($keys.Count -gt 0 -and $badFmt -eq 0)
Assert "no duplicate id inside a list (dups: $dup)" ($keys.Count -gt 0 -and $dup -eq 0)
Assert "weak is a subset of the entry own ids (bad: $badWeak)" ($keys.Count -gt 0 -and $badWeak -eq 0)

# ---- item 3: positive controls through `rules --json` --------------------------------------
function RuleOf($id) { $cat.rules | Where-Object { $_.id -eq $id } | Select-Object -First 1 }
$hc = RuleOf 'hardcoded-credential'; $ub = RuleOf 'used-before-assignment'; $tp = RuleOf 'type-name-prefix'
Assert "rules --json: every rule has a compliance object" (@($cat.rules | Where-Object { $null -eq $_.compliance }).Count -eq 0)
Assert "hardcoded-credential carries CWE-798" ($null -ne $hc -and $null -ne $hc.compliance -and @($hc.compliance.cwe) -contains 'CWE-798')
Assert "used-before-assignment carries EXP33-C" ($null -ne $ub -and $null -ne $ub.compliance -and @($ub.compliance.cert) -contains 'EXP33-C')
Assert "type-name-prefix carries nothing" ($null -ne $tp -and $null -ne $tp.compliance -and (@($tp.compliance.cwe) + @($tp.compliance.cert) + @($tp.compliance.misra)).Count -eq 0)

# ---- item 4: negative control ---------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("compl-guard-" + [Guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path $tmp | Out-Null
  Copy-Item (Join-Path $rulesDir '*') $tmp -Recurse
  $orig = Get-Content $labelFile -Raw
  $bad = $orig -replace '"hardcoded-credential": \{"cwe": \[', '"hardcoded-credential": {"cwe": ["NOT-AN-ID", '
  Assert "negative control mutation changed the file" ($bad -ne $orig)
  [IO.File]::WriteAllText((Join-Path $tmp 'compliance.json'), $bad)
  & $exe rules --json --rules-dir $tmp 2>$null | Out-Null
  Assert "bogus id in compliance.json makes rules --json exit non-zero" ($LASTEXITCODE -ne 0)
  & $exe rules --json --rules-dir $rulesDir 2>$null | Out-Null
  Assert "same exe, real compliance.json: exit 0 (control is not vacuous)" ($LASTEXITCODE -eq 0)
} finally {
  [IO.Directory]::Delete($tmp, $true)
}

# ---- item 5: lint --json carries the labels -------------------------------------------------
$f1 = & $exe lint --json --rules-dir $rulesDir (Join-Path $repo 'tests\lint\hardcoded-credential.pas') 2>$null
$a1 = @(($f1 -join "`n") | ConvertFrom-Json | Where-Object { $_.rule -eq 'hardcoded-credential' })
Assert "lint --json: hardcoded-credential finding exists" ($a1.Count -ge 1)
Assert "lint --json: hardcoded-credential finding has compliance.cwe containing CWE-798" ($a1.Count -ge 1 -and @($a1[0].compliance.cwe) -contains 'CWE-798')
$f2 = & $exe lint --json --rules-dir $rulesDir (Join-Path $repo 'tests\lint\type-name-prefix.pas') 2>$null
$a2 = @(($f2 -join "`n") | ConvertFrom-Json | Where-Object { $_.rule -eq 'type-name-prefix' })
Assert "lint --json: type-name-prefix finding exists" ($a2.Count -ge 1)
Assert "lint --json: type-name-prefix finding has no compliance key" ($a2.Count -ge 1 -and $null -eq $a2[0].PSObject.Properties['compliance'])

# ---- item 6: --format sarif carries the taxonomies -----------------------------------------
$sarifTxt = (& $exe lint --format sarif --rules-dir $rulesDir (Join-Path $repo 'tests\lint\hardcoded-credential.pas') 2>$null) -join "`n"
$sj = $null; try { $sj = $sarifTxt | ConvertFrom-Json } catch {}
Assert "sarif: parses" ($null -ne $sj)
Assert "sarif: tags contain external/cwe/cwe-798" ($sarifTxt -match '"external/cwe/cwe-798"')
$tax = $null; if ($sj) { $tax = @($sj.runs[0].taxonomies) }
Assert "sarif: taxonomies array has name CWE" ($null -ne $tax -and @($tax | Where-Object { $_.name -eq 'CWE' }).Count -eq 1)
$hcRule = $null; if ($sj) { $hcRule = @($sj.runs[0].tool.driver.rules | Where-Object { $_.id -eq 'hardcoded-credential' })[0] }
Assert "sarif: hardcoded-credential has a relationship targeting 798" ($null -ne $hcRule -and @($hcRule.relationships | Where-Object { $_.target.id -eq '798' -and $_.target.toolComponent.name -eq 'CWE' }).Count -ge 1)

# ---- item 7: built-in profile `cwe` ----------------------------------------------------------
$p1 = & $exe lint --json --profile cwe --rules-dir $rulesDir (Join-Path $repo 'tests\lint\type-name-prefix.pas') 2>$null
$n1 = @(($p1 -join "`n") | ConvertFrom-Json).Count
Assert "--profile cwe on type-name-prefix.pas: 0 findings (got $n1)" ($n1 -eq 0)
$p2 = & $exe lint --json --profile cwe --rules-dir $rulesDir (Join-Path $repo 'tests\lint\hardcoded-credential.pas') 2>$null
$h2 = @(($p2 -join "`n") | ConvertFrom-Json | Where-Object { $_.rule -eq 'hardcoded-credential' -and $_.severity -in @('warning','error') })
Assert "--profile cwe on hardcoded-credential.pas: >= 1 finding at >= warning (got $($h2.Count))" ($h2.Count -ge 1)

Write-Host ""
if ($fail -gt 0) { Write-Host "$fail check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host "compliance labels guard: all checks passed"
exit 0
