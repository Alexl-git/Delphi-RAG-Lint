# run_v1511_CYC_fix_hubsurface.ps1 -- lane v1511 CYC (T06): `cycles --fix --hub-surface` runs recipe R3 through the
# compile gate (the IDE's Fix-it verb), on the hub-shaped fixture tests\fixtures\cyclefix\hubsurface.
# Real dcc; every project is a copy under -WorkDir.
#
#   f0  dry run, json: exit 0, cycle-fix/1, part r3, recipe hub-surface, verdict mechanical, baseline ok, new unit
#       HubMain.Hub, sources unchanged                                  (RED on 1.51.0: exit 2, "does not combine with --fix")
#   f1  dry run, text: the R3 block and `Verdict: mechanical`
#   f2  --apply, json: exit 0; build 1 (baseline) and build 2 (after the edit) both on stderr; compile ok; HubMain.Hub.pas
#       written; the re-indexed `cycles` matches the prediction (verified)
#   f3  --apply with a broken rewrite (test seam DRAGLINT_CYCLEFIX_BREAK=3): exit 1, compile error, rolled back,
#       sources byte-identical, no HubMain.Hub.pas
#   f4  a group R3 plans but cannot break (`with HubMainForm do`): exit 1, refusal hub-surface-group-stays; --apply writes nothing
#   f5  a two-unit knot: exit 1, refusal not-hub-shaped
#   f6  --part with --hub-surface: exit 2
#   f7  control (O11, default NOT flipped): `--fix` without the switch is the planner's, part is not r3
#   f8  `--causes --format json --hub-surface`: the fix object's commands are the gated `cycles --fix --hub-surface`
#   f9  a project that does not build before the edit: exit 1, dirty-baseline, nothing written
#
# Usage: pwsh -File run_v1511_CYC_fix_hubsurface.ps1 -Exe <drag-lint.exe> [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v1511-cyc-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$script:N = 0

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function New-Proj([string]$Fix, [string]$Name, [scriptblock]$Patch = $null) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  $from = Join-Path $Repo "tests\fixtures\cyclefix\$Fix"
  Get-ChildItem $from -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $root "$Name.dproj") --db $db --library-db none *> "$db.log" } } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root "$Name.dproj"); Db = $db; Name = $Name }
}
# One `cycles --fix` run; stdout and stderr apart (the build progress lines go to stderr).
function Invoke-Fix($P, [string[]]$Extra = @(), [hashtable]$EnvVars = @{}) {
  $a = @('cycles', '--fix', '--project', $P.Dproj, '--db', $P.Db, '--library-db', 'none', '--platform', 'win64', '--build-timeout', '600') + $Extra
  $errFile = "$($P.Root).fix$script:N.err"
  foreach ($k in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($k, $EnvVars[$k]) }
  Push-Location $WorkDir
  try { $out = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe @a 2> $errFile } | Out-String); $code = $LASTEXITCODE }
  finally {
    Pop-Location
    foreach ($k in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($k, $null) }
  }
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  $doc = $null
  if ($Extra -contains 'json') { try { $doc = $out | ConvertFrom-Json } catch { $doc = $null } }
  return @{ Exit = $code; Out = $out; Err = $err; Doc = $doc }
}
function Has([string]$Text, [string]$Literal) { return $Text.Contains($Literal) }
$WithSpoke = { param($r) Edit-Text (Join-Path $r 'HubSpokeC.pas') "  hubMainForm.log.Add(" "  with HubMainForm do`n    Note('w');`n  hubMainForm.log.Add(" }

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== f: cycles --fix --hub-surface (R3 through the compile gate)' -ForegroundColor Cyan
  $P = New-Proj 'hubsurface' 'HubSurface'
  $h0 = Get-SrcHash $P.Root
  $r = Invoke-Fix $P @('--hub-surface', '--cycle', '1', '--format', 'json')
  $c = if ($r.Doc) { @($r.Doc.cycles)[0] } else { $null }
  Check 'f0 dry run json: exit 0, part r3, recipe hub-surface, mechanical, baseline ok, new unit HubMain.Hub, nothing written   (RED on 1.51.0: exit 2)' (
    ($r.Exit -eq 0) -and ($null -ne $c) -and ($r.Doc.schema -eq 'cycle-fix/1') -and ($c.part -eq 'r3') -and ($c.recipe -eq 'hub-surface') -and
    ($c.verdict -eq 'mechanical') -and ($r.Doc.baseline.status -eq 'ok') -and (@($c.new_units)[0].unit -eq 'HubMain.Hub') -and
    ((Get-SrcHash $P.Root) -eq $h0) -and -not (Test-Path (Join-Path $P.Root 'HubMain.Hub.pas'))) "exit=$($r.Exit) out=$($r.Out) err=$($r.Err)"

  $t = Invoke-Fix $P @('--hub-surface', '--cycle', '1', '--format', 'text')
  Check 'f1 dry run text: the R3 block and the mechanical verdict' (($t.Exit -eq 0) -and (Has $t.Out 'hub-surface recipe R3') -and
    (Has $t.Out '- prediction: the group breaks') -and (Has $t.Out 'Verdict: mechanical')) "exit=$($t.Exit) $($t.Out) $($t.Err)"

  $a = Invoke-Fix $P @('--hub-surface', '--cycle', '1', '--apply', '--format', 'json')
  $ac = if ($a.Doc) { @($a.Doc.cycles)[0] } else { $null }
  Check 'f2.1 --apply: exit 0, mechanical, compile ok' (($a.Exit -eq 0) -and ($null -ne $ac) -and ($ac.verdict -eq 'mechanical') -and ($ac.compile.status -eq 'ok')) "exit=$($a.Exit) out=$($a.Out) err=$($a.Err)"
  Check 'f2.2 build 1 (baseline) and build 2 (after the edit) are reported' ((Has $a.Err 'baseline build') -and (Has $a.Err 'build after the edit')) $a.Err
  Check 'f2.3 HubMain.Hub.pas written, spokes rewritten' ((Test-Path (Join-Path $P.Root 'HubMain.Hub.pas')) -and
    (@($ac.new_files) -match 'HubMain\.Hub\.pas$').Count -eq 1 -and ([IO.File]::ReadAllText((Join-Path $P.Root 'HubSpokeA.pas')) -match 'HubMainHub\.')) "$($a.Out)"
  Check 'f2.4 re-indexed: the cycles output matches the prediction (no cycle left)' (($ac.verified -eq $true) -and ($ac.actual -match 'No circular unit dependencies')) "verified=$($ac.verified) actual=$($ac.actual) reason=$($ac.verify_reason)"

  $B = New-Proj 'hubsurface' 'HubSurface'
  $b0 = Get-SrcHash $B.Root
  $brk = Invoke-Fix $B @('--hub-surface', '--cycle', '1', '--apply', '--format', 'json') @{ DRAGLINT_CYCLEFIX_BREAK = '3' }
  $kc = if ($brk.Doc) { @($brk.Doc.cycles)[0] } else { $null }
  Check 'f3 broken rewrite: exit 1, compile error, rolled back, sources byte-identical, no new unit' (($brk.Exit -eq 1) -and ($null -ne $kc) -and
    ($kc.compile.status -eq 'error') -and ($kc.rolled_back -eq $true) -and ((Get-SrcHash $B.Root) -eq $b0) -and
    -not (Test-Path (Join-Path $B.Root 'HubMain.Hub.pas'))) "exit=$($brk.Exit) out=$($brk.Out) err=$($brk.Err)"

  $W = New-Proj 'hubsurface' 'HubSurface' $WithSpoke
  $w0 = Get-SrcHash $W.Root
  $s = Invoke-Fix $W @('--hub-surface', '--cycle', '1', '--format', 'json', '--no-compile')
  $sc = if ($s.Doc) { @($s.Doc.cycles)[0] } else { $null }
  $sa = Invoke-Fix $W @('--hub-surface', '--cycle', '1', '--apply', '--format', 'json')
  Check 'f4 the group stays: exit 1, refused hub-surface-group-stays; --apply writes nothing' (($s.Exit -eq 1) -and ($null -ne $sc) -and
    ($sc.verdict -eq 'refused') -and (@($sc.refusals)[0].kind -eq 'hub-surface-group-stays') -and ($sa.Exit -eq 1) -and
    ((Get-SrcHash $W.Root) -eq $w0)) "exit=$($s.Exit)/$($sa.Exit) out=$($s.Out) err=$($s.Err)"

  $Knot = New-Proj 'guardeduses' 'GuardedUses'
  $kn = Invoke-Fix $Knot @('--hub-surface', '--cycle', '1', '--format', 'json', '--no-compile')
  $nc = if ($kn.Doc) { @($kn.Doc.cycles)[0] } else { $null }
  Check 'f5 a two-unit knot: exit 1, refused not-hub-shaped' (($kn.Exit -eq 1) -and ($null -ne $nc) -and (@($nc.refusals)[0].kind -eq 'not-hub-shaped')) "exit=$($kn.Exit) $($kn.Out) $($kn.Err)"

  $q = Invoke-Fix $W @('--hub-surface', '--part', 'a', '--format', 'json', '--no-compile')
  Check 'f6 --part with --hub-surface: exit 2' ($q.Exit -eq 2) "exit=$($q.Exit) $($q.Out) $($q.Err)"

  $Ctl = New-Proj 'hubsurface' 'HubSurface'
  $d = Invoke-Fix $Ctl @('--cycle', '1', '--format', 'json', '--no-compile', '--no-hub-surface')
  $dc = if ($d.Doc) { @($d.Doc.cycles)[0] } else { $null }
  Check 'f7 control (O11 not flipped): --fix without the switch is the planner''s, not r3' (($null -ne $dc) -and ($dc.part -ne 'r3') -and ($dc.recipe -ne 'hub-surface')) "exit=$($d.Exit) $($d.Out)"

  Push-Location $WorkDir
  try { $js = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe cycles --causes --format json --hub-surface --project $Ctl.Dproj --db $Ctl.Db --library-db none 2>$null } | Out-String); $jsCode = $LASTEXITCODE } finally { Pop-Location }
  $fx = try { @(($js | ConvertFrom-Json) | ForEach-Object { $_ })[0].fix } catch { $null }
  Check 'f8 --causes json --hub-surface: the fix commands are the gated cycles --fix --hub-surface' (($jsCode -eq 0) -and ($null -ne $fx) -and
    ($fx.part -eq 'r3') -and ($fx.dry_run -match '^drag-lint cycles --fix --hub-surface --project ".*HubSurface\.dproj" --db ".*" --cycle 1$') -and
    ($fx.apply -match '^drag-lint cycles --fix --hub-surface --project .* --cycle 1 --apply$')) "exit=$jsCode $js"

  $Dirty = New-Proj 'hubsurface' 'HubSurface' { param($r) Edit-Text (Join-Path $r 'HubSpokeB.pas') "  if HubMainForm.Ready" "  NoSuchRoutine;`n  if HubMainForm.Ready" }
  $d0 = Get-SrcHash $Dirty.Root
  $y = Invoke-Fix $Dirty @('--hub-surface', '--cycle', '1', '--apply', '--format', 'json')
  Check 'f9 dirty baseline: exit 1, dirty-baseline, nothing written' (($y.Exit -eq 1) -and ($null -ne $y.Doc) -and
    (@($y.Doc.refusals)[0].kind -eq 'dirty-baseline') -and ((Get-SrcHash $Dirty.Root) -eq $d0)) "exit=$($y.Exit) $($y.Out) $($y.Err)"
} finally {
  if (-not $KeepWorkDir) {
    Set-Location -LiteralPath $env:TEMP
    if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: work dir not removed: $WorkDir" } }
  } else { Write-Host "work dir kept: $WorkDir" }
}
Write-Host ("{0} passed, failed={1}" -f $script:Passed, $script:Failed)
if ($script:Failed) { exit 1 } else { exit 0 }
