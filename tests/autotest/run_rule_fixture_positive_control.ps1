<#
  run_rule_fixture_positive_control.ps1 -- A6: every rule needs a fixture that can FAIL.

  A rule with no tests\lint fixture that shows BOTH a hit (`<id> <line>`) and a
  non-hit (`!<id>` / `!<id> <line>`) can regress to "never fires" or "always
  fires" with every test green (feedback: every guard needs a positive control).
  This guard walks `rules --json` and demands, per rule id, >= 1 hit directive and
  >= 1 negative directive across tests\lint\*.expected.

  Three lists, each with a different contract:
    $Allowlist -- ids that legitimately cannot be a tests\lint per-file fixture
                  (project-wide / store-only rules tested by their own autotest
                  runner) OR parked gaps that existed on 2026-10-27. A listed id that
                  now HAS a hit+non-hit fixture is a FAIL ("remove it"): the list
                  may only shrink.
    $Pending   -- the 43 ids of the clippy-parity wave (plan
                  docs\superpowers\plans\2026-10-27-clippy-rules-plan.md). Each lane
                  adds its fixtures; integration step 4 EMPTIES this list. A pending
                  id that already has fixtures only warns, so lanes may merge first.
  Positive control: a fabricated id with no fixture is run through the same
  predicate and MUST be rejected; if it is not, the guard itself is broken.

  Usage: pwsh -File tests\autotest\run_rule_fixture_positive_control.ps1 [-Exe path\to\drag-lint.exe]
#>
[CmdletBinding()]
param([string]$Exe = 'third_party\dll-win64\drag-lint.exe')
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $Repo
$exePath = (Resolve-Path $Exe).Path
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name $Detail" -ForegroundColor Red; $script:Failed = $true }
}

# Parked gaps measured 2026-10-27 (L0): ids with no hit+non-hit pair in tests\lint\*.expected. Project-wide / store-only
# rules are covered by their own tests\autotest\run_*.ps1 runner; the rest are legacy gaps owed a fixture. The list may only
# shrink (P4 fails an entry that gained a fixture).
$Allowlist = @(
    'abstract-method-instantiation', 'assert-with-side-effect', 'boolean-comparison-true',
    'case-magic-numbers', 'circular-uses', 'classname-string-compare',
    'confusable-identifier', 'const-casing', 'cycle-participant-unit', 'deep-inheritance',
    'deep-nesting', 'dependent-project-not-recompiled', 'deprecated-rtl-function',
    'dfm-event-handler-missing', 'dfm-password-edit-unmasked', 'dfm-property-not-declared',
    'discarded-effect-free-result', 'doc-drift', 'doc-orphan-block',
    'doc-param-no-description', 'doc-param-not-in-signature', 'duplicate-global-decl',
    'empty-procedure-body', 'enum-bare-read-scoped', 'enum-helper-separate-units',
    'enum-ordinal-persisted', 'enum-read-inside-with', 'fan-in', 'fan-out', 'feature-envy',
    'global-form-variable', 'global-only-uses-edge', 'god-class', 'goto-statement', 'high-coupling',
    'high-response', 'ifdef-undefined-symbol', 'inline-assembly',
    'inline-comment-in-multiline-args', 'instability', 'interface-reference-cycle',
    'layering-violation', 'line-too-long', 'local-field-prefix', 'low-cohesion', 'method-too-long',
    'middle-man', 'missing-doc', 'nested-with', 'outputdebugstring', 'parser-error',
    'platform-divergent-define', 'query-name-with-effect',
    'repeated-type-switch', 'review-marker-malformed', 'review-marker-placeholder-hash',
    'review-marker-reason-unreviewed', 'review-marker-stale', 'review-marker-unused',
    'stat-gated-destructive', 'too-many-children', 'too-many-locals', 'unbalanced-begin-end',
    'unit-not-in-dpr', 'unit-not-in-library', 'unit-too-large', 'unsafe-string-api', 'unused-local',
    'unused-private-member', 'unused-public-symbol', 'unused-unit-in-uses', 'uses-movable-to-implementation',
    'virtual-never-overridden',
    'used-unit-not-resolvable', 'uses-global-census', 'with-hides-outer-symbol', 'with-statement',
    'writeln-in-source'
)
# Store-backed / project-wide ids whose fixtures live in their own runner, not in tests\lint (added by INT lane IPC):
#   taint-*                       -> tests\autotest\run_taint_rules.ps1 + run_taint_library.ps1 (tests\lint-project\taint*)
#   duplicate-unit-on-search-path -> tests\autotest\run_duplicate_unit_on_search_path.ps1
#   pp-unresolved-if              -> tests\autotest\run_index_pp_consts.ps1
$Allowlist += @('taint-sql-injection', 'taint-command-injection', 'taint-path-traversal',
    'duplicate-unit-on-search-path', 'pp-unresolved-if')
