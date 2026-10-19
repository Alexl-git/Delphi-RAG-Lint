<#
  run_cyclefix_edge_surface.ps1 -- E18 Task 4: the per-edge surface (TEdgeSurface) of
  `cycles --format json --causes`.

  Every circular group gets an `edges[]` array, one entry per uses edge inside the group:
  {from, to, surface:{members, has_write, has_construction, has_class_method, routine,
  routine_sig, sig_types:[{name, unit, in_scc}], call_count, ...}}. Asserted on the demo:
    demouiconnect -> demogageport           members [LastGage, Log], no construction, no write
    demogageport  -> demouiconnect          construction + write (GDemoUIConnect :=)
    demoblueprint -> demoblueprint.viewmodel one routine, its verbatim signature, its sig types
    democontrolplan -> demoblueprint        class method (CreateForFolder)
  Without --causes the JSON carries no `edges` key (the chart's default call stays fast).

  POSITIVE CONTROL: a demo copy whose DemoUIConnect also CONSTRUCTS TDemoGagePort must flip
  has_construction to true on demouiconnect -> demogageport, so the `false` assertion above
  is not vacuous.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cycle-edge-surface-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Copies the demo into $WorkDir\<Tag>, indexes it, returns the DB path.
function New-Demo([string]$Tag) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'circular-demo') -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) -Force }
  return $root
}
function Index-Demo([string]$Root, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $Root 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  Check "$Tag indexed" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  return $db
}
# Runs `cycles --format json` with the given extra flags; returns the parsed groups (or $null).
function Get-Groups([string]$Db, [string[]]$Extra, [string]$Tag) {
  $o = Join-Path $WorkDir "cycles-$Tag.json"; $e = Join-Path $WorkDir "cycles-$Tag.err"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $Db + '"'), '--format', 'json') + $Extra) `
    -RedirectStandardOutput $o -RedirectStandardError $e
  Check "cycles $Tag exit 0" ($p.ExitCode -eq 0) "exit=$($p.ExitCode)"
  try { return ,@([IO.File]::ReadAllText($o) | ConvertFrom-Json) } catch { Check "cycles $Tag is JSON" $false $_.Exception.Message; return ,@() }
}
function Find-Edge($Groups, [string]$From, [string]$To) {
  foreach ($g in $Groups) {
    if ($null -eq $g.PSObject.Properties['edges']) { continue }
    foreach ($ed in @($g.edges)) { if ($ed.from -eq $From -and $ed.to -eq $To) { return $ed } }
  }
  return $null
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
$db = Index-Demo (New-Demo 'demo') 'demo'

Write-Host '== without --causes: no edges key' -ForegroundColor Cyan
$plain = Get-Groups $db @() 'plain'
Check 'p0 three groups' ($plain.Count -eq 3) "groups=$($plain.Count)"
Check 'p1 no group has an edges key' (@($plain | Where-Object { $null -ne $_.PSObject.Properties['edges'] }).Count -eq 0)

Write-Host '== --edges --causes: per-edge surfaces' -ForegroundColor Cyan
$groups = Get-Groups $db @('--edges', '--causes') 'causes'
Check 'e0 three groups' ($groups.Count -eq 3) "groups=$($groups.Count)"
Check 'e1 every group has an edges array' (@($groups | Where-Object { $null -eq $_.PSObject.Properties['edges'] }).Count -eq 0)

$ui = Find-Edge $groups 'demouiconnect' 'demogageport'
Check 'u0 edge demouiconnect -> demogageport present' ($null -ne $ui)
if ($null -ne $ui) {
  $s = $ui.surface
  Check 'u1 members = [LastGage, Log]' ((@($s.members) -join ',') -ceq 'LastGage,Log') ('members=' + (@($s.members) -join ','))
  Check 'u2 has_construction = false' ($s.has_construction -eq $false) "has_construction=$($s.has_construction)"
  Check 'u3 has_write = false' ($s.has_write -eq $false) "has_write=$($s.has_write)"
}
$gp = Find-Edge $groups 'demogageport' 'demouiconnect'
Check 'g0 edge demogageport -> demouiconnect present' ($null -ne $gp)
if ($null -ne $gp) {
  Check 'g1 has_construction = true' ($gp.surface.has_construction -eq $true) "has_construction=$($gp.surface.has_construction)"
  Check 'g2 has_write = true (GDemoUIConnect :=)' ($gp.surface.has_write -eq $true) "has_write=$($gp.surface.has_write)"
}
$bp = Find-Edge $groups 'demoblueprint' 'demoblueprint.viewmodel'
Check 'b0 edge demoblueprint -> demoblueprint.viewmodel present' ($null -ne $bp)
if ($null -ne $bp) {
  $s = $bp.surface
  Check 'b1 routine = DemoBlueprintViewModelCreate' ($s.routine -ceq 'DemoBlueprintViewModelCreate') "routine=$($s.routine)"
  Check 'b2 routine_sig verbatim' ($s.routine_sig -ceq '(const pFolderId: Integer): IDemoBlueprintViewModel') "routine_sig=$($s.routine_sig)"
  $st = @($s.sig_types | ForEach-Object { '{0}|{1}|{2}' -f $_.name, $_.unit, $_.in_scc })
  Check 'b3 sig_types = Integer(``,false), IDemoBlueprintViewModel(demoblueprint.interfaces,false)' `
    (($st -join ';') -ceq 'Integer||False;IDemoBlueprintViewModel|demoblueprint.interfaces|False') ('sig_types=' + ($st -join ';'))
  Check 'b4 call_count = 1' ($s.call_count -eq 1) "call_count=$($s.call_count)"
}
$cp = Find-Edge $groups 'democontrolplan' 'demoblueprint'
Check 'c0 edge democontrolplan -> demoblueprint present' ($null -ne $cp)
if ($null -ne $cp) { Check 'c1 has_class_method = true (CreateForFolder)' ($cp.surface.has_class_method -eq $true) "has_class_method=$($cp.surface.has_class_method)" }

Write-Host '== positive control: DemoUIConnect constructs TDemoGagePort' -ForegroundColor Cyan
$ctlRoot = New-Demo 'ctl'
$f = Join-Path $ctlRoot 'DemoUIConnect.pas'
$t = [IO.File]::ReadAllText($f)
$t2 = $t.Replace("  if not (Owner is TDemoGagePort) then`r`n", "  TDemoGagePort.Create(nil).Free;`r`n  if not (Owner is TDemoGagePort) then`r`n")
Check 'k0 control mutation applied' ($t2 -ne $t)
[IO.File]::WriteAllText($f, $t2, [Text.Encoding]::ASCII)
$ctlDb = Index-Demo $ctlRoot 'ctl'
$ctl = Find-Edge (Get-Groups $ctlDb @('--causes') 'ctl') 'demouiconnect' 'demogageport'
Check 'k1 control: has_construction flips to true' (($null -ne $ctl) -and ($ctl.surface.has_construction -eq $true)) $(if ($ctl) { "has_construction=$($ctl.surface.has_construction)" } else { 'edge missing' })
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
