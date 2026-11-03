<#
  run_exe_start_hint_guard.ps1 -- lane CLIFIX C2 (#17). Every guard whose fixture index can come
  back empty must say WHY when the exe never started (0xC000007B, companion DLLs missing) instead
  of only "index produced no DB". Positive control: each listed guard is run against a COPY of the
  exe with NO DLLs beside it and must print the hint; negative control: the same guard against
  the intact exe prints no hint. Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-exehint-$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null
$bare = Join-Path $WorkDir 'bare'
New-Item -ItemType Directory -Path $bare | Out-Null
Copy-Item $Exe (Join-Path $bare 'drag-lint.exe') -Force   # deliberately NO dlls beside it
$bareExe = Join-Path $bare 'drag-lint.exe'

foreach ($g in 'run_find_callers_callback_reach', 'run_generate_test_stub_guard', 'run_hover_bundle_guard',
               'run_lint_project_scope_active_config_guard', 'run_query_callers_shared_guard', 'run_text_query_adhoc_db',
               'run_resolution_kind', 'run_lsp_full_rules_guard', 'run_schema', 'run_lsp_remove_unused_imports_code_action_guard',
               'run_lintall_json_stdout_clean', 'run_json_stdout_parses_on_stale_index', 'run_lsp_missing_uses_code_action_guard',
               'run_busy_beat_guard', 'run_config_defaults_source_named', 'run_config_rule_key_scope',
               'run_context_type_surface', 'run_convert_apply_backup_set', 'run_dpr_uses_ignores_comments',
               'run_enum_bare_read_scoped', 'run_enum_read_inside_with', 'run_enum_scoped_decline',
               'run_exception_class_naming', 'run_exception_unit_writer', 'run_implicit_self_inherited_cross_unit',
               'run_index_halfread_guard', 'run_lint_duplicate_global_decl', 'run_lint_global_only_uses_edge',
               'run_lint_rule_narrows_checkers', 'run_lint_uses_global_census', 'run_lint_walk_scope_guard',
               'run_lintall_infers_project_for_unit_not_in_dpr', 'run_lintall_rule_enables', 'run_lsp_c15_server_fixes_guard',
               'run_lsp_c9_preprocess_guard', 'run_lsp_loose_open_scaling_guard', 'run_lsp_semantic_tokens_guard',
               'run_lsp_semantic_tokens_lone_cr_guard', 'run_menu_drift_app', 'run_menu_tree_dxbar',
               'run_menu_tree_guard', 'run_menu_tree_tests', 'run_ownroots_default_note',
               'run_repo_ownroots_tracked', 'run_serve_multidb_warning_guard', 'run_unit_missing_from_uses',
               'run_unit_usage_degrades', 'run_unused_unit_enum_values', 'run_unused_unit_helpers',
               'run_usages_field_access', 'run_wiki_blocks', 'run_with_hiding_rule') {
  $out = (& pwsh -NoProfile -File (Join-Path $PSScriptRoot "$g.ps1") -Exe $bareExe -WorkDir (Join-Path $WorkDir $g) 2>&1 | ForEach-Object { "$_" }) -join "`n"
  Check "$g names 0xC000007B when the exe cannot start" ($out -match '0xC000007B') (($out -split "`n" | Select-Object -First 2) -join ' | ')
}
Check 'helper: ordinary exit code gives no hint (negative control)' ((Get-ExeStartFailureHint 1) -eq '')
if ($script:Failed) { Write-Host 'run_exe_start_hint_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_exe_start_hint_guard: PASS' -ForegroundColor Green
exit 0