# unused-enum-value -> tests\lint-project\unused-enum-value\run_unused_enum_value.ps1 (project rule, lane B-ENUM)
$Allowlist += @('unused-enum-value')
#   side-effect-in-short-circuit, property-getter-with-effect, ui-access-in-thread-transitive
#     -> tests\lint-project\effect-rules\run_effect_rules.ps1 (lane B-EFFECT, 1.37.0)
$Allowlist += @('side-effect-in-short-circuit', 'property-getter-with-effect', 'ui-access-in-thread-transitive')
# The clippy-parity wave is fully fixtured (tests\lint) and integrated; the list is kept empty so a future wave can reuse it.
$Pending = @()

# --- collect directives from every fixture ---
$hits = @{}; $negs = @{}
foreach ($f in Get-ChildItem (Join-Path $Repo 'tests\lint') -Filter '*.expected') {
  foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
    $l = $line.Trim()
    if ($l -eq '' -or $l.StartsWith('#') -or $l -eq 'none') { continue }
    if ($l.StartsWith('!')) {
      $id = ($l.Substring(1) -split '\s+')[0]
      $negs[$id] = 1 + [int]$negs[$id]
    } else {
      $parts = $l -split '\s+'
      if ($parts.Count -ge 2 -and $parts[1] -match '^\d+$') { $hits[$parts[0]] = 1 + [int]$hits[$parts[0]] }
    }
  }
}
function HasFixture([string]$Id) { return (([int]$hits[$Id]) -ge 1) -and (([int]$negs[$Id]) -ge 1) }

$ids = @((& $exePath rules --json --rules-dir (Join-Path $Repo 'rules') 2>$null | Out-String | ConvertFrom-Json).rules | ForEach-Object { $_.id })
Check 'P0 CONTROL: rule catalogue parsed' ($ids.Count -gt 100) "($($ids.Count) id(s))"
Check 'P0 CONTROL: fixtures parsed' ($hits.Count -gt 50) "($($hits.Count) id(s) with hits)"

# positive control: the predicate must reject an id that has no fixture
$fake = 'zz-fake-rule-without-fixture'
Check 'P1 POSITIVE CONTROL: a fake id without a fixture is rejected' (-not (HasFixture $fake)) 'the predicate accepts everything -- the guard is vacuous'
Check 'P1 POSITIVE CONTROL: a fake id is neither allowlisted nor pending' (($Allowlist -notcontains $fake) -and ($Pending -notcontains $fake)) ''
$ctlOk = $true
foreach ($id in $ids) {
  if (HasFixture $id) { continue }
  if (($Allowlist -contains $id) -or ($Pending -contains $id)) { continue }
  $ctlOk = $false
}
# the fake id, appended to the catalogue, MUST make the main loop fail
$withFake = @($ids) + $fake
$fakeFlagged = @($withFake | Where-Object { -not (HasFixture $_) -and ($Allowlist -notcontains $_) -and ($Pending -notcontains $_) }) -contains $fake
Check 'P2 POSITIVE CONTROL: the loop flags a fake catalogue id' $fakeFlagged ''

$missing = @($ids | Where-Object { -not (HasFixture $_) -and ($Allowlist -notcontains $_) -and ($Pending -notcontains $_) })
Check 'P3 every rule has a fixture with >= 1 hit and >= 1 non-hit (or is allowlisted/pending)' ($missing.Count -eq 0) ("no fixture: " + ($missing -join ' '))

$stale = @($Allowlist | Where-Object { HasFixture $_ })
Check 'P4 no allowlisted id has a fixture any more (the list only shrinks)' ($stale.Count -eq 0) ("remove from allowlist: " + ($stale -join ' '))
$ghost = @($Allowlist | Where-Object { $ids -notcontains $_ })
Check 'P5 every allowlisted id is a real catalogue rule' ($ghost.Count -eq 0) ("not in rules --json: " + ($ghost -join ' '))
$done = @($Pending | Where-Object { HasFixture $_ })
if ($done.Count -gt 0) { Write-Host ("WARN  pending ids already fixtured (integration step 4 removes them): " + ($done -join ' ')) -ForegroundColor Yellow }
Write-Host ("INFO  catalogue={0} allowlisted={1} pending={2} (still unfixtured: {3})" -f $ids.Count, $Allowlist.Count, $Pending.Count, ($Pending.Count - $done.Count))

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
