# run_v152_HUB_default.ps1 -- lane v152 HUB (owner ruling B9b): the hub surface (recipe R3) is the DEFAULT for
# `cycles --causes --format json`, `cycles --plan --apply` and `cycles --fix` -- for a group R3 predicts to BREAK;
# every other group gets exactly the old default. `--no-hub-surface` restores the old default everywhere.
# Plus the four R3 findings of the 1.51.1 website review. Fixture tests\fixtures\cyclefix\hubsurface (one hub
# HubMain, global HubMainForm, three spokes) and tests\fixtures\cyclefix\guardeduses (a two-unit knot, not
# hub-shaped). Every project is a copy under -WorkDir; real dcc only where a check says "dcc".
#
#   j1  --causes --format json (no switch) on the hub group = byte-identical to --hub-surface (part r3)  (RED on 1.51.1)
#   j2  control: --causes --format json --no-hub-surface: the planner's fix object (part is not r3)
#   j3  a knot R3 does not plan: the default = --no-hub-surface, byte for byte (no r3, no note)
#   x1  --fix --cycle 1 (no switch), dry run: cycle-fix/1 part r3 recipe hub-surface, byte-identical to --hub-surface
#                                                                                                       (RED on 1.51.1)
#   x2  control: --fix --no-hub-surface: the planner's fix (part is not r3)
#   x3  a knot: --fix default = --fix --no-hub-surface, byte for byte (not refused not-hub-shaped)
#   x4  a hub group R3 plans but cannot break (`with HubMainForm do`): default --fix = --no-hub-surface, byte for byte
#   x5  --fix --hub-surface --no-hub-surface: exit 2
#   a1  --plan --cycle 1 --apply (no switch) writes R3: HubMain.Hub.pas + rewritten spokes, the same bytes as
#       --plan --hub-surface --apply on a twin copy                                                    (RED on 1.51.1)
#   a2  control: --plan --apply --no-hub-surface writes nothing (the old default)
#   r1  review #1 (E2197): a spoke passing HubMainForm.Counter to a `var` parameter is refused (var argument) at PLAN
#       time -- the dry run no longer says mechanical, so --apply never writes and rolls back
#   r2  review #2: the refusal line names a place, never ` :0` / `.dproj:0`; its way back is --no-hub-surface
#   r3  review #3 (dcc): the accessor block in the hub class is indented like the class's own sections
#   r4  review #4: --help no longer says --plan --apply / --fix need --hub-surface by name, and names --no-hub-surface
#
# Usage: pwsh -File run_v152_HUB_default.ps1 -Exe <drag-lint.exe> [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-hub-$PID",
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
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$HaveDcc = Test-Path $RsVars
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
  try { $null | & { $ErrorActionPreference = 'Continue'; $input | & $Exe index --project (Join-Path $root "$Name.dproj") --db $db --library-db none *> "$db.log" } } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root "$Name.dproj"); Db = $db; Name = $Name }
}
# One `cycles` run; stdout only (stderr apart). The project path is replaced by <P> so two twin copies compare.
function Invoke-Cycles($P, [string[]]$A) {
  $a = @('cycles', '--db', $P.Db, '--library-db', 'none') + $A
  $errFile = "$($P.Root).c$script:N.$([guid]::NewGuid().ToString('N').Substring(0,6)).err"
  Push-Location $WorkDir
  try { $out = ($null | & { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($errFile); [IO.File]::WriteAllText($dlErrFile, ''); $input | & $Exe @a 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } } | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  $norm = $out.Replace($P.Root, '<P>').Replace(($P.Root -replace '\\', '\\'), '<P>').Replace($P.Db, '<DB>').Replace(($P.Db -replace '\\', '\\'), '<DB>') -replace 'draglint_cyclefix_\d+', 'draglint_cyclefix_N'
  $doc = $null
  if ($A -contains 'json') { try { $doc = $out | ConvertFrom-Json | ForEach-Object { $_ } } catch { $doc = $null } }
  return @{ Exit = $code; Out = $out; Norm = $norm; Err = $err; Doc = $doc }
}
function FixArgs($P, [string[]]$Extra) {
  return @('--fix', '--project', $P.Dproj, '--platform', 'win64', '--build-timeout', '600') + $Extra
}
function CausesFix($r) { try { return @($r.Doc)[0].fix } catch { return $null } }
$WithSpoke = { param($r) Edit-Text (Join-Path $r 'HubSpokeC.pas') "  hubMainForm.log.Add(" "  with HubMainForm do`n    Note('w');`n  hubMainForm.log.Add(" }
$VarArg = { param($r)
  Edit-Text (Join-Path $r 'HubSpokeA.pas') "procedure SpokeA;`nbegin`n  Inc(HubMainForm.Counter, 2);" "procedure AddTwo(var pN: Integer);`nbegin`n  Inc(pN, 2);`nend;`n`nprocedure SpokeA;`nbegin`n  AddTwo(HubMainForm.Counter);" }

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== j: cycles --causes --format json' -ForegroundColor Cyan
  $H = New-Proj 'hubsurface' 'HubSurface'
  $jd = Invoke-Cycles $H @('--causes', '--format', 'json')
  $jh = Invoke-Cycles $H @('--causes', '--format', 'json', '--hub-surface')
  $jn = Invoke-Cycles $H @('--causes', '--format', 'json', '--no-hub-surface')
  Write-Host "      raw default fix: $((CausesFix $jd) | ConvertTo-Json -Compress -Depth 3)" -ForegroundColor DarkGray
  Check 'j1 --causes json default = --hub-surface byte for byte (fix.part r3)   (RED on 1.51.1)' (($jd.Exit -eq 0) -and
    ($jd.Out -eq $jh.Out) -and ((CausesFix $jd).part -eq 'r3')) "exit=$($jd.Exit) part=$((CausesFix $jd).part)"
  Check 'j2 control: --no-hub-surface = the planner''s fix object (part is not r3)' (($jn.Exit -eq 0) -and ($null -ne (CausesFix $jn)) -and
    ((CausesFix $jn).part -ne 'r3')) "exit=$($jn.Exit) part=$((CausesFix $jn).part)"
  $K = New-Proj 'guardeduses' 'GuardedUses'
  $kd = Invoke-Cycles $K @('--causes', '--format', 'json')
  $kn = Invoke-Cycles $K @('--causes', '--format', 'json', '--no-hub-surface')
  Check 'j3 a knot: the default = --no-hub-surface byte for byte' (($kd.Exit -eq $kn.Exit) -and ($kd.Out -eq $kn.Out) -and ($kd.Out.Length -gt 0)) "$($kd.Out) // $($kn.Out)"

  Write-Host '== x: cycles --fix (dry run, --no-compile)' -ForegroundColor Cyan
  $xd = Invoke-Cycles $H (FixArgs $H @('--cycle', '1', '--format', 'json', '--no-compile'))
  $xh = Invoke-Cycles $H (FixArgs $H @('--cycle', '1', '--format', 'json', '--no-compile', '--hub-surface'))
  $xn = Invoke-Cycles $H (FixArgs $H @('--cycle', '1', '--format', 'json', '--no-compile', '--no-hub-surface'))
  $xc = if ($xd.Doc) { @($xd.Doc.cycles)[0] } else { $null }
  Check 'x1 --fix default: part r3, recipe hub-surface, = --hub-surface byte for byte   (RED on 1.51.1)' (($xd.Exit -eq 0) -and ($null -ne $xc) -and
    ($xc.part -eq 'r3') -and ($xc.recipe -eq 'hub-surface') -and ($xd.Norm -eq $xh.Norm)) "exit=$($xd.Exit) part=$($xc.part) out=$($xd.Out.Substring(0, [Math]::Min(400, $xd.Out.Length)))"
  $nc = if ($xn.Doc) { @($xn.Doc.cycles)[0] } else { $null }
  Check 'x2 control: --fix --no-hub-surface = the planner (part is not r3)' (($null -ne $nc) -and ($nc.part -ne 'r3') -and ($nc.recipe -ne 'hub-surface')) "exit=$($xn.Exit) $($xn.Out)"
  $kfd = Invoke-Cycles $K (FixArgs $K @('--cycle', '1', '--format', 'json', '--no-compile'))
  $kfn = Invoke-Cycles $K (FixArgs $K @('--cycle', '1', '--format', 'json', '--no-compile', '--no-hub-surface'))
  Check 'x3 a knot: --fix default = --no-hub-surface byte for byte (not refused not-hub-shaped)' (($kfd.Exit -eq $kfn.Exit) -and
    ($kfd.Norm -eq $kfn.Norm) -and -not $kfd.Out.Contains('not-hub-shaped')) "exit=$($kfd.Exit)/$($kfn.Exit) $($kfd.Out)"
  $W = New-Proj 'hubsurface' 'HubSurface' $WithSpoke
  $wd = Invoke-Cycles $W (FixArgs $W @('--cycle', '1', '--format', 'json', '--no-compile'))
  $wn = Invoke-Cycles $W (FixArgs $W @('--cycle', '1', '--format', 'json', '--no-compile', '--no-hub-surface'))
  $wh = Invoke-Cycles $W (FixArgs $W @('--cycle', '1', '--format', 'json', '--no-compile', '--hub-surface'))
  Check 'x4 a hub group R3 cannot break: default --fix = --no-hub-surface byte for byte; --hub-surface still refuses it' (($wd.Exit -eq $wn.Exit) -and
    ($wd.Norm -eq $wn.Norm) -and $wh.Out.Contains('hub-surface-group-stays')) "exit=$($wd.Exit)/$($wn.Exit)/$($wh.Exit)"
  $bad = Invoke-Cycles $H (FixArgs $H @('--cycle', '1', '--no-compile', '--hub-surface', '--no-hub-surface'))
  Check 'x5 --fix --hub-surface --no-hub-surface: exit 2' ($bad.Exit -eq 2) "exit=$($bad.Exit) $($bad.Err)"

  Write-Host '== a: cycles --plan --apply' -ForegroundColor Cyan
  $A1 = New-Proj 'hubsurface' 'HubSurface'
  $A2 = New-Proj 'hubsurface' 'HubSurface'
  $ad = Invoke-Cycles $A1 @('--plan', '--cycle', '1', '--apply', '--no-backup')
  $ah = Invoke-Cycles $A2 @('--plan', '--cycle', '1', '--apply', '--no-backup', '--hub-surface')
  Check 'a1 --plan --apply default writes R3: the same bytes as --hub-surface --apply   (RED on 1.51.1)' (($ad.Exit -eq 0) -and
    (Test-Path (Join-Path $A1.Root 'HubMain.Hub.pas')) -and ((Get-SrcHash $A1.Root) -eq (Get-SrcHash $A2.Root))) "exit=$($ad.Exit)/$($ah.Exit) $($ad.Out.Substring(0, [Math]::Min(300, $ad.Out.Length))) $($ad.Err)"
  $A3 = New-Proj 'hubsurface' 'HubSurface'
  $a30 = Get-SrcHash $A3.Root
  $an = Invoke-Cycles $A3 @('--plan', '--cycle', '1', '--apply', '--no-hub-surface')
  Check 'a2 control: --plan --apply --no-hub-surface writes nothing' (((Get-SrcHash $A3.Root) -eq $a30) -and
    -not (Test-Path (Join-Path $A3.Root 'HubMain.Hub.pas'))) "exit=$($an.Exit)"

  Write-Host '== r: the 1.51.1 website review' -ForegroundColor Cyan
  $V = New-Proj 'hubsurface' 'HubSurface' $VarArg
  $v0 = Get-SrcHash $V.Root
  $vt = Invoke-Cycles $V (FixArgs $V @('--cycle', '1', '--no-compile', '--hub-surface'))
  Write-Host "      raw: $(($vt.Out -split "`r?`n" | Select-String 'spokes:|refused|Verdict' | ForEach-Object Line) -join ' | ')" -ForegroundColor DarkGray
  Check 'r1 review #1: a hub field passed to a var parameter refuses its spoke at plan time (no write, no E2197 rollback)' (
    ($vt.Exit -eq 1) -and ($vt.Out -match 'refused `HubSpokeA\.pas`: [a-z-]+ -- line \d+: .*var') -and -not $vt.Out.Contains('Verdict: mechanical') -and
    ((Get-SrcHash $V.Root) -eq $v0)) "exit=$($vt.Exit) $($vt.Out)"
  $Ws = Invoke-Cycles $W (FixArgs $W @('--cycle', '1', '--no-compile', '--hub-surface'))
  $refLine = ($Ws.Out -split "`r?`n" | Where-Object { $_ -match '^\s*- hub-surface-group-stays\b' }) -join ''
  Write-Host "      raw: $refLine" -ForegroundColor DarkGray
  Check 'r2 review #2: the group refusal names no `:0` place' (($refLine -ne '') -and ($refLine -notmatch ':0\b') -and ((($refLine -split ' -- ')[0]) -notmatch ':\s*$') -and ($refLine -match '--no-hub-surface\)')) $refLine
  $Hc = New-Proj 'hubsurface' 'HubSurface'
  $hh = Invoke-Cycles $Hc @('--plan', '--cycle', '1', '--apply', '--no-backup', '--hub-surface')
  $hub = [IO.File]::ReadAllText((Join-Path $Hc.Root 'HubMain.pas'), $Ascii)
  Write-Host "      raw: $(($hub -split "`r`n" | Select-String 'drag-lint cycles --hub-surface: the|HubGetCounter: Integer;$|AfterConstruction; override' | ForEach-Object { '[' + $_.Line + ']' }) -join ' ')" -ForegroundColor DarkGray
  Check 'r3 review #3: the accessor block sits at the class''s section column (2), its members at 4' (($hh.Exit -eq 0) -and
    ($hub -match "`r`n  private \{ drag-lint cycles --hub-surface") -and ($hub -match "`r`n    function HubGetCounter: Integer;`r`n") -and
    ($hub -match "`r`n  public`r`n    procedure AfterConstruction; override;")) "exit=$($hh.Exit)"
  if ($HaveDcc) {
    $Hd = New-Proj 'hubsurface' 'HubSurface'
    $hf = Invoke-Cycles $Hd (FixArgs $Hd @('--cycle', '1', '--apply', '--format', 'json'))
    $hfc = if ($hf.Doc) { @($hf.Doc.cycles)[0] } else { $null }
    Check 'r3b (dcc) default --fix --apply on the hub group: r3, compile ok, verified' (($hf.Exit -eq 0) -and ($null -ne $hfc) -and
      ($hfc.part -eq 'r3') -and ($hfc.compile.status -eq 'ok') -and ($hfc.verified -eq $true)) "exit=$($hf.Exit) $($hf.Out) $($hf.Err)"
  } else { Write-Host '  [SKIP] r3b: no rsvars.bat' -ForegroundColor Yellow }
  $help = (& { $ErrorActionPreference = 'Continue'; & $Exe cycles --help 2>&1 | ForEach-Object { "$_" } } | Out-String)
  $cyc = ($help -split "`r?`n" | Where-Object { $_ -match '^\s*drag-lint cycles\b' }) -join "`n"
  Check 'r4 review #4: --help names --no-hub-surface on every cycles line and says nothing of a missing compile gate / switch-by-name' (
    ($cyc -ne '') -and (@($help -split "`r?`n" | Where-Object { $_ -match '^\s*drag-lint cycles\b' -and $_ -notmatch '--no-hub-surface' }).Count -eq 0) -and
    ($help -notmatch 'runs no compile gate|no compile gate yet|cannot run R3 yet|needs? the switch by name')) $cyc
} finally {
  if (-not $KeepWorkDir) {
    Set-Location -LiteralPath $env:TEMP
    if (Test-Path -LiteralPath $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: work dir not removed: $WorkDir" } }
  } else { Write-Host "work dir kept: $WorkDir" }
}
Write-Host ("{0} passed, failed={1}" -f $script:Passed, $script:Failed)
if ($script:Failed) { exit 1 } else { exit 0 }
