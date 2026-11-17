# Guard for lane DFMDUP (1.52): TDfmNode / TDfmProp are declared ONCE.
#
# History: DRagLint.V151.Dfm.Common declares the lint-side TDfmProp / TDfmNode records;
# DRagLint.Convert.DfmReemit used to declare its own TDfmNode class (a duplicate global
# name). The converter's parse-tree node is now TReemitDfmNode.
#
# What it pins (source scan of src\**\*.pas, comments ignored, no engine needed):
#   1. exactly one declaration of TDfmNode (the V151.Dfm.Common record)   [RED before: 2]
#   2. exactly one declaration of TDfmProp (positive control: the scan sees a decl)
#   3. TReemitDfmNode is declared exactly once, in Convert.DfmReemit
#   4. no unit still uses the converter node under the old name: every TDfmNode use
#      sits in a unit that does NOT use DRagLint.Convert.DfmReemit
# Optional index cross-check: -Exe <drag-lint.exe> -Db <project db> asserts
# `query --name TDfmNode --exact` returns one declaration.
param(
  [string]$Repo = "",
  [string]$Exe = "",
  [string]$Db = ""
)
$ErrorActionPreference = "Stop"
$repo = if ($Repo -ne "") { (Resolve-Path $Repo).Path } else { (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
$files = Get-ChildItem (Join-Path $repo "src") -Recurse -Filter *.pas
$decl = @{}
foreach ($f in $files) {
  $n = 0
  foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
    $code = ($line -replace '//.*$', '')
    if ($code -match '^\s*(TDfmNode|TDfmProp|TReemitDfmNode)\s*=\s*(class|record)\b') {
      $k = $Matches[1]
      if (-not $decl.ContainsKey($k)) { $decl[$k] = @() }
      $decl[$k] += $f.Name
    }
  }
}
function Count($k) { if ($decl.ContainsKey($k)) { @($decl[$k]).Count } else { 0 } }
Assert "TDfmNode declared once (found $(Count 'TDfmNode'): $(@($decl['TDfmNode']) -join ', '))" ((Count 'TDfmNode') -eq 1)
Assert "TDfmProp declared once (positive control, found $(Count 'TDfmProp'))" ((Count 'TDfmProp') -eq 1)
Assert "TReemitDfmNode declared once in Convert.DfmReemit (found $(Count 'TReemitDfmNode'))" (((Count 'TReemitDfmNode') -eq 1) -and ($decl['TReemitDfmNode'][0] -eq 'DRagLint.Convert.DfmReemit.pas'))
$clash = @()
foreach ($f in $files) {
  $txt = (([IO.File]::ReadAllLines($f.FullName) | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n")
  if (($txt -match '\bTDfmNode\b') -and ($txt -match 'DRagLint\.Convert\.DfmReemit\b') -and ($f.Name -ne 'DRagLint.Convert.DfmReemit.pas') -and ($txt -notmatch 'DRagLint\.V151\.Dfm\.Common')) { $clash += $f.Name }
}
Assert "no converter unit uses the old TDfmNode name (offenders: $($clash -join ', '))" ($clash.Count -eq 0)
if ($Exe -ne "" -and $Db -ne "") {
  $out = & $Exe query --name TDfmNode --exact --db $Db 2>$null
  $hits = @($out | Where-Object { $_ -match 'TDfmNode' })
  Assert "index: query --name TDfmNode --exact = 1 declaration (got $($hits.Count))" ($hits.Count -eq 1)
}
if ($fail -gt 0) { Write-Host "$fail FAILED"; exit 1 }
Write-Host "ALL PASS"