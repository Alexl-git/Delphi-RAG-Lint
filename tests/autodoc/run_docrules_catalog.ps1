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
  # RAISED hint -> warning by user ruling 2026-08-09 ("If method has params and
  # they are not documented it should be reported as warning"), superseding the
  # hint chosen on 2026-08-07. Still pinned here rather than left to drift.
  Assert 'doc-param-no-description default_severity=warning' ($pn.default_severity -eq 'warning')
  Assert 'doc-param-no-description fixable=false'           ($pn.fixable -ne $true)
}

# 2026-08-09, same ruling: "If method doesn't have params and they are reported
# then it is an error." Its own id rather than a doc-drift special case, because
# one id cannot carry two severities without this catalogue lying about it.
$pns = $json.rules | Where-Object { $_.id -eq 'doc-param-not-in-signature' } | Select-Object -First 1
Assert 'doc-param-not-in-signature present'                ($null -ne $pns)
if ($null -ne $pns) {
  Assert 'doc-param-not-in-signature source=builtin'         ($pns.source -eq 'builtin')
  Assert 'doc-param-not-in-signature category=documentation' ($pns.category -eq 'documentation')
  Assert 'doc-param-not-in-signature default_enabled=true'   ($pns.default_enabled -eq $true)
  Assert 'doc-param-not-in-signature default_severity=error' ($pns.default_severity -eq 'error')
}

# Built-in count grew by EXACTLY 2 (110 pre-milestone -> 112), then +1 more
# (enum-helper-separate-units, Task 7, 2026-07-07) -> 113. See file header note.
# 2026-08-07: +1 -> 114, and the documentation category goes 2 -> 3, both from
# `doc-param-no-description` (a <param> tag present with an EMPTY body, at `hint`,
# ON by default -- user ruling, see PLAN-autodoc-and-backlog-2026-08-06 A4). This
# assertion going RED when that rule landed is the assertion working: a rule added
# to the catalogue without anyone deciding it belongs there is exactly what it is
# for. Both numbers are bumped together and deliberately.
# 2026-08-09: +1 -> 115, documentation 3 -> 4, from `doc-param-not-in-signature`
# (user ruling; see the block above). Bumped deliberately, together, for the same
# reason the 2026-08-07 bump was: a rule reaching the catalogue without anyone
# deciding it belongs there is exactly what these two numbers exist to catch.
$builtins = @($json.rules | Where-Object { $_.source -eq 'builtin' })
# 2026-08-12: +1 -> 116, and the naming category goes 9 -> 10, from
# `local-field-prefix` ("Local variable wears the field/param prefix"), added by
# 3fdefd9 on main when the naming rules were split. Verified against the catalog
# before matching the number: the delta is exactly that one id, and the
# documentation category is unchanged at 4.
# 2026-08-12 (b): +2 -> 118, from the dl:ok reviewed-marker landing:
# `review-marker-stale` and `review-marker-unused`, both category `review-markers`,
# both hint, both ON. They are meta-rules ABOUT the suppression mechanism, emitted
# by the central marker filter rather than by any checker. This assertion caught
# them on the first battery run after the change -- which is the tripwire doing its
# job, so it is bumped deliberately rather than loosened. Verified the delta is
# exactly those two ids and that `documentation` is still 4.
# 2026-08-14: +1 -> 119, documentation 4 -> 5, from `doc-orphan-block` (a managed
# facts block attached to no declaration). Both numbers bumped together and
# deliberately, and this tripwire caught it on the first battery run after the
# change -- which is the tripwire working, not a nuisance.
#
# Worth recording WHY this rule had to exist, because the obvious question is why
# doc-drift did not already cover it: doc-drift walks SYMBOLS, and an orphan block
# belongs to no symbol -- that is what makes it an orphan -- so it is invisible to
# doc-drift by construction, and so was every convergence gate built on doc-drift.
# Measured 2026-08-14: three YADF projects all reported "nothing to document" over
# source that already carried a stacked pair. Hence a FILE-level scan, and hence a
# fifth documentation-category rule rather than another doc-drift signal.
Assert ("built-in rule count = 119 (118 + doc-orphan-block); got {0}" -f $builtins.Count) ($builtins.Count -eq 119)

$docBuiltins = @($builtins | Where-Object { $_.category -eq 'documentation' })
Assert ("exactly 5 documentation-category built-ins; got {0}" -f $docBuiltins.Count) ($docBuiltins.Count -eq 5)

Write-Host ''
if ($fail -gt 0) { Write-Host "docrules-catalog: $fail FAIL" -ForegroundColor Red; exit 1 } else { Write-Host 'docrules-catalog: all pass' -ForegroundColor Green; exit 0 }
