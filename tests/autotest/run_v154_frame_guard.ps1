# Guard for the wave v154 scaffold (lane FRAME, 1.54.0-alpha). The catalog COUNTS are pinned by
# run_v151_frame_guard.ps1 / run_v152_frame_guard.ps1, not here.
#
# What it pins:
#   1. every scaffold unit exists and is listed in BOTH drag-lint.dpr and .dproj (the dialog unit: in
#      the plugin's .dpk and .dproj).
#   2. the v154 lanes are BuildLanes rows of DRagLint.V151.Dispatch with all five hooks.
#   3. CLI.Repo dispatches the Table Tools lane units, and only their own unit names their sub-verbs.
#   4. the lint config reads "schema_rules" -> "local_naming_match" and refuses a malformed value.
#   5. DRAGLINT_VERSION is at least 1.54.
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe",
  [string]$Repo = ""
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

# 1. units
$lanes = 'DFM','EXPR','FLOW','SCHEMA','SQL'
$units = @('lint\v154\DRagLint.V154.ParamModes.pas', 'lint\v154\DRagLint.V154.SqlText.pas')
foreach ($l in $lanes) { $units += "lint\v154\DRagLint.V154.$l.pas"; $units += "lint\v154\DRagLint.V154.$l.Support.pas" }
foreach ($s in 'SchemaFactsEx','DfmWrite','DfmWritePlan','Handlers','HandlersRegions') { $units += "sql\DRagLint.FieldRepo.$s.pas" }
$cliUnits = 'RepoDfmWrite','RepoHandlers','RepoFib'
$dpr = Src 'src\cli\drag-lint.dpr'
$dproj = Src 'src\cli\drag-lint.dproj'
$missing = @()
foreach ($u in $units) {
  if (-not (Test-Path (Join-Path $repo "src\$u"))) { $missing += "file:$u" }
  if (-not $dpr.Contains("'..\$u'")) { $missing += "dpr:$u" }
  if (-not $dproj.Contains("Include=""..\$u""")) { $missing += "dproj:$u" }
}
foreach ($c in $cliUnits) {
  $f = "DRagLint.CLI.$c.pas"
  if (-not (Test-Path (Join-Path $repo "src\cli\$f"))) { $missing += "file:$f" }
  if (-not $dpr.Contains("'$f'")) { $missing += "dpr:$f" }
  if (-not $dproj.Contains("Include=""$f""")) { $missing += "dproj:$f" }
}
$dlg = 'DragLint.Plugin.FieldSelectDialog.pas'
if (-not (Test-Path (Join-Path $repo "src\delphi-plugin\$dlg"))) { $missing += "file:$dlg" }
if (-not (Src 'src\delphi-plugin\dclDragLintWizard.dpk').Contains("'$dlg'")) { $missing += "dpk:$dlg" }
if (-not (Src 'src\delphi-plugin\dclDragLintWizard.dproj').Contains("Include=""$dlg""")) { $missing += "plugin dproj:$dlg" }
Assert "all $($units.Count + $cliUnits.Count + 1) v154 scaffold units exist and are in their project files ($($missing -join ', '))" ($missing.Count -eq 0)

# 2. one provider mechanism
$disp = Src 'src\lint\v151\DRagLint.V151.Dispatch.pas'
$notWired = @()
foreach ($l in $lanes) {
  $c = "TV154${l}Rules"
  $hooks = "$c.Catalog, $c.CheckFile, $c.CheckDfm, $c.CheckRawBytes, $c.CheckProject)"
  if (-not ($disp.Contains("Lane('$l',") -and $disp.Contains($hooks) -and $disp -match "DRagLint\.V154\.$l\b")) { $notWired += $l }
}
Assert "every v154 lane is a BuildLanes row of V151.Dispatch with its five hooks ($($notWired -join ', '))" ($notWired.Count -eq 0)

# 3. CLI.Repo dispatch
$cliRepo = Src 'src\cli\DRagLint.CLI.Repo.pas'
foreach ($p in @(@('IsRepoDfmWriteSub(pSub)','RunRepoDfmWriteVerb('), @('IsRepoHandlersSub(pSub)','RunRepoHandlersVerb('), @('IsRepoFibSub(pSub)','RunRepoFibVerb('))) {
  $hits = @($cliRepo -split "`r?`n" | Where-Object { $_.Contains($p[0]) -and $_.Contains($p[1]) })
  Assert "CLI.Repo: $($p[0]) -> $($p[1]) on exactly one line (got $($hits.Count))" ($hits.Count -eq 1)
}
Assert "CLI.Repo: the unknown-sub-verb message takes the lanes' names" ($cliRepo.Contains('+ REPO_DFMWRITE_SUBS + REPO_HANDLERS_SUBS + REPO_FIB_SUBS'))

# 4. config key, on the running engine: a good value loads, a malformed one is refused by name
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl-v154-frame-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
[void](New-Item -ItemType Directory -Path $work)
try {
  $pas = Join-Path $work 'uA.pas'
  [IO.File]::WriteAllText($pas, "unit uA;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
  function Lint-With($json) {
    $cfg = Join-Path $work 'cfg.json'
    [IO.File]::WriteAllText($cfg, $json, [Text.Encoding]::ASCII)
    $o = & { $ErrorActionPreference = 'Continue'; & $exe lint $pas --config $cfg 2>&1 | ForEach-Object { "$_" } }
    return ($o -join "`n")
  }
  Assert 'config: schema_rules.local_naming_match = true loads' ((Lint-With '{"schema_rules":{"local_naming_match":true}}') -notmatch 'schema_rules')
  Assert 'config: schema_rules.local_naming_match = 1 is refused by name' ((Lint-With '{"schema_rules":{"local_naming_match":1}}') -match 'schema_rules\.local_naming_match')
  Assert 'config: schema_rules = [] is refused by name' ((Lint-With '{"schema_rules":[]}') -match '"schema_rules" must be an object')
} finally { [IO.Directory]::Delete($work, $true) }

# 5. version
$m = [regex]::Match((Src 'src\core\DRagLint.Core.Model.pas'), "DRAGLINT_VERSION = '1\.(\d+)\.")
Assert "DRAGLINT_VERSION is 1.54 or later (got 1.$($m.Groups[1].Value))" ($m.Success -and [int]$m.Groups[1].Value -ge 54)

if ($fail -gt 0) { Write-Host "run_v154_frame_guard: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v154_frame_guard: all passed"
exit 0
