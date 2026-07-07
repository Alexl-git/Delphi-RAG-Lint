<#
  run_docrules_catalog.ps1 -- ADF Task 9 catalog LOCK for the two documentation
  rules (missing-doc from Task 7, doc-drift from Task 8).

  Locks, against `drag-lint rules --json`, that the milestone shipped BOTH rules
  with the exact flags the design mandates and that they grew the BUILT-IN rule
  count by EXACTLY 2 (pre-milestone builtins = 110, current = 112):
    * both present, source=builtin, category=documentation
    * doc-drift  default_enabled=true   (ON by default -- safe correctness signal)
    * missing-doc default_enabled=false (OFF by default, opt-in -- ADF Task 11b:
      fires 1302x on drag-lint's own first-run wave, too noisy to ship ON)
    * doc-drift  fixable=true     (its --fix repairs the mechanically-safe subset)
    * missing-doc fixable=false   (report-only -- nothing safe to auto-write)
    * builtin rule count = 112  (= 110 pre-milestone + the 2 doc rules)

  If someone flips a default, drops the fixable flag, or adds/removes a built-in
  without accounting for it, this suite fails -- the catalog is pinned.

  Run against the repo rules/ dir so the count is deterministic (scm rules are
  excluded from the built-in tally by filtering source=builtin).
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$exePath = (Resolve-Path $Exe).Path
$rulesDir = Join-Path $repo 'rules'
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

$json = & $exePath rules --json --rules-dir $rulesDir 2>$null | ConvertFrom-Json
Assert 'rules --json has a rules array' ($null -ne $json.rules)

$md = $json.rules | Where-Object { $_.id -eq 'missing-doc' } | Select-Object -First 1
$dd = $json.rules | Where-Object { $_.id -eq 'doc-drift'   } | Select-Object -First 1

Assert 'missing-doc present'                    ($null -ne $md)
Assert 'doc-drift present'                       ($null -ne $dd)
if ($null -ne $md) {
  Assert 'missing-doc source=builtin'              ($md.source -eq 'builtin')
  Assert 'missing-doc category=documentation'      ($md.category -eq 'documentation')
  Assert 'missing-doc default_enabled=false (OFF)' ($md.default_enabled -eq $false)
  Assert 'missing-doc fixable=false'               ($md.fixable -eq $false)
}
if ($null -ne $dd) {
  Assert 'doc-drift source=builtin'              ($dd.source -eq 'builtin')
  Assert 'doc-drift category=documentation'      ($dd.category -eq 'documentation')
  Assert 'doc-drift default_enabled=true (ON)'   ($dd.default_enabled -eq $true)
  Assert 'doc-drift fixable=true'                ($dd.fixable -eq $true)
}

# Built-in count grew by EXACTLY 2 (110 pre-milestone -> 112).
$builtins = @($json.rules | Where-Object { $_.source -eq 'builtin' })
Assert ("built-in rule count = 112 (pre-milestone 110 + 2 doc rules); got {0}" -f $builtins.Count) ($builtins.Count -eq 112)

# The +2 are precisely the two documentation-category built-ins.
$docBuiltins = @($builtins | Where-Object { $_.category -eq 'documentation' })
Assert ("exactly 2 documentation-category built-ins; got {0}" -f $docBuiltins.Count) ($docBuiltins.Count -eq 2)

Write-Host ''
if ($fail -gt 0) { Write-Host "docrules-catalog: $fail FAIL" -ForegroundColor Red; exit 1 } else { Write-Host 'docrules-catalog: all pass' -ForegroundColor Green; exit 0 }
