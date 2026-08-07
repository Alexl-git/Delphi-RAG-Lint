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
    * missing-doc fixable=true    (ADF Task 11c: SINGLE-FIX-ONLY -- its "Fix it"
      inserts a document-qname doc-comment for ONE targeted decl; EXCLUDED from
      the blanket batch. rules --json reports fixable=true so the IDE offers it.)
    * builtin rule count = 112  (= 110 pre-milestone + the 2 doc rules)

  Total-count note (enum-helper-generator milestone, Task 7, 2026-07-07): the
  builtin total below is 113 -- +1 on top of this suite's own 112 baseline --
  because Task 7 added `enum-helper-separate-units` (category=project-wide, NOT
  documentation, so it does not affect the documentation-category assertion
  below). Bumped here deliberately, per this file's own stated purpose of
  "accounting for" catalog additions rather than silently drifting.

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
  Assert 'missing-doc fixable=true (single-fix)'   ($md.fixable -eq $true)
}
if ($null -ne $dd) {
  Assert 'doc-drift source=builtin'              ($dd.source -eq 'builtin')
  Assert 'doc-drift category=documentation'      ($dd.category -eq 'documentation')
  Assert 'doc-drift default_enabled=true (ON)'   ($dd.default_enabled -eq $true)
  Assert 'doc-drift fixable=true'                ($dd.fixable -eq $true)
}

# 2026-08-07: the third documentation built-in gets the same lock as the other
# two, which is this file's whole purpose. severity=hint and default_enabled=true
# are BOTH the user's explicit ruling (the volume was put to them first), so they
# are pinned here rather than left to drift. fixable=false is not a default that
# was skipped: it is report-only by construction -- there is nothing a fix could
# write, since ruling D-3 is precisely that the meaning is not in the code.
$pn = $json.rules | Where-Object { $_.id -eq 'doc-param-no-description' } | Select-Object -First 1
Assert 'doc-param-no-description present'                 ($null -ne $pn)
if ($null -ne $pn) {
  Assert 'doc-param-no-description source=builtin'          ($pn.source -eq 'builtin')
  Assert 'doc-param-no-description category=documentation'  ($pn.category -eq 'documentation')
  Assert 'doc-param-no-description default_enabled=true'    ($pn.default_enabled -eq $true)
  Assert 'doc-param-no-description default_severity=hint'   ($pn.default_severity -eq 'hint')
  Assert 'doc-param-no-description fixable=false'           ($pn.fixable -ne $true)
}

# Built-in count grew by EXACTLY 2 (110 pre-milestone -> 112), then +1 more
# (enum-helper-separate-units, Task 7, 2026-07-07) -> 113. See file header note.
# 2026-08-07: +1 -> 114, and the documentation category goes 2 -> 3, both from
# `doc-param-no-description` (a <param> tag present with an EMPTY body, at `hint`,
# ON by default -- user ruling, see PLAN-autodoc-and-backlog-2026-08-06 A4). This
# assertion going RED when that rule landed is the assertion working: a rule added
# to the catalogue without anyone deciding it belongs there is exactly what it is
# for. Both numbers are bumped together and deliberately.
$builtins = @($json.rules | Where-Object { $_.source -eq 'builtin' })
Assert ("built-in rule count = 114 (pre-milestone 110 + 2 doc rules + enum-helper-separate-units + doc-param-no-description); got {0}" -f $builtins.Count) ($builtins.Count -eq 114)

# The +2 are precisely the two documentation-category built-ins.
$docBuiltins = @($builtins | Where-Object { $_.category -eq 'documentation' })
Assert ("exactly 3 documentation-category built-ins; got {0}" -f $docBuiltins.Count) ($docBuiltins.Count -eq 3)

Write-Host ''
if ($fail -gt 0) { Write-Host "docrules-catalog: $fail FAIL" -ForegroundColor Red; exit 1 } else { Write-Host 'docrules-catalog: all pass' -ForegroundColor Green; exit 0 }
