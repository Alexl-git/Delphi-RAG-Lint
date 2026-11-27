<#
  run_v156_FIX2A.ps1 -- 1.56 lane FIX2-A: two review findings of REV-2.
    F2  happens-before: check-init must not prove YES through a var / out argument write
        (twins GVarW / GOutW -> MAY a-site-uncertain; control GAsgW plain assignment -> YES check-init)
    F8  lock-order-inversion: a common gate held through a try-enter or an inexact lock silences the pair
        (QUIET markers); positive control: an ungated opposite-order pair still fires (HIT marker)

  Fixtures tests\fixtures\v156\FIX2-A\hb and \thr, indexed into private dbs. Run from a neutral cwd.
  Usage: pwsh -File tests\autotest\run_v156_FIX2A.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = '')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "run_v156_FIX2A: no engine at $Exe"; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP ('dl-v156-fix2a-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) }
[void](New-Item -ItemType Directory -Force -Path $WorkDir)
$script:Fail = 0; $script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function Index-Fx([string]$Folder) {
  $fx = Join-Path $WorkDir "fx-$Folder"
  [void](New-Item -ItemType Directory -Force -Path $fx)
  Copy-Item (Join-Path $Root "tests\fixtures\v156\FIX2-A\$Folder\*.pas") $fx -Force
  $db = Join-Path $WorkDir "$Folder.sqlite"
  & { $ErrorActionPreference = 'Continue'; & $Exe index $fx --db $db *> (Join-Path $WorkDir "index-$Folder.log") }
  return @{ db = $db; fx = $fx }
}
Push-Location $WorkDir
try {
  # ---- F2 ----
  $hb = Index-Fx 'hb'
  foreach ($c in @(@('GVarW', 'MAY', 'var argument'), @('GOutW', 'MAY', 'out argument'), @('GAsgW', 'YES', 'plain assignment (control)'))) {
    $raw = & { $ErrorActionPreference = 'Continue'; & $Exe happens-before --a "write:uFix2Hb.$($c[0])" --b "read:uFix2Hb.$($c[0])" --db $hb.db --json 2>$null }
    $rc = $LASTEXITCODE
    $j = $null; try { $j = ($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } } catch { }
    $v = if ($j) { [string]$j.verdict } else { '(no JSON)' }
    $ok = ($v -eq $c[1])
    if ($c[1] -eq 'MAY') { $ok = $ok -and ($rc -eq 1) -and (@($j.reasons) -contains 'a-site-uncertain') -and ($j.proven -eq $false) }
    else { $ok = $ok -and ($rc -eq 0) -and (@($j.methods) -contains 'check-init') }
    Check "F2 $($c[0]) $($c[2]) -> $($c[1])" $ok "verdict=$v rc=$rc reasons=[$(@($j.reasons) -join ',')] methods=[$(@($j.methods) -join ',')]"
  }
  # ---- F8 ----
  $thr = Index-Fx 'thr'
  $src = Join-Path $thr.fx 'thrGate2.pas'
  $Hit = @{}; $Quiet = @{}; $n = 0
  foreach ($line in [IO.File]::ReadAllLines($src)) {
    $n++
    if ($line -match '//\s*HIT-([A-Z0-9-]+)\s*$')   { $Hit[$n] = $Matches[1] }
    if ($line -match '//\s*QUIET-([A-Z0-9-]+)\s*$') { $Quiet[$n] = $Matches[1] }
  }
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $thr.db --json 2>$null }) -join "`n"
  $f = @()
  if ($out.TrimStart().StartsWith('[')) { $f = @($out | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.rule -eq 'lock-order-inversion' }) }
  $lines = @($f | ForEach-Object { [int]$_.start_line })
  foreach ($k in ($Hit.Keys | Sort-Object)) { Check "F8 hit   $($Hit[$k]) (line $k) fires once" (@($lines | Where-Object { $_ -eq $k }).Count -eq 1) "lines: $($lines -join ',')" }
  foreach ($k in ($Quiet.Keys | Sort-Object)) { Check "F8 quiet $($Quiet[$k]) (line $k) silent" (@($lines | Where-Object { $_ -eq $k }).Count -eq 0) "lines: $($lines -join ',')" }
  Check 'F8 nothing but the HIT line' ($lines.Count -eq $Hit.Count) "lines: $($lines -join ',')"
}
finally { Pop-Location; try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
Write-Host ("run_v156_FIX2A: {0} passed, {1} failed" -f $script:Pass, $script:Fail)
exit $(if ($script:Fail -eq 0) { 0 } else { 1 })
