<#
  run_v152_BK-TOOLING2B.ps1 -- lane BK-TOOLING2B (1.52): manifest writer round-trip, runner param tails,
  exception-unit-writer battery blocker.
    M1-M6  settings.ignoreLocalConfig (B28) survives EVERY manifest write path of DRagLint.Index.ManifestWrite:
           register-project --apply (AppendSectionToText), manifest migrate --apply (RebasedManifestText) and
           migrate-dbs --apply (TManifestIO.SaveEdits; M7/M8 text only -- migrate-dbs rewrites the file it was given).
           Each path is checked twice: the KEY is still in the written text, and its EFFECT still holds (the
           engine run from a folder with a .drag-lint.json loads no defaults). M0 is the positive control: the
           same engine without the key DOES load them, so "no banner" cannot pass vacuously.
    P1     no ADVANCED runner (CmdletBinding / Parameter) under tests\autotest has ANY default (-Exe, -RulesDir, -Repo, ...) derived from
           $PSScriptRoot / $MyInvocation / $PSCommandPath inside param(): Windows PowerShell 5 run with -File
           leaves them empty there, so "$PSScriptRoot\..\.." became C:\ (HBRECV F3).
    P2     behavioural control for P1 under powershell.exe -File: the OLD shape yields C:\ (the bug is real on
           this machine), the NEW shape (resolve in the body) yields the script's repo.
    X1     run_exception_unit_writer.ps1 is green on this engine (REWRITE checks were refused by B23).
  Parameters: -Exe engine (default: this tree's src\cli\Win64\Debug build).  Exit 0 = all pass.
#>
[CmdletBinding()]
param([string]$Exe = '', [string]$WorkDir = '')
# Defaults that need the script path are resolved in the body (see P1).
if (-not $Exe)     { $Exe     = Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe' }
if (-not $WorkDir) { $WorkDir = Join-Path ([IO.Path]::GetTempPath()) "v152-bk-tooling2b-$PID" }
$ErrorActionPreference = 'Continue'
$script:fail = 0; $script:pass = 0
function Check($n, $ok, $d = '') {
  if ($ok) { $script:pass++ } else { $script:fail++ }
  Write-Host ("  [{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
}
$exePath = (Resolve-Path -LiteralPath $Exe).Path
$srcDir  = Split-Path -Parent $exePath
$saved = @{}
foreach ($n in 'APPDATA','LOCALAPPDATA','DRAGLINT_LAYOUT','DRAGLINT_MANIFEST') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
[IO.Directory]::CreateDirectory($WorkDir) | Out-Null
$fakeRoam  = Join-Path $WorkDir 'roam';  [IO.Directory]::CreateDirectory($fakeRoam)  | Out-Null
$fakeLocal = Join-Path $WorkDir 'local'; [IO.Directory]::CreateDirectory($fakeLocal) | Out-Null
$cwd = Join-Path $WorkDir 'cwd'; [IO.Directory]::CreateDirectory($cwd) | Out-Null
[IO.File]::WriteAllText((Join-Path $cwd '.drag-lint.json'), '{"rule":"magic-literal"}', [Text.Encoding]::ASCII)

function New-Engine([string]$Name, [string]$ManifestJson) {
  $d = Join-Path $WorkDir $Name; [IO.Directory]::CreateDirectory($d) | Out-Null
  Get-ChildItem -LiteralPath $srcDir -File | Where-Object { $_.Name -match '\.(exe|dll|castlib)$' -and $_.Name -notmatch '\.bak' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $d }
  if (Test-Path -LiteralPath (Join-Path $srcDir 'rules')) { Copy-Item -LiteralPath (Join-Path $srcDir 'rules') -Destination $d -Recurse }
  if ($ManifestJson) { [IO.File]::WriteAllText((Join-Path $d 'drag-lint.json'), $ManifestJson, [Text.Encoding]::ASCII) }
  return (Join-Path $d 'drag-lint.exe')
}
function Invoke-Engine([string]$Copy, [string[]]$EngineArgs, [hashtable]$Vars = @{}) {
  $env:APPDATA = $fakeRoam; $env:LOCALAPPDATA = $fakeLocal; $env:DRAGLINT_LAYOUT = $null; $env:DRAGLINT_MANIFEST = $null
  foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
  Push-Location -LiteralPath $cwd
  try {
    $o = (& $Copy @EngineArgs 2>&1 | ForEach-Object { "$_" }) -join "`n"
    return [pscustomobject]@{ Rc = $LASTEXITCODE; Out = $o }
  } finally {
    Pop-Location
    foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $null) }
  }
}
function Get-Ignore([string]$Path) {
  try { $j = [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { return "unparsable" }
  return "$($j.settings.ignoreLocalConfig)"
}
function Test-NoDefaults([string]$Copy, [hashtable]$Vars = @{}) { return ((Invoke-Engine $Copy @('--version') $Vars).Out -notmatch 'loaded defaults from') }

try {
  # ---- M: manifest writers ------------------------------------------------------------------------
  Write-Host '== M manifest writers keep settings.ignoreLocalConfig ==' -ForegroundColor Cyan
  $ctl = New-Engine 'eng-ctl' '{"settings":{},"indexes":{"sections":[]}}'
  Check 'M0 CONTROL an engine WITHOUT the key loads the CWD .drag-lint.json' (-not (Test-NoDefaults $ctl))

  # register-project --apply -> AppendSectionToText
  $regManifest = '{"settings":{"ignoreLocalConfig":true,"defaultPlatform":"Win32"},"indexes":{"sections":[{"name":"Other","include":["C:\\nowhere\\Other.dproj"]}]}}'
  $reg = New-Engine 'eng-reg' $regManifest
  $projDir = Join-Path $WorkDir 'proj'; [IO.Directory]::CreateDirectory($projDir) | Out-Null
  $proj = Join-Path $projDir 'RegP.dproj'; [IO.File]::WriteAllText($proj, '<Project/>', [Text.Encoding]::ASCII)
  Check 'M1 register-project engine honours the key before the write' (Test-NoDefaults $reg)
  $r = Invoke-Engine $reg @('register-project', $proj, '--apply')
  $regFile = Join-Path (Split-Path -Parent $reg) 'drag-lint.json'
  $regText = [IO.File]::ReadAllText($regFile)
  Check 'M2 register-project --apply wrote the new section' (($r.Rc -eq 0) -and ($regText -match '"RegP"')) "rc=$($r.Rc) $($r.Out)"
  Check 'M3 register-project --apply kept settings.ignoreLocalConfig=true in the text' ((Get-Ignore $regFile) -eq 'True') $regText
  Check 'M4 register-project: the key still takes EFFECT after the write' (Test-NoDefaults $reg)

  # manifest migrate --apply -> RebasedManifestText
  $mig = New-Engine 'eng-mig' '{"settings":{"ignoreLocalConfig":true},"indexes":{"sections":[{"name":"SecM","include":["src"]}]}}'
  [IO.Directory]::CreateDirectory((Join-Path (Split-Path -Parent $mig) 'src')) | Out-Null
  $V2 = @{ DRAGLINT_LAYOUT = 'v2' }
  $r = Invoke-Engine $mig @('manifest', 'migrate', '--apply', '--json') $V2
  $roamFile = Join-Path $fakeRoam 'drag-lint\drag-lint.json'
  Check 'M5 manifest migrate --apply wrote the roaming file and kept settings.ignoreLocalConfig=true' (
    ($r.Rc -eq 0) -and (Test-Path -LiteralPath $roamFile) -and ((Get-Ignore $roamFile) -eq 'True')) "rc=$($r.Rc) $($r.Out)"
  Check 'M6 manifest migrate: the key still takes EFFECT from the roaming file (exe-side file renamed away)' (
    (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $mig) 'drag-lint.json'))) -and (Test-NoDefaults $mig $V2))

  # migrate-dbs --apply -> TManifestIO.SaveEdits (the Config / migrate-dbs save path)
  $mdDir = Join-Path $WorkDir 'mdb'
  [IO.Directory]::CreateDirectory((Join-Path $mdDir 'proj')) | Out-Null; [IO.Directory]::CreateDirectory((Join-Path $mdDir 'elsewhere')) | Out-Null
  [IO.File]::WriteAllText((Join-Path $mdDir 'proj\App.dpr'), "program App;`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)
  $oldDb = Join-Path $mdDir 'elsewhere\App.sqlite'; $newDb = Join-Path $mdDir 'proj\_D-RAG\App.sqlite'
  $null = Invoke-Engine $exePath @('index', '--project', (Join-Path $mdDir 'proj\App.dpr'), '--db', $oldDb)
  $esc = $mdDir -replace '\\', '\\'
  $mdCfg = Join-Path $mdDir 'm.json'
  [IO.File]::WriteAllText($mdCfg, ('{"settings":{"ignoreLocalConfig":true},"indexes":{"sections":[{"name":"App","include":["' + $esc +
    '\\proj\\App.dpr"],"db":"' + $esc + '\\elsewhere\\App.sqlite"}]}}'), [Text.Encoding]::ASCII)
  $r = Invoke-Engine $exePath @('migrate-dbs', '--config', $mdCfg, '--apply')
  $mdText = [IO.File]::ReadAllText($mdCfg)
  Check 'M7 migrate-dbs --apply took the SaveEdits path (DB moved, section "db" key gone)' (
    ($r.Rc -eq 0) -and (Test-Path -LiteralPath $newDb) -and ($mdText -notmatch '"db"')) "rc=$($r.Rc) $($r.Out) $mdText"
  Check 'M8 migrate-dbs --apply (SaveEdits) kept settings.ignoreLocalConfig=true in the text' ((Get-Ignore $mdCfg) -eq 'True') $mdText
  # ---- P: runner param defaults -------------------------------------------------------------------
  Write-Host '== P runner defaults under Windows PowerShell 5 -File ==' -ForegroundColor Cyan
  # Any param() default derived from the script path (-Exe, -RulesDir, -Repo, ...) is the bug, whatever its name.
  function Get-PathDefaultsInParam($Files) {
    $found = @()
    foreach ($f in $Files) {
      $ast = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
      if (-not $ast.ParamBlock) { continue }
      $adv = (@($ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }).Count -gt 0) -or
             (@($ast.ParamBlock.Parameters | Where-Object { $_.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' } }).Count -gt 0)
      if (-not $adv) { continue }
      foreach ($p in $ast.ParamBlock.Parameters) {
        $t = if ($p.DefaultValue) { $p.DefaultValue.Extent.Text } else { '' }
        if ($t -match 'PSScriptRoot|MyInvocation|PSCommandPath') { $found += "$($f.Name) -$($p.Name.VariablePath.UserPath)" }
      }
    }
    return $found
  }
  $bad = @(Get-PathDefaultsInParam (Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -Filter *.ps1))
  $pcDir = Join-Path $WorkDir 'p1ctl'; [IO.Directory]::CreateDirectory($pcDir) | Out-Null
  [IO.File]::WriteAllText("$pcDir\ctl.ps1", "[CmdletBinding()]`r`nparam([string]`$Exe = `"`$PSScriptRoot\..\x.exe`", [string]`$RulesDir = (Join-Path `$PSScriptRoot 'r'))`r`n", [Text.Encoding]::ASCII)
  $ctlBad = @(Get-PathDefaultsInParam (Get-ChildItem -LiteralPath $pcDir -Filter *.ps1))
  Check 'P1 CONTROL a fixture with $PSScriptRoot-derived -Exe and -RulesDir defaults inside param() is flagged' ($ctlBad.Count -eq 2) ($ctlBad -join '; ')  Check 'P1 no advanced runner has ANY default (-Exe, -RulesDir, -Repo, ...) derived from the script path inside param()' ($bad.Count -eq 0) ("$($bad.Count): " + (($bad | Select-Object -First 8) -join '; '))
  Check 'P1 no advanced runner has a param() default derived from $PSScriptRoot / $MyInvocation / $PSCommandPath (-Exe, -RulesDir, -Repo, ...)' ($bad.Count -eq 0) ("$($bad.Count): " + (($bad | Select-Object -First 8) -join '; '))
  $pdir = Join-Path $WorkDir 'p\a\b'; [IO.Directory]::CreateDirectory($pdir) | Out-Null
  [IO.File]::WriteAllText("$pdir\old.ps1", "[CmdletBinding()]`r`nparam([string]`$Repo = (Resolve-Path `"`$PSScriptRoot\..\..`" -ErrorAction SilentlyContinue).Path)`r`n`"REPO=[`$Repo]`"`r`n", [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText("$pdir\new.ps1", "[CmdletBinding()]`r`nparam([string]`$Repo = '')`r`nif (-not `$Repo) { `$Repo = (Resolve-Path `"`$PSScriptRoot\..\..`").Path }`r`n`"REPO=[`$Repo]`"`r`n", [Text.Encoding]::ASCII)
  $want = (Resolve-Path (Join-Path $pdir '..\..')).Path
  $old = (& powershell.exe -NoProfile -File "$pdir\old.ps1" 2>&1 | Out-String)
  $new = (& powershell.exe -NoProfile -File "$pdir\new.ps1" 2>&1 | Out-String)
  Check 'P2 CONTROL the old shape under powershell -File does NOT get the repo (the bug is real here)' ($old -notmatch [regex]::Escape("REPO=[$want]")) $old.Trim()
  Check 'P2 the new shape under powershell -File gets the repo' ($new -match [regex]::Escape("REPO=[$want]")) $new.Trim()

  # ---- X: exception unit writer -------------------------------------------------------------------
  Write-Host '== X run_exception_unit_writer ==' -ForegroundColor Cyan
  $xo = (& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'run_exception_unit_writer.ps1') -Exe $exePath -WorkDir (Join-Path $WorkDir 'excw') 2>&1 | Out-String)
  $xrc = $LASTEXITCODE
  $xf = @(($xo -split "`r?`n") | Where-Object { $_ -match '\[FAIL\]' })
  Check 'X1 run_exception_unit_writer.ps1 passes on this engine' ($xrc -eq 0) ("exit=$xrc " + ($xf -join ' | '))
} finally {
  foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
  try { [IO.Directory]::Delete($WorkDir, $true) } catch { $null = $_ }
}
Write-Host ("run_v152_BK-TOOLING2B: {0} pass, {1} fail" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { Write-Host 'run_v152_BK-TOOLING2B: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_v152_BK-TOOLING2B: PASS' -ForegroundColor Green; exit 0
