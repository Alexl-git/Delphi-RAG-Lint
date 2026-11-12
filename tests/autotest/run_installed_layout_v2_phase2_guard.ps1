<#
  run_installed_layout_v2_phase2_guard.ps1 -- installed layout v2, phase 2 (+ the phase-5 escape
  value): `manifest migrate`, E6 %VAR% expansion in outDir, the roaming library default, writers
  that create the roaming manifest, DRAGLINT_LAYOUT=v1. Spec:
  docs\superpowers\specs\2026-11-06-installed-layout-v2.md (section 5, phases 2 and 5).

  Every engine run sees a FAKE APPDATA and LOCALAPPDATA under -WorkDir and an engine COPY.
  The scratch refusal is the phase-1 guard's (S1-S2 here re-prove it fires).

  CASES
    S1-S2 scratch guard
    D1-D3 migrate plans by default and touches nothing; --apply with the layout OFF and with an
          explicit manifest is refused (exit 2) and touches nothing
    A1-A6 migrate --apply (v2): roaming file written, exe-side file RENAMED (not deleted), every
          section's DB path unchanged, unknown keys kept, a re-run has nothing to migrate,
          an existing roaming file is never overwritten
    N1-N3 E6: %VAR% in outDir expands under v2, stays literal with the layout OFF, an unset
          name stays literal
    L1-L2 ruling 3: a roaming manifest with no outDir puts DBs in LOCALAPPDATA\drag-lint\library;
          an explicit one with no outDir keeps them beside itself
    C1-C3 register-project with no manifest anywhere: OFF refuses and creates nothing, v2 dry
          run creates nothing, v2 --apply creates the roaming file with the section
    V1    DRAGLINT_LAYOUT=v1 is OFF (the way back after the phase-5 flip)
    R1    the real manifest locations did not change

  RED control: pass the deployed 1.46.0 engine as -Exe; D1, A*, N1, L1, C3 must fail.
  Exit 0 = all pass, 1 = a check failed, 2 = refused to run.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_layout_v2_p2_guard_$PID"
)
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # 152 HG3: no machine drag-lint.json

function Assert-Scratch([string]$Path) {
  $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
  foreach ($real in @($env:APPDATA, $env:LOCALAPPDATA)) {
    if ($real -and $full.StartsWith($real.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
      $tmp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
      if (-not $full.StartsWith($tmp, [StringComparison]::OrdinalIgnoreCase)) {
        throw "refused: $Path is inside the real profile folder $real"
      }
    }
  }
  $roots = @(([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'), 'C:\TEMP\')
  $inScratch = @($roots | Where-Object { $full.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) -and $full.Length -gt $_.Length })
  if ($inScratch.Count -eq 0) { throw "refused: $Path is not below a scratch root ($($roots -join ', '))" }
}

try { Assert-Scratch $WorkDir } catch { Write-Host "REFUSED: $_" -ForegroundColor Red; exit 2 }

$savedEnv = @{}
foreach ($n in 'APPDATA','LOCALAPPDATA','DRAGLINT_LAYOUT','DRAGLINT_MANIFEST','DLGUARD_OUT','DLGUARD_UNSET') { $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
$realAppData = $env:APPDATA
$realLocal   = $env:LOCALAPPDATA

try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}

Check 'S1 WorkDir accepted as scratch' $true
$refused = $false
try { Assert-Scratch (Join-Path $realAppData 'drag-lint') } catch { $refused = $true }
Check 'S2 positive control: the real APPDATA is refused' $refused

function Get-Stamp([string]$p) { if (Test-Path -LiteralPath $p) { $i = Get-Item -LiteralPath $p; "$($i.Length)/$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' } }
$exePath = (Resolve-Path $Exe).Path
$srcDir  = Split-Path $exePath -Parent
$realWatch = @((Join-Path $realAppData 'drag-lint\drag-lint.json'), (Join-Path $srcDir 'drag-lint.json'))
$realBefore = $realWatch | ForEach-Object { Get-Stamp $_ }

if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$fakeLocal = Join-Path $WorkDir 'fake-localappdata'
$cwd       = Join-Path $WorkDir 'cwd'
foreach ($d in $fakeLocal, $cwd) { [void][IO.Directory]::CreateDirectory($d) }

function New-Engine([string]$Dir) {
  [void][IO.Directory]::CreateDirectory($Dir)
  Copy-Item -LiteralPath $exePath -Destination $Dir
  Get-ChildItem -LiteralPath $srcDir -Filter '*.dll' | Copy-Item -Destination $Dir
  Copy-Item -LiteralPath (Join-Path $srcDir 'rules') -Destination $Dir -Recurse
  return (Join-Path $Dir 'drag-lint.exe')
}
function New-Src([string]$Dir) {
  [void][IO.Directory]::CreateDirectory((Join-Path $Dir 'src'))
  [IO.File]::WriteAllText((Join-Path $Dir 'src\Only.pas'), "unit Only;`r`ninterface`r`nimplementation`r`nend.`r`n")
}

function Invoke-Engine([string]$Copy, [string]$Roam, [string[]]$EngineArgs, [hashtable]$Vars = @{}) {
  $env:APPDATA = $Roam
  $env:LOCALAPPDATA = $fakeLocal
  $env:DRAGLINT_LAYOUT = $null
  $env:DRAGLINT_MANIFEST = $null
  foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $Vars[$k]) }
  Push-Location -LiteralPath $cwd
  try {
    $errFile = Join-Path $WorkDir 'stderr.txt'
    $o = ((& $Copy @EngineArgs 2>$errFile | ForEach-Object { "$_" }) -join "`n")
    $rc = $LASTEXITCODE
    $e = if (Test-Path -LiteralPath $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
    return [pscustomobject]@{ Rc = $rc; Out = $o; Err = $e }
  } finally {
    foreach ($k in $Vars.Keys) { [Environment]::SetEnvironmentVariable($k, $null) }
    Pop-Location
  }
}
function Get-Plan([string]$Copy, [string]$Roam, [hashtable]$Vars = @{}) {
  $r = Invoke-Engine $Copy $Roam @('index','--all','--dry-run','--json') $Vars
  try { $plan = $r.Out | ConvertFrom-Json } catch { return [pscustomobject]@{ Key = ''; Dbs = @(); Raw = $r.Out + $r.Err } }
  $pairs = @($plan.sections | ForEach-Object { "$($_.name)=$($_.db)" })
  return [pscustomobject]@{ Key = ($pairs -join '|'); Dbs = @($plan.sections | ForEach-Object { $_.db }); Raw = $r.Out + $r.Err }
}
function Get-Json([object]$R) { try { return ($R.Out | ConvertFrom-Json) } catch { return $null } }
function Test-Under([string]$Path, [string]$Dir) { return $Path -and $Path.StartsWith($Dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }
function Get-Tree([string]$Dir) { if (Test-Path -LiteralPath $Dir) { @(Get-ChildItem -LiteralPath $Dir -Recurse -Force | ForEach-Object { "$($_.FullName)/$(if ($_.PSIsContainer) {'d'} else {$_.Length})" }) -join '|' } else { 'absent' } }
$V2 = @{ DRAGLINT_LAYOUT = 'v2' }

# ---- engine A: an exe-side manifest with NO outDir, a relative include array, a string include
#      and an unknown key; an empty fake APPDATA ----
$engA   = Join-Path $WorkDir 'engineA'
$copyA  = New-Engine $engA
$roamA  = Join-Path $WorkDir 'roamA'
[void][IO.Directory]::CreateDirectory($roamA)
New-Src $engA
$exeManifest = Join-Path $engA 'drag-lint.json'
$exeText = '{"_comment":"guard-keep-me","settings":{},"indexes":{"sections":[{"name":"SecArr","include":["src"]},{"name":"SecStr","include":"src"}]}}'
[IO.File]::WriteAllText($exeManifest, $exeText)
$roamManifest = Join-Path $roamA 'drag-lint\drag-lint.json'
$renamed = "$exeManifest.migrated-$((Get-Date).ToString('yyyy-MM-dd'))"

$base = Get-Plan $copyA $roamA
Check 'A0 baseline (layout OFF): both exe-side sections plan' (($base.Dbs.Count -eq 2) -and ($base.Key -match 'SecArr=') -and ($base.Key -match 'SecStr=')) $base.Raw

# ---- D: refusals and the dry run ----
$treeBefore = (Get-Tree $engA) + '#' + (Get-Tree $roamA)
$r = Invoke-Engine $copyA $roamA @('manifest','migrate','--json')
$j = Get-Json $r
Check 'D1 migrate without --apply plans (outcome migrated, applied false) and touches nothing' (
  ($r.Rc -eq 0) -and $j -and ($j.outcome -eq 'migrated') -and (-not $j.applied) -and ($j.target -eq $roamManifest) -and
  ((Get-Tree $engA) + '#' + (Get-Tree $roamA) -eq $treeBefore)) ($r.Out + $r.Err)
$r = Invoke-Engine $copyA $roamA @('manifest','migrate','--apply','--json')
$j = Get-Json $r
Check 'D2 --apply with the layout OFF is refused (exit 2, layout-off) and touches nothing' (
  ($r.Rc -eq 2) -and $j -and ($j.outcome -eq 'layout-off') -and ((Get-Tree $engA) + '#' + (Get-Tree $roamA) -eq $treeBefore)) ($r.Out + $r.Err)
$r = Invoke-Engine $copyA $roamA @('manifest','migrate','--apply','--json') @{ DRAGLINT_LAYOUT = 'v2'; DRAGLINT_MANIFEST = $exeManifest }
$j = Get-Json $r
Check 'D3 --apply with an explicit manifest is refused (exit 2, explicit) and touches nothing' (
  ($r.Rc -eq 2) -and $j -and ($j.outcome -eq 'explicit') -and ((Get-Tree $engA) + '#' + (Get-Tree $roamA) -eq $treeBefore)) ($r.Out + $r.Err)

# ---- A: the migration ----
$r = Invoke-Engine $copyA $roamA @('manifest','migrate','--apply','--json') $V2
$j = Get-Json $r
Check 'A1 migrate --apply (v2): exit 0, applied, roaming file written' (($r.Rc -eq 0) -and $j -and $j.applied -and (Test-Path -LiteralPath $roamManifest)) ($r.Out + $r.Err)
Check 'A2 the exe-side file is RENAMED to .migrated-<date>, byte-identical, not deleted' (
  (-not (Test-Path -LiteralPath $exeManifest)) -and (Test-Path -LiteralPath $renamed) -and ([IO.File]::ReadAllText($renamed) -ceq $exeText)) "renamedTo=$($j.renamedTo)"
$after = Get-Plan $copyA $roamA $V2
Check 'A3 v2 after migrate: the ROAMING file answers with the same sections and every DB path unchanged' ((Test-Path -LiteralPath $roamManifest) -and (-not (Test-Path -LiteralPath $exeManifest)) -and ($after.Key -ne '') -and ($after.Key -ceq $base.Key)) "before=$($base.Key)`n      after=$($after.Key)`n      $($after.Raw)"
$roamText = if (Test-Path -LiteralPath $roamManifest) { [IO.File]::ReadAllText($roamManifest) } else { '' }
Check 'A4 unknown keys survive and includes are absolute' (($roamText -match 'guard-keep-me') -and ($roamText -match [regex]::Escape(((Join-Path $engA 'src') -replace '\\','\\')))) $roamText
$r = Invoke-Engine $copyA $roamA @('manifest','migrate','--apply','--json') $V2
$j = Get-Json $r
Check 'A5 a re-run has nothing to migrate (exit 0)' (($r.Rc -eq 0) -and $j -and ($j.outcome -eq 'nothing-to-migrate')) ($r.Out + $r.Err)
[IO.File]::WriteAllText($exeManifest, $exeText)
$roamBefore = if (Test-Path -LiteralPath $roamManifest) { [IO.File]::ReadAllText($roamManifest) } else { '<absent>' }
$r = Invoke-Engine $copyA $roamA @('manifest','migrate','--apply','--json') $V2
$j = Get-Json $r
Check 'A6 an existing roaming file is never overwritten (exit 2, target-exists; both files intact)' (
  ($r.Rc -eq 2) -and $j -and ($j.outcome -eq 'target-exists') -and ($roamBefore -ne '<absent>') -and ([IO.File]::ReadAllText($roamManifest) -ceq $roamBefore) -and
  ([IO.File]::ReadAllText($exeManifest) -ceq $exeText)) ($r.Out + $r.Err)

# ---- N / L: outDir under v2 (explicit manifests, so the file found is known) ----
$nDir = Join-Path $WorkDir 'expN'
New-Src $nDir
$nManifest = Join-Path $nDir 'drag-lint.json'
[IO.File]::WriteAllText($nManifest, '{"settings":{},"indexes":{"outDir":"%DLGUARD_OUT%\\dbs","sections":[{"name":"SecN","include":["src"]}]}}')
$outRoot = Join-Path $WorkDir 'expanded'
$p = Get-Plan $copyA $roamA @{ DRAGLINT_LAYOUT = 'v2'; DRAGLINT_MANIFEST = $nManifest; DLGUARD_OUT = $outRoot }
Check 'N1 v2: %DLGUARD_OUT% in outDir expands' (Test-Under $p.Dbs[0] (Join-Path $outRoot 'dbs')) ($p.Dbs -join ',')
$p = Get-Plan $copyA $roamA @{ DRAGLINT_MANIFEST = $nManifest; DLGUARD_OUT = $outRoot }
Check 'N2 OFF: outDir stays literal (today''s behaviour)' (($p.Dbs.Count -eq 1) -and ($p.Dbs[0] -match '%DLGUARD_OUT%')) ($p.Dbs -join ',')
[IO.File]::WriteAllText($nManifest, '{"settings":{},"indexes":{"outDir":"%DLGUARD_UNSET%\\dbs","sections":[{"name":"SecN","include":["src"]}]}}')
$p = Get-Plan $copyA $roamA @{ DRAGLINT_LAYOUT = 'v2'; DRAGLINT_MANIFEST = $nManifest }
Check 'N3 v2: an unset name stays literal' (($p.Dbs.Count -eq 1) -and ($p.Dbs[0] -match '%DLGUARD_UNSET%')) ($p.Dbs -join ',')

$engL  = Join-Path $WorkDir 'engineL'
$copyL = New-Engine $engL
$roamL = Join-Path $WorkDir 'roamL'
$lDir  = Join-Path $roamL 'drag-lint'
New-Src $lDir
[IO.File]::WriteAllText((Join-Path $lDir 'drag-lint.json'), '{"settings":{},"indexes":{"sections":[{"name":"SecL","include":["src"]}]}}')
$p = Get-Plan $copyL $roamL $V2
Check 'L1 v2: a roaming manifest with no outDir puts DBs in LOCALAPPDATA\drag-lint\library' (Test-Under $p.Dbs[0] (Join-Path $fakeLocal 'drag-lint\library')) ($p.Dbs -join ',')
$xDir = Join-Path $WorkDir 'expX'
New-Src $xDir
$xManifest = Join-Path $xDir 'drag-lint.json'
[IO.File]::WriteAllText($xManifest, '{"settings":{},"indexes":{"sections":[{"name":"SecX","include":["src"]}]}}')
$p = Get-Plan $copyL $roamL @{ DRAGLINT_LAYOUT = 'v2'; DRAGLINT_MANIFEST = $xManifest }
Check 'L2 v2: an explicit manifest with no outDir keeps DBs beside itself' (Test-Under $p.Dbs[0] $xDir) ($p.Dbs -join ',')

# ---- C: register-project with no manifest anywhere ----
# own parent folder: the writer's sibling walk (the BPL copy) would otherwise find engineA's file
$engC  = Join-Path $WorkDir 'isoC\engineC'
$copyC = New-Engine $engC
$roamC = Join-Path $WorkDir 'roamC'
[void][IO.Directory]::CreateDirectory($roamC)
$proj = Join-Path $cwd 'Reg.dproj'
[IO.File]::WriteAllText($proj, '<Project><PropertyGroup><MainSource>Reg.dpr</MainSource></PropertyGroup></Project>')
$roamCManifest = Join-Path $roamC 'drag-lint\drag-lint.json'
$r = Invoke-Engine $copyC $roamC @('register-project', $proj, '--name', 'RegC', '--apply')
Check 'C1 OFF: register-project with no manifest creates nothing' ((-not (Test-Path -LiteralPath $roamCManifest)) -and (-not (Test-Path -LiteralPath (Join-Path $engC 'drag-lint.json')))) ($r.Out + $r.Err)
$r = Invoke-Engine $copyC $roamC @('register-project', $proj, '--name', 'RegC') $V2
Check 'C2 v2 dry run creates nothing' (-not (Test-Path -LiteralPath $roamCManifest)) ($r.Out + $r.Err)
$r = Invoke-Engine $copyC $roamC @('register-project', $proj, '--name', 'RegC', '--apply') $V2
$cText = if (Test-Path -LiteralPath $roamCManifest) { [IO.File]::ReadAllText($roamCManifest) } else { '' }
Check 'C3 v2 --apply creates the roaming manifest with the section, nothing beside the exe' (
  ($cText -match '"RegC"') -and (-not (Test-Path -LiteralPath (Join-Path $engC 'drag-lint.json')))) ($r.Out + $r.Err)

# ---- V: the way back ----
$p = Get-Plan $copyL $roamL @{ DRAGLINT_LAYOUT = 'v1' }
Check 'V1 DRAGLINT_LAYOUT=v1 is OFF: the roaming manifest is not read' ($p.Key -notmatch 'SecL=') $p.Raw

$env:APPDATA = $realAppData
$env:LOCALAPPDATA = $realLocal
$realAfter = $realWatch | ForEach-Object { Get-Stamp $_ }
Check 'R1 the real manifest locations did not change' ((($realBefore) -join '|') -ceq (($realAfter) -join '|')) "before=$($realBefore -join '|') after=$($realAfter -join '|')"
}
finally {
  foreach ($n in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $savedEnv[$n]) }
  if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: could not delete $WorkDir" } }
}
if ($script:fail) { exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
