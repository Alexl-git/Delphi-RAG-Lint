<#
  run_default_engine_fallback_guard.ps1 -- GD (wave 148): a guard whose default engine is the deployed
  third_party\dll-win64\drag-lint.exe must fall back to the worktree's own src\cli\Win64\Debug build, and
  the reverse for the Debug-default cyclefix guards; when neither exists it must say so, naming both paths.

  Before this fix run_feature_registry_guard.ps1 said "GUARD BROKEN: engine not found: <dll-win64>" and the
  cyclefix_cycq guard said "FATAL: exe not found" in every fresh worktree.

  Checks (each has a positive control: the same probe on a tree WITHOUT the fallback file must refuse):
    A  cyclefix scripts: the `-Exe` default expression, evaluated against a scratch tree, returns the Debug exe when
       only Debug exists, the deployed exe when only that exists, and the first-choice path when neither exists.
    B  run_feature_registry_guard.ps1 run from a scratch tree with NO engine anywhere says GUARD BROKEN naming BOTH
       paths (exit 1); with only a stub Debug exe it does not say "no engine" (it reaches the engine stage).
  Run under pwsh 7:  pwsh -File tests\autotest\run_default_engine_fallback_guard.ps1
#>
[CmdletBinding()]
param([string]$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
Write-Host '== default-engine fallback guard ==' -ForegroundColor Cyan
$tmp = Join-Path $env:TEMP "dl-default-engine-fallback-$PID"
$tests = Join-Path $tmp 'tests\autotest'
[void][IO.Directory]::CreateDirectory($tests)
# The runners' -Exe defaults dot-source lib\FreshEngineExe.ps1 from their own $PSScriptRoot, which is $tests here.
[void][IO.Directory]::CreateDirectory((Join-Path $tests 'lib'))
Copy-Item -LiteralPath (Join-Path $Repo 'tests\autotest\lib\FreshEngineExe.ps1') -Destination (Join-Path $tests 'lib\FreshEngineExe.ps1')
$deployed = Join-Path $tmp 'third_party\dll-win64\drag-lint.exe'
$built = Join-Path $tmp 'src\cli\Win64\Debug\drag-lint.exe'
function Set-Stub([string]$Path, [bool]$On) {
  if ($On) { [void][IO.Directory]::CreateDirectory((Split-Path $Path)); [IO.File]::WriteAllText($Path, 'stub') }
  elseif (Test-Path -LiteralPath $Path) { [IO.File]::Delete($Path) }
}
function Get-ExeDefault([string]$Script) {
  $ast = [Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$null)
  $p = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Exe' } | Select-Object -First 1
  if (-not $p -or -not $p.DefaultValue) { return $null }
  return $p.DefaultValue.Extent.Text
}
try {
  # ---- A: every cyclefix guard's -Exe default
  $psr = $tests
  $scripts = @(Get-ChildItem (Join-Path $Repo 'tests\autotest') -Filter 'run_cyclefix_*.ps1')
  $bad = @()
  foreach ($s in $scripts) {
    $expr = Get-ExeDefault $s.FullName
    if (-not $expr) { continue }
    $sb = [scriptblock]::Create('param($PSScriptRoot) ' + $expr)
    if ($expr -match 'Get-FreshEngineExe') {
      # v1511 HYG H02 contract: the tree's own build or FATAL exit 2 -- NEVER the deployed engine.
      # `exit` inside the default would end this guard, so the no-build states run in a child pwsh.
      Set-Stub $deployed $false; Set-Stub $built $true
      $onlyBuilt = & $sb $psr
      $childFile = Join-Path $tmp 'fresh-probe.ps1'; [IO.File]::WriteAllText($childFile, 'param($r) & { param($PSScriptRoot) ' + $expr + ' } $r')
      Set-Stub $built $false
      $nb = & pwsh -NoProfile -File $childFile $psr 2>&1 | Out-String; $nbCode = $LASTEXITCODE
      Set-Stub $deployed $true
      $dp = & pwsh -NoProfile -File $childFile $psr 2>&1 | Out-String; $dpCode = $LASTEXITCODE
      $okFresh = ($onlyBuilt -like '*src\cli\Win64\Debug\drag-lint.exe') -and ($nbCode -eq 2) -and ($dpCode -eq 2) -and $nb.Contains('no build of this tree') -and $dp.Contains('no build of this tree')
      if (-not $okFresh) { $bad += $s.Name }
      continue
    }
    Set-Stub $deployed $false; Set-Stub $built $false
    $none = & $sb $psr
    Set-Stub $built $true
    $onlyBuilt = & $sb $psr
    Set-Stub $built $false; Set-Stub $deployed $true
    $onlyDeployed = & $sb $psr
    $ok = ($onlyBuilt -like '*src\cli\Win64\Debug\drag-lint.exe') -and ($onlyDeployed -like '*third_party\dll-win64\drag-lint.exe') -and ($none -like '*drag-lint.exe')  # exe-freshness: absent (wildcard patterns matched against stub paths, not exe references)
    if (-not $ok) { $bad += $s.Name }
  }
  Check 'A cyclefix -Exe defaults fall back both ways' (($bad.Count -eq 0) -and ($scripts.Count -ge 40)) "($($scripts.Count) scripts, bad: $($bad -join ','))"
  # ---- B: registry guard, scratch tree
  $guard = Join-Path $Repo 'tests\autotest\run_feature_registry_guard.ps1'
  $text = [IO.File]::ReadAllText($guard)
  $m = [regex]::Match($text, '(?s)\$engine = \$Engine\r?\nif \(-not \$engine\) \{.*?\r?\n\}\r?\n')
  Check 'B registry guard carries the fallback block' $m.Success
  if ($m.Success) {
    # run ONLY the engine-resolution block against the scratch tree (the rest needs featuregen, a full repo)
    $probe = '$Repo = $args[0]; $Engine = ""; ' + $m.Value + ' Write-Host "ENGINE=$engine"'
    $pf = Join-Path $tmp 'probe.ps1'; [IO.File]::WriteAllText($pf, $probe)
    Set-Stub $deployed $false; Set-Stub $built $false
    $o0 = (& pwsh -NoProfile -File $pf $tmp 2>&1 | Out-String); $c0 = $LASTEXITCODE
    Check 'B neither engine: GUARD BROKEN naming both paths, exit 1' (($c0 -eq 1) -and $o0.Contains('GUARD BROKEN') -and $o0.Contains($deployed) -and $o0.Contains($built))
    Set-Stub $built $true
    $o1 = (& pwsh -NoProfile -File $pf $tmp 2>&1 | Out-String)
    Check 'B only Debug build: it is chosen' ($o1.Contains("ENGINE=$built"))
    Set-Stub $deployed $true
    $o2 = (& pwsh -NoProfile -File $pf $tmp 2>&1 | Out-String)
    Check 'B both present: deployed wins' ($o2.Contains("ENGINE=$deployed"))
  }
} finally {
  if (Test-Path -LiteralPath $tmp) { [IO.Directory]::Delete($tmp, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
