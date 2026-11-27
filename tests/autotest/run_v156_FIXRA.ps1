# run_v156_FIXRA.ps1 -- v156 fix lane FIXR-A (review REV-1 findings 1, 4, 7):
#   F1  the taint walker's FIELD / GLOBAL writer lookups drop value rows (val_class <> '') like RowsOf:
#       an Integer parameter written to a field / unit variable is no taint carrier (no finding at
#       DeleteFile(IntToStr(FQty)) / IntToStr(GQty)).
#       POSITIVE CONTROL: the string twins (FName / GName) still fire taint-path-traversal.
#   F4  run_extractor_version_guard.ps1 hashes src\analysis\DRagLint.Analysis.Cfg.pas and
#       src\doc\DRagLint.Doc.SymbolFacts.pas (row-writing units outside parser / preprocess / index):
#       a touched file there makes the guard FAIL.  POSITIVE CONTROL: the untouched staged tree passes,
#       and so does a touch of a unit OUTSIDE the surface (src\lint) -- the guard is not "always red".
#   F7  see the LIN section (tests\fieldrepo\LineageTests.dpr, run by run_v156_LIN1.ps1): lineage reads the
#       '' row set only; the doc-comment of TDataFlowRow.ValClass states which reader wants which row.
# Usage: pwsh -File tests\autotest\run_v156_FIXRA.ps1 [-Exe <drag-lint.exe>]   (rules\ + DLLs beside the exe)
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') {
  $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe'
  if (-not (Test-Path $Exe)) { $Exe = Join-Path $repo 'third_party\dll-win64\drag-lint.exe' }
}
$exePath = (Resolve-Path $Exe).Path
$fx   = Join-Path $repo 'tests\fixtures\v156-fixra'
$src  = [IO.File]::ReadAllLines((Join-Path $fx 'uFixRA.pas'))
$tmp  = Join-Path $env:TEMP "v156fixra_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}
function LineOf([string]$Marker) {
  for ($i = 0; $i -lt $src.Length; $i++) { if ($src[$i].Contains("{ $Marker }")) { return $i + 1 } }
  throw "marker $Marker not in the fixture"
}
function AtLine($L, [int]$Line) { return ,@($L | Where-Object { $_.start_line -eq $Line }) }
Push-Location $env:TEMP
try {
  # ---- F1 ----
  $db = Join-Path $tmp 'fx.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $fx --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --json --quiet 2>$null }
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @(($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object { $_.rule -like 'taint-*' }) } catch { $all = @() } }
  $all | ForEach-Object { Write-Host ("  {0} {1} {2}" -f $_.rule, $_.start_line, $_.message) }
  foreach ($m in 'FIELDSTR', 'GLOBSTR') {
    $c = AtLine $all (LineOf $m)
    Check "F1 POSITIVE CONTROL: the string twin ($m) still fires taint-path-traversal" (($c.Count -ge 1) -and ($c[0].rule -eq 'taint-path-traversal')) "got $($c.Count)"
  }
  foreach ($m in 'FIELDINT', 'GLOBINT') {
    Check "F1 a value row written to a field / global is no taint carrier ($m)" ((AtLine $all (LineOf $m)).Count -eq 0) 'a finding fired'
  }

  # ---- F4 ----
  $stage = Join-Path $tmp 'guard'
  $dirs = @('src\parser', 'src\preprocess', 'src\index', 'src\doc', 'src\analysis', 'src\storage', 'src\lint')
  foreach ($d in $dirs) { Copy-Item (Join-Path $repo $d) (Join-Path $stage $d) -Recurse }
  foreach ($f in 'src\core\DRagLint.Core.Indexer.pas', 'src\core\DRagLint.Core.Model.pas', 'src\cli\DRagLint.CLI.pas', 'tests\autotest\run_extractor_version_guard.ps1') {
    $to = Join-Path $stage $f; [void][IO.Directory]::CreateDirectory((Split-Path $to)); Copy-Item (Join-Path $repo $f) $to
  }
  $guard = Join-Path $stage 'tests\autotest\run_extractor_version_guard.ps1'
  $base  = Join-Path $stage 'tests\extractor-version.baseline'
  function RunGuard { $o = & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File $guard 2>&1 | ForEach-Object { "$_" } }; return @{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
  [IO.File]::WriteAllText($base, "0.0.0|0`n")
  $r0 = RunGuard
  $line = ([regex]::Match($r0.Out, '(?m)^\s+(\d+\.\d+\.\d+[^\s|]*\|[0-9a-f]{64})\s*$')).Groups[1].Value
  Check 'F4 staging: the guard printed the current baseline line' ($line -ne '') $r0.Out
  [IO.File]::WriteAllText($base, "$line`n")
  $r1 = RunGuard
  Check 'F4 POSITIVE CONTROL: the untouched staged tree passes' ($r1.Code -eq 0) $r1.Out
  foreach ($rel in 'src\analysis\DRagLint.Analysis.Cfg.pas', 'src\doc\DRagLint.Doc.SymbolFacts.pas') {
    $p = Join-Path $stage $rel
    $orig = [IO.File]::ReadAllBytes($p)
    try {
      [IO.File]::WriteAllBytes($p, $orig + [Text.Encoding]::ASCII.GetBytes("{ touched }`r`n"))
      $r = RunGuard
      Check "F4 a touched $rel makes the guard FAIL" ($r.Code -ne 0) 'guard stayed green'
    } finally { [IO.File]::WriteAllBytes($p, $orig) }
  }
  # control: a unit outside the surface does not move the hash
  $lintPas = (Get-ChildItem (Join-Path $stage 'src\lint') -Filter *.pas | Select-Object -First 1).FullName
  $orig = [IO.File]::ReadAllBytes($lintPas)
  try {
    [IO.File]::WriteAllBytes($lintPas, $orig + [Text.Encoding]::ASCII.GetBytes("{ touched }`r`n"))
    $r = RunGuard
    Check 'F4 control: a touched src\lint unit (outside the surface) leaves the guard green' ($r.Code -eq 0) $r.Out
  } finally { [IO.File]::WriteAllBytes($lintPas, $orig) }

  # ---- F7: the ValClass doc-comment agrees with the readers ----
  $model = [IO.File]::ReadAllText((Join-Path $repo 'src\core\DRagLint.Core.Model.pas'))
  $doc = [regex]::Match($model, '(?s)1\.56 B3: the value class of the flowing value.*?</summary>').Value
  Check 'F7 doc-comment: ValClass '''' is the pre-1.56 set INCLUDING the legacy twin of a classed row' ($doc -match 'legacy twin') 'doc silent about the twin'
  foreach ($reader in 'RowsOf', 'GetFieldWriters', 'CollectArguments', 'Charts.Q.ValueFlow', 'TUnitReader.LoadFlows') {
    Check "F7 doc-comment names the reader $reader" ($doc -match [regex]::Escape($reader)) 'not named'
  }
  $lin = [IO.File]::ReadAllText((Join-Path $repo 'src\sql\DRagLint.FieldRepo.Lineage.pas'))
  $ld = [regex]::Match($lin, '(?s)procedure TUnitReader\.LoadFlows;.*?\r\nend;').Value
  Check 'F7 lineage LoadFlows reads both row sets as the doc-comment says (no val_class condition in its SQL)' (($ld.Length -gt 0) -and ($ld -notmatch '(?i)val_class') -and ($doc -match 'reads BOTH sets')) 'LoadFlows filters, or the doc says otherwise'
  Check 'F7 control: HappensBefore CollectArguments filters val_class = '''' (the doc-comment says so)' ([IO.File]::ReadAllText((Join-Path $repo 'src\query\DRagLint.Query.HappensBefore.Events.pas')) -match "d\.val_class = ''''") 'filter gone'
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
if ($fail -gt 0) { Write-Host "FAIL: $fail check(s)"; exit 1 }
Write-Host 'run_v156_FIXRA: all checks passed'