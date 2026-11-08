# run_cyclefix_guarded_uses_dcc.ps1 -- lane 148 CY (fabcyc case 9): a removed uses entry inside a
# single-branch conditional region ($IFDEF X ... $ENDIF, no ELSE, no nesting) is removed WITH its guard
# when every entry of the region goes; real dcc proves it.
#
#   g1  plan: no `refused: directive`; the guarded block is removed     (RED on 1.46.0 / 147-int: directive)
#   g2  --apply: exit 0, no refusal; builds; stdout byte-identical; GuA.pas no longer names GU_EXTRA
#   g3  no cycle after a re-index
#   n1  an ELSE branch: still refused directive (multi-branch is not provable)
#   n2  a region with an entry that stays: still refused directive
#   n3  the region inactive in the build (GU_EXTRA undefined): the index sees no edge, no cycle, nothing planned
#
# Usage: pwsh -File run_cyclefix_guarded_uses_dcc.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-KeepWorkDir]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-guarded-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepWorkDir
)
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
# A private copy of a fixture, patched, indexed. $Fix is a tests\fixtures\cyclefix name or a repo-relative dir.
function New-Proj([string]$Fix, [string]$Name, [scriptblock]$Patch = $null) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  $from = Join-Path $Repo "tests\fixtures\cyclefix\$Fix"
  if (-not (Test-Path $from)) { $from = Join-Path $Repo $Fix }
  Get-ChildItem $from -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Patch) { & $Patch $root }
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root "$Name.dproj") --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root "$Name.dproj"); Db = $db; Name = $Name }
}
function Run-Fix($P, [string[]]$Extra) {
  $a = @('cycles', '--fix', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', 'none', '--format', 'json') + $Extra
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += $x.kind } } }
  foreach ($x in @($j.refusals)) { if ($x) { $k += $x.kind } }
  $r = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $r += "$($x.kind): $($x.reason)" } } }
  return @{ Exit = $code; Out = $out; Kinds = $k; Reasons = ($r -join ' || ') }
}
function Refused($P) { return Run-Fix $P @('--no-compile', '--shadow-out', "$($P.Root)-shadow") }
function Get-Plan($P) {
  Push-Location $WorkDir
  try { return ($null | & $Exe cycles --plan --project $P.Dproj --db $P.Db --library-db none 2>$null | Out-String) } finally { Pop-Location }
}
function Get-Cycles($P) {
  Push-Location $WorkDir
  try {
    $null | & $Exe index --project $P.Dproj --db $P.Db --library-db none *> "$($P.Db).relog"
    return ($null | & $Exe cycles --db $P.Db --library-db none 2>$null | Out-String)
  } finally { Pop-Location }
}
function Invoke-Build($P) {
  $bat = "$($P.Root).build.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $P.Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $P.Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program($P) {
  $exeP = Join-Path $P.Root "Win64\Debug\$($P.Name).exe"
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii)
}
# Applies the plan on one copy and proves it: exit 0, no refusal, cycle gone, builds, same stdout as an untouched copy.
function Prove-Apply([string]$Tag, [string]$Fix, [string]$Name, [scriptblock]$Patch = $null, [string[]]$Extra = @()) {
  $base = New-Proj $Fix $Name $Patch
  $b0 = Invoke-Build $base
  Check "$Tag untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program $base
  $P = New-Proj $Fix $Name $Patch
  $a = Run-Fix $P (@('--apply') + $Extra)
  Check "$Tag --apply: exit 0, no refusal" (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons) $($a.Out)"
  $b1 = Invoke-Build $P
  Check "$Tag the applied copy builds (independent msbuild)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program $P
  Check "$Tag stdout is byte-identical to the untouched build" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) "before=[$out0] after=[$out1]"
  return $P
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== g: the guarded entry goes with its guard' -ForegroundColor Cyan
  $P0 = New-Proj 'guardeduses' 'GuardedUses'
  $plan = Get-Plan $P0
  Check 'g1.1 the plan does not refuse directive' ($plan -notmatch 'refused: directive') $plan
  Check 'g1.2 the plan removes GuB from GuA''s interface' ($plan -match '(?m)^- `GuA\.pas` / `GuB`:.*\*\*remove\*\*') $plan
  $P = Prove-Apply 'g2' 'guardeduses' 'GuardedUses'
  $ga = [IO.File]::ReadAllText((Join-Path $P.Root 'GuA.pas'), $Ascii)
  Check 'g2.4 GuA.pas: the guard and the entry are gone, System.SysUtils stays' (($ga -notmatch 'GU_EXTRA') -and ($ga -notmatch '\bGuB\b') -and ($ga -match '(?m)^uses\s+System\.SysUtils;')) $ga
  $left = Get-Cycles $P
  Check 'g3 no cycle after a re-index' ($left -match 'No circular unit dependencies found\.') $left

  Write-Host '== n: what stays refused' -ForegroundColor Cyan
  $E = New-Proj 'guardeduses' 'GuardedUses' { param($r) Edit-Text (Join-Path $r 'GuA.pas') "{`$IFDEF GU_EXTRA}`n  GuB,`n{`$ENDIF}" "{`$IFDEF GU_EXTRA}`n  GuB,`n{`$ELSE}`n  System.Classes,`n{`$ENDIF}" }
  $r = Refused $E
  Check 'n1 an ELSE branch: refused directive' (($r.Exit -eq 1) -and ($r.Kinds -contains 'directive')) "exit=$($r.Exit) kinds=$($r.Kinds -join ',') $($r.Reasons)"
  $S = New-Proj 'guardeduses' 'GuardedUses' { param($r) Edit-Text (Join-Path $r 'GuA.pas') "{`$IFDEF GU_EXTRA}`n  GuB,`n{`$ENDIF}" "{`$IFDEF GU_EXTRA}`n  GuB,`n  System.Classes,`n{`$ENDIF}" }
  $r = Refused $S
  Check 'n2 an entry of the region stays: refused directive' (($r.Exit -eq 1) -and ($r.Kinds -contains 'directive')) "exit=$($r.Exit) kinds=$($r.Kinds -join ',') $($r.Reasons)"
  $I = New-Proj 'guardeduses' 'GuardedUses' { param($r) Edit-Text (Join-Path $r 'GuardedUses.dproj') 'GU_EXTRA;' '' }
  $c = ($null | & $Exe cycles --db $I.Db --library-db none 2>$null | Out-String)
  Check 'n3 the region inactive in the build: no edge, no cycle' ($c -match 'No circular unit dependencies found\.') $c
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_guarded_uses_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }