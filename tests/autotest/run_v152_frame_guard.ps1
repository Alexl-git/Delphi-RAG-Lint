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
  [int]$ExpectTotal = 423,
  [int]$ExpectFixable = 125,
  [int]$ExpectOn = 341
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

if ($fail -gt 0) { Write-Host "run_v152_frame_guard: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v152_frame_guard: all passed"
exit 0
