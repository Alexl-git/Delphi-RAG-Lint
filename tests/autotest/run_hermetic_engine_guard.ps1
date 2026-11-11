<#
  run_hermetic_engine_guard.ps1 -- 152 HG1 static meta-guard (no engine is run).
  A guard that asserts or relies on an ABSENT manifest ("no drag-lint.json", a --db-less run,
  config discovery) is only meaningful when the engine it drives has no drag-lint.json beside it.
  A machine manifest outranks a fixture, so such a guard must call Get-HermeticEngine
  (tests\autotest\lib\HermeticEngine.ps1) on its -Exe, or it passes or turns vacuous for the wrong reason.

  RULE. Every tests\**\run_*.ps1 that (a) takes an -Exe parameter, (b) says "no|without|absent
  ... drag-lint.json|manifest" in its text and (c) does not call Get-HermeticEngine is FLAGGED.
  A flagged guard fails the run unless it is in $Reported below: guards the 152 HG1 lane reviewed that
  build their OWN manifest-less engine copy or otherwise need no conversion, closed by evidence (the
  151 and 152 INT batteries run every guard with a drag-lint.json beside the exe). The list is a
  ratchet: a NEW flagged guard fails until it calls Get-HermeticEngine or is reviewed in.
  POSITIVE CONTROL: a fixture guard with the phrase and without the call must be flagged; one with the call must not.
  Usage: pwsh -File run_hermetic_engine_guard.ps1   (any cwd)
#>
[CmdletBinding()]
param([string]$TestsRoot = (Join-Path $PSScriptRoot '..'))
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
$Reported = @(
  # guards reviewed by HG1, not converted: own engine copy or no -Exe-sensitive manifest premise (see lanes\152\HG1\REPORT.md)
  'run_compare_verb.ps1','run_doc_returns.ps1','run_doc_returns_and_callers.ps1','run_docs_manifest_roundtrip.ps1',
  'run_info_verb.ps1','run_installed_layout_v2_phase2_guard.ps1','run_library_sibling_platform_guard.ps1',
  'run_lintall_infers_project_for_unit_not_in_dpr.ps1','run_lintall_no_library_warning.ps1','run_lintall_unanchored_note.ps1',
  'run_nodb_error_on_stderr.ps1','run_outline_resolves_from_file.ps1','run_project_db_resolve.ps1',
  'run_redundant_cast_multi_library.ps1','run_rename_owners_harness.ps1','run_resolve_dbs_in_uncovered.ps1',
  'run_resolve_dbs_library_contract.ps1','run_starter_manifest.ps1','run_usages_no_db_guard.ps1',
  'run_cli141_followups.ps1','run_context_library_calls.ps1','run_cq_library_defaults.ps1','run_index_all_library_first.ps1',
  'run_index_all_no_prune.ps1','run_installed_layout_v2_guard.ps1','run_lint_library_unit_project_rules_guard.ps1',
  'run_lintall_corrupt_library.ps1','run_lsp_watch_pascal_guard.ps1','run_qcli_142_guard.ps1'
)
$phrase = '(?i)\b(no|without|absent)\b[^\r\n]{0,30}(drag-lint\.json|manifest)'
function Get-FlaggedGuards([string]$Root) {
  $self = 'run_hermetic_engine_guard.ps1'
  foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'run_*.ps1') {
    if ($f.Name -eq $self) { continue }
    $t = [IO.File]::ReadAllText($f.FullName)
    if ($t -notmatch '\[string\]\s*\$Exe\b') { continue }
    if ($t -notmatch $phrase) { continue }
    if ($t -match 'Get-HermeticEngine') { continue }
    $f.Name
  }
}
$flagged = @(Get-FlaggedGuards $TestsRoot)
$new = @($flagged | Where-Object { $Reported -notcontains $_ })
Check 'H1 no unreviewed guard relies on an absent manifest without Get-HermeticEngine' ($new.Count -eq 0) ("flagged-new=[{0}]" -f ($new -join ','))
$stale = @($Reported | Where-Object { $flagged -notcontains $_ })
Check 'H2 every reported guard is still flagged (list stays honest)' ($stale.Count -eq 0) ("no-longer-flagged=[{0}]" -f ($stale -join ','))

# ---- positive control on a fixture tree ------------------------------------------------
$fx = Join-Path ([IO.Path]::GetTempPath()) ("hermetic_guard_fx_$PID")
[void][IO.Directory]::CreateDirectory($fx)
try {
  [IO.File]::WriteAllText("$fx\run_bad.ps1", "param([string]`$Exe = 'x')`r`n# Default -Exe has no drag-lint.json beside it.`r`n")
  [IO.File]::WriteAllText("$fx\run_good.ps1", "param([string]`$Exe = 'x')`r`n# no drag-lint.json`r`n`$Exe = Get-HermeticEngine `$Exe`r`n")
  [IO.File]::WriteAllText("$fx\run_unrelated.ps1", "param([string]`$Exe = 'x')`r`n# plain`r`n")
  $fxFlag = @(Get-FlaggedGuards $fx)
  Check 'P1 POSITIVE CONTROL fixture without the call is flagged' ($fxFlag -contains 'run_bad.ps1')
  Check 'P2 CONTROL fixture with the call / without the phrase is not flagged' (($fxFlag -notcontains 'run_good.ps1') -and ($fxFlag -notcontains 'run_unrelated.ps1'))
} finally { [IO.Directory]::Delete($fx, $true) }

# the five HG1 guards must call it
foreach ($n in 'run_cli_followups_guard','run_explicit_db_strict','run_index_project_nodb_sibling_guard','run_reconcile_backup_name','run_target_compiler_d5') {
  $p = Join-Path $PSScriptRoot "$n.ps1"
  Check "C1 $n calls Get-HermeticEngine" ([IO.File]::ReadAllText($p) -match 'Get-HermeticEngine')
}
Write-Host ("run_hermetic_engine_guard: {0}" -f $(if ($script:Failed) { 'FAIL' } else { 'PASS' }))
exit $(if ($script:Failed) { 1 } else { 0 })
