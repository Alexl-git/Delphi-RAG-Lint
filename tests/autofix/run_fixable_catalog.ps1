[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
Push-Location C:\TEMP
try {
  $json = & $Exe rules --json 2>$null | Out-String
  $obj  = $json | ConvertFrom-Json
  $byId = @{}; foreach($r in $obj.rules){ $byId[$r.id] = $r }
  Check 'self-assignment fixable=true'        ($byId['self-assignment'].fixable -eq $true)
  Check 'redundant-parentheses fixable=true'  ($byId['redundant-parentheses'].fixable -eq $true)
  Check 'redundant-cast fixable=true'         ($byId['redundant-cast'].fixable -eq $true)
  Check 'redundant-not-not fixable=true'       ($byId['redundant-not-not'].fixable -eq $true)
  Check 'redundant-as-tobject fixable=true'    ($byId['redundant-as-tobject'].fixable -eq $true)
  Check 'boolean-comparison-true fixable=true' ($byId['boolean-comparison-true'].fixable -eq $true)
  Check 'reserved-word-casing fixable=true'    ($byId['reserved-word-casing'].fixable -eq $true)
  Check 'redundant-assigned-free fixable=true' ($byId['redundant-assigned-free'].fixable -eq $true)
  Check 'off-by-one-count fixable=true'        ($byId['off-by-one-count'].fixable -eq $true)
  Check 'doc-drift fixable=true'               ($byId['doc-drift'].fixable -eq $true)
  Check 'missing-doc fixable=true'             ($byId['missing-doc'].fixable -eq $true)
  # Batch C / Task 7: naming re-casing rules -- store-backed like doc-drift/
  # missing-doc (no BuildAutofixEdits branch; edits come from BuildNamingFixEdits
  # via the FinalizeAndOutput store-backed append), but still registered fixable
  # in FIXABLE_RULE_IDS so `rules --json`.fixable and the IDE "Fix it" menu agree.
  Check 'method-pascalcase fixable=true'       ($byId['method-pascalcase'].fixable -eq $true)
  Check 'local-var-casing fixable=true'        ($byId['local-var-casing'].fixable -eq $true)
  Check 'const-casing fixable=true'            ($byId['const-casing'].fixable -eq $true)
  # Batch D / Task 3: naming PREFIX-ADDING rules -- same store-backed pattern
  # (BuildNamingFixEdits, extended with SynthesizePrefixedName), no
  # BuildAutofixEdits branch of their own either.
  Check 'field-name-prefix fixable=true'       ($byId['field-name-prefix'].fixable -eq $true)
  Check 'param-name-prefix fixable=true'       ($byId['param-name-prefix'].fixable -eq $true)
  Check 'type-name-prefix fixable=true'        ($byId['type-name-prefix'].fixable -eq $true)
  # v(autofix-compare): the two comparison rules, plus the always-false SPLIT of
  # uppercase-compare. Unlike the naming rules above these are pure-text fixes
  # with their own BuildAutofixEdits branches -- no store needed. They are also
  # the first fixable rules that are EXTERNAL .scm rules rather than built-ins,
  # so this also pins that `rules --json`.fixable reports correctly for those.
  Check 'nil-comparison fixable=true'          ($byId['nil-comparison'].fixable -eq $true)
  Check 'uppercase-compare fixable=true'       ($byId['uppercase-compare'].fixable -eq $true)
  Check 'uppercase-compare-always-false fixable=true' ($byId['uppercase-compare-always-false'].fixable -eq $true)
  # ...and that the always-false split is reported as an ERROR, not a warning:
  # it marks a comparison that can never be true, which is a defect rather than
  # the style nit uppercase-compare reports.
  Check 'uppercase-compare-always-false severity=error' ($byId['uppercase-compare-always-false'].default_severity -eq 'error')
  Check 'unused-local fixable=true'          ($byId['unused-local'].fixable -eq $true)
  # a rule with no fix must be false (pick a stable always-present rule):
  Check 'cyclomatic-complexity fixable=false' ($byId['cyclomatic-complexity'].fixable -eq $false)
  # local-field-prefix became fixable on 2026-08-16: it STRIPS an F prefix off a
  # local, the mirror of the phase-2 prefix-adding rules and the safest rename in
  # the family (a local's scope is one routine body, so no call site can be
  # affected). Guarded by tests\autotest\run_local_field_prefix_autofix.ps1.
  Check 'local-field-prefix fixable=true' ($byId['local-field-prefix'].fixable -eq $true)
  # The COUNT is deliberately pinned, not derived: FIXABLE_RULE_IDS is the single
  # source of truth for both this catalogue flag and what --fix will attempt, so
  # a rule appearing or vanishing from it silently is exactly what this catches.
  # Bump it here, in the same commit that changes the list, and say why: 21 -> 22
  # on 2026-08-16 (+local-field-prefix); 22 -> 23 on 2026-08-31
  # (+raise-bare-exception).
  #
  # raise-bare-exception is STORE-BACKED, like doc-drift and the naming rules:
  # it has no BuildAutofixEdits branch, because the class name it substitutes is
  # read out of the exceptions unit's managed block and a pure-text builder could
  # not know it. Its edits come from BuildExceptionRewriteEdits, appended in
  # FinalizeAndOutput. Guarded by tests/autotest/run_exception_unit_writer.ps1.
  Check 'raise-bare-exception fixable=true' ($byId['raise-bare-exception'].fixable -eq $true)
  $fixableCount = ($obj.rules | Where-Object { $_.fixable -eq $true }).Count
  Check 'exactly 23 fixable rules' ($fixableCount -eq 23) "got $fixableCount"
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
