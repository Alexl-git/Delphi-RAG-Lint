# Guard for the wave v151 registration scaffold (lane FRAME, 1.51.0-alpha).
#
# What it pins:
#   1. the catalog counts (`rules --json`): total, fixable, default-on. With every
#      v151 lane unit empty they equal the 1.50 numbers (317 / 110 / 263); INT
#      raises the three defaults below when it merges rule lanes.
#   2. every scaffold unit exists and is listed in BOTH drag-lint.dpr and .dproj
#      (a unit in only one of them compiles in one build and not the other).
#   3. the hooks are in place: the provider rows at the end of BuiltinRegistry, the
#      OFF list as ONE function, and the TV151Dispatch calls in DoLint, the
#      DoLintAll per-file loop and the DoLintAll project-wide section.
# Positive control (recorded in the v151 ledger, not committed): a probe rule
# declared in a lane Catalog in a scratch build makes check 1 fail with 318.
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe",
  [int]$ExpectTotal = 435,   # 1.52 (was 423 at 1.51.0)
  [int]$ExpectFixable = 131,   # live at 1.52 BATTERY152 (125 at 1.51.0-alpha; +6 = fixable-ids.txt)
  [int]$ExpectOn = 356     # 1.52.2: +1 param-name-prefix ON (owner Q7); 1.52 was 355 (341 at 1.51.0)
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$exe = (Resolve-Path $Exe).Path
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

# 1. counts
$raw = & { $ErrorActionPreference = 'Continue'; & $exe rules --json --rules-dir rules 2>$null }
$json = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }
$total = [int]$json.summary.total
$fixable = @($json.rules | Where-Object { $_.fixable }).Count
$on = @($json.rules | Where-Object { $_.default_enabled }).Count
Assert "rules total = $ExpectTotal (got $total)" ($total -eq $ExpectTotal)
Assert "rules fixable = $ExpectFixable (got $fixable)" ($fixable -eq $ExpectFixable)
Assert "rules default-on = $ExpectOn (got $on)" ($on -eq $ExpectOn)
$dups = @($json.rules | Group-Object id | Where-Object { $_.Count -gt 1 })
Assert "no duplicate rule id in the catalog" ($dups.Count -eq 0)

# 2. units in dpr and dproj
$lanes = 'APP','CMP','DFMA','DFMB','DS','EXC','MEM','OO','RTLCOLL','RTLSTR','STY','THRA','THRB','TXT','TYP'
$units = @('lint\v151\DRagLint.V151.Api.pas', 'lint\v151\DRagLint.V151.Dispatch.pas', 'lint\fixers\DRagLint.Fix.V151.Legacy.pas')
foreach ($l in $lanes) {
  $units += "lint\v151\DRagLint.V151.$l.pas"
  if ($l -ne 'RTLSTR') { $units += "lint\v151\DRagLint.V151.$l.Support.pas" }   # 1.52.1 d227feb3a deleted the empty RTLSTR.Support
  if ($l -eq 'TYP') { $units += "lint\fixers\DRagLint.Fix.V151.$l.pas" }   # 1.52.1 d227feb3a deleted the 14 empty Fix.V151.<lane> scaffolds
}
$dpr = [IO.File]::ReadAllText((Join-Path $repo 'src\cli\drag-lint.dpr'))
$dproj = [IO.File]::ReadAllText((Join-Path $repo 'src\cli\drag-lint.dproj'))
$missing = @()
foreach ($u in $units) {
  $rel = '..\' + $u
  if (-not (Test-Path (Join-Path $repo ('src\' + $u)))) { $missing += "file:$u" }
  if (-not $dpr.Contains("'$rel'")) { $missing += "dpr:$u" }
  if (-not $dproj.Contains("Include=""$rel""")) { $missing += "dproj:$u" }
}
Assert "all $($units.Count) scaffold units exist and are in dpr + dproj ($($missing -join ', '))" ($missing.Count -eq 0)

# 3. hooks
$cat = [IO.File]::ReadAllText((Join-Path $repo 'src\lint\DRagLint.Lint.RuleCatalog.pas'))
Assert "BuiltinRegistry appends the provider rows" ($cat.Contains('L.AddRange(GProviderRows);'))
Assert "OFF list is one function over core + provider rows" ($cat -match 'function BUILTIN_RULES_OFF_BY_DEFAULT: TArray<string>;' -and $cat.Contains('BUILTIN_RULES_OFF_BY_DEFAULT_CORE + GProviderOff'))
$cli = [IO.File]::ReadAllText((Join-Path $repo 'src\cli\DRagLint.CLI.pas'))
Assert "CLI calls TV151Dispatch.CheckFile twice (lint, lint-all loop)" (([regex]::Matches($cli, 'TV151Dispatch\.CheckFile\(')).Count -eq 2)
Assert "CLI calls TV151Dispatch.CheckProject once (lint-all)" (([regex]::Matches($cli, 'TV151Dispatch\.CheckProject\(')).Count -eq 1)
# Each CheckFile/CheckProject call must sit under a gate within the 16 lines above it (1.52.2 PROJ2 added PCtx.LibraryRoots) (1.52 BK-XPROJ
# put a begin..end with the sibling resolver between `if V151Wanted then` and CheckProject):
# `if TV151Dispatch.Wants(..)` (one --rule id) or `if V151Wanted` (lint-all since
# v1511 CLI B16, where --rule may be a list), and V151Wanted must itself be derived
# from the dispatch's own id list. Counting Wants( alone misread the B16 form.
$cliLines = $cli -split "`r?`n"
$ungated = @()
for ($i = 0; $i -lt $cliLines.Count; $i++) {
  if ($cliLines[$i] -match 'TV151Dispatch\.Check(File|Project)\(') {
    $above = ($cliLines[[Math]::Max(0, $i - 16)..($i - 1)] -join "`n")
    if ($above -notmatch '\bif\s+(TV151Dispatch\.Wants\(|V151Wanted\b)') { $ungated += ($i + 1) }
  }
}
$wantedDerived = ($cli -match 'V151Ids:\s*TArray<string>:=\s*TV151Dispatch\.RuleIds;') -and
                 ($cli -match 'V151Wanted:\s*Boolean:=\s*\(Length\(V151Ids\) > 0\) and LintRuleWants\(Nr, V151Ids\);')
Assert "every v151 call is gated by TV151Dispatch.Wants or V151Wanted (ungated lines: $($ungated -join ', '))" ($ungated.Count -eq 0)
Assert "V151Wanted is derived from TV151Dispatch.RuleIds" $wantedDerived

if ($fail -gt 0) { Write-Host "run_v151_frame_guard: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v151_frame_guard: all passed"
exit 0
