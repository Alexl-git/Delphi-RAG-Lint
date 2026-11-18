# Guard for the wave v152 scaffold (lane FRAME, 1.52.0-alpha).
#
# What it pins:
#   1. the catalog counts (`rules --json`): total, fixable, default-on. With every
#      v152 lane unit empty they equal the 1.51.1 numbers (423 / 125 / 341); INT
#      raises the three defaults below when it merges rule lanes.
#   2. every scaffold unit exists and is listed in BOTH drag-lint.dpr and .dproj
#      (a unit in only one of them compiles in one build and not the other).
#   3. (F2) the v152 lanes are registered in the ONE provider mechanism
#      (DRagLint.V151.Dispatch): each TV152<ID>Rules appears in BuildLanes with all
#      five entry points; no second dispatcher exists.
#   4. (F2) CLI.pas: one dispatch line per new verb calling its own unit
#      (check-init, repo, explain, rules disable / enable).
#   5. (F2) the section-5 config keys are read by DRagLint.Lint.Config.
# Positive control (recorded in the v152 ledger, not committed): a probe rule
# declared in a v152 lane Catalog in a scratch build makes check 1 fail with 424.
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe",
  [string]$Repo = "",
  [int]$ExpectTotal = 435,   # INT: +2 unconnected-control, hanging-handler (UNCONN, ON), +1 unit-used-by-no-unit (PROJ2, ON), +2 doc-placeholder (ON) + doc-malformed-summary (OFF) (DOCPOL), +1 extract-constant (XCONST, OFF, fixable; magic-literal family +3 fixable), +1 rule-skipped-budget (BUDGET, ON), +2 ATLA rules (ON), +1 member-could-be-private (ATLB, OFF), +1 index-possibly-out-of-range (IDXRANGE2), +1 review-marker-remeasured (MARK)
  [int]$ExpectFixable = 131,   # +1 parameter-type-too-wide (PTW)
  [int]$ExpectOn = 354   # 1.52: +1 parameter-type-too-wide ON (PTW); +2 UNCONN ON; +1 unit-used-by-no-unit ON; +1 doc-placeholder ON; +1 rule-skipped-budget ON; +2 ATLA ON; index-possibly-out-of-range OFF (FP gate), review-marker-remeasured ON; +4 DEFAULTS (3 lint + datamodule-form-global)
)
$ErrorActionPreference = "Stop"
$repo = if ($Repo -ne "") { (Resolve-Path $Repo).Path } else { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$exe = (Resolve-Path $Exe).Path
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
function Src($rel) { [IO.File]::ReadAllText((Join-Path $repo $rel)) }

# 1. counts
$raw = & $exe rules --json --rules-dir rules 2>$null
$json = ($raw -join "`n") | ConvertFrom-Json
$total = [int]$json.summary.total
$fixable = @($json.rules | Where-Object { $_.fixable }).Count
$on = @($json.rules | Where-Object { $_.default_enabled }).Count
Assert "rules total = $ExpectTotal (got $total)" ($total -eq $ExpectTotal)
Assert "rules fixable = $ExpectFixable (got $fixable)" ($fixable -eq $ExpectFixable)
Assert "rules default-on = $ExpectOn (got $on)" ($on -eq $ExpectOn)
$dups = @($json.rules | Group-Object id | Where-Object { $_.Count -gt 1 })
Assert "no duplicate rule id in the catalog" ($dups.Count -eq 0)

# 2. units in dpr and dproj
$lanes = 'UNCONN','DOCPOL','XCONST','PTW','PROJ2','APP2','ATLA','ATLB','RTTI5','FPS','DEFAULTS'
$units = @()
foreach ($l in $lanes) {
  $units += "lint\v152\DRagLint.V152.$l.pas"
  $units += "lint\v152\DRagLint.V152.$l.Support.pas"
  $units += "lint\fixers\DRagLint.Fix.V152.$l.pas"
}
foreach ($s in '','.Types','.Render','.Roots','.Events','.Intra','.Fields','.Receiver','.Handlers') { $units += "query\DRagLint.Query.HappensBefore$s.pas" }
foreach ($s in 'Schema','FbImport','TextBackup','SchemaSeed','FbTypes','CsvMemTable','ParamArray','OrmGen','DataServiceGen') { $units += "sql\DRagLint.FieldRepo.$s.pas" }
$cliUnits = 'CheckInit','Repo','Explain','RuleScope'
$dpr = Src 'src\cli\drag-lint.dpr'
$dproj = Src 'src\cli\drag-lint.dproj'
$missing = @()
foreach ($u in $units) {
  $rel = '..\' + $u
  if (-not (Test-Path (Join-Path $repo ('src\' + $u)))) { $missing += "file:$u" }
  if (-not $dpr.Contains("'$rel'")) { $missing += "dpr:$u" }
  if (-not $dproj.Contains("Include=""$rel""")) { $missing += "dproj:$u" }
}
foreach ($c in $cliUnits) {
  $f = "DRagLint.CLI.$c.pas"
  if (-not (Test-Path (Join-Path $repo "src\cli\$f"))) { $missing += "file:$f" }
  if (-not $dpr.Contains("'$f'")) { $missing += "dpr:$f" }
  if (-not $dproj.Contains("Include=""$f""")) { $missing += "dproj:$f" }
}
Assert "all $($units.Count + $cliUnits.Count) v152 scaffold units exist and are in dpr + dproj ($($missing -join ', '))" ($missing.Count -eq 0)

# 3. (F2) one provider mechanism: the v152 lanes sit in V151.Dispatch's BuildLanes
$disp = Src 'src\lint\v151\DRagLint.V151.Dispatch.pas'
$notWired = @()
foreach ($l in $lanes) {
  $c = "TV152${l}Rules"
  $row = "Lane('$l',"
  $hooks = "$c.Catalog, $c.CheckFile, $c.CheckDfm, $c.CheckRawBytes, $c.CheckProject)"
  if (-not ($disp.Contains($row) -and $disp.Contains($hooks) -and $disp -match "DRagLint\.V152\.$l\b")) { $notWired += $l }
}
Assert "every v152 lane is a BuildLanes row of V151.Dispatch with its five hooks ($($notWired -join ', '))" ($notWired.Count -eq 0)
$provCalls = @(Get-ChildItem (Join-Path $repo 'src') -Recurse -Filter *.pas | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'RegisterProviderRules\(' -and $_.Name -ne 'DRagLint.Lint.RuleCatalog.pas' })
Assert "RegisterProviderRules is called from ONE unit, V151.Dispatch (got: $(($provCalls | ForEach-Object Name) -join ', '))" (($provCalls.Count -eq 1) -and ($provCalls[0].Name -eq 'DRagLint.V151.Dispatch.pas'))

# 4. (F2) CLI.pas: one dispatch line per new verb, each calling its own unit
$cli = Src 'src\cli\DRagLint.CLI.pas'
$verbs = [ordered]@{
  "Args.Command = 'check-init'" = 'RunCheckInit('
  "Args.Command = 'repo'"       = 'RunRepoVerb('
  "Args.Command = 'explain'"    = 'RunExplain('
  "(Args.Command = 'rules') and MatchText(Args.SubCommand, ['disable', 'enable'])" = 'RunRuleScope('
}
foreach ($k in $verbs.Keys) {
  $hits = @($cli -split "`r?`n" | Where-Object { $_.Contains($k) -and $_.Contains($verbs[$k]) })
  Assert "CLI dispatch: $k -> $($verbs[$k]) on exactly one line (got $($hits.Count))" ($hits.Count -eq 1)
}
$ruleScopeIdx = $cli.IndexOf('RunRuleScope(LowerCase(Args.SubCommand)')
$doRulesIdx = $cli.IndexOf("Args.Command = 'rules'             then Result:= DoRules")
Assert "rules disable/enable is dispatched BEFORE the plain rules verb" (($ruleScopeIdx -gt 0) -and ($doRulesIdx -gt $ruleScopeIdx))
foreach ($flag in '--at','--explain','--max-routines','--repo','--replace','--reason') {
  Assert "ParseArgs knows $flag" ($cli.Contains("A = '$flag'"))
}
Assert "ParseArgs: --scope under `rules` goes to RuleScope" ($cli.Contains("(A = '--scope') and (Result.Command = 'rules')"))

# 5. (F2) section-5 config keys are read by Lint.Config
$cfg = Src 'src\lint\DRagLint.Lint.Config.pas'
foreach ($key in 'rule_overrides','exclude_units','form_object_without_field','exempt_classes','use_default_list','rule_time_budget_ms') {
  Assert "Lint.Config reads ""$key""" ($cfg.Contains("'$key'"))
}
Assert "DEFAULT_RULE_TIME_BUDGET_MS = 2000 (PLAN D9)" ($cfg -match 'DEFAULT_RULE_TIME_BUDGET_MS\s*=\s*2000;')

if ($fail -gt 0) { Write-Host "run_v152_frame_guard: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v152_frame_guard: all passed"
exit 0
