#Requires -Version 7
<#
  run_v156_G62R.ps1 -- 1.56 lane G62R (gap G-62): ui-call-in-console-or-service follows METHODS across units.
  The v152 APP2 / 1.54.1 UICALL pass was text based and followed stand-alone routines only. The new pass walks
  resolved call edges (a console program's main block, or a method of a TService descendant) back from every
  routine that shows a dialog or has a ui_affinity, over at most 8 hops, cycle guarded, and prints the chain.

  Fixtures tests\fixtures\v156-g62r\{console,service,gui}: UFoo.TFoo (Greet shows a dialog; Wrap -> Greet;
  Quiet is silent; Ping <-> Pong with Pong showing a dialog; Loop1 <-> Loop2 with no dialog; ShowDone is a
  stand-alone dialog routine).
    c1  console: ConsoleProg.dpr line 13 (F.Greet, a method) fires
    c2  console: line 14 (F.Wrap -> Greet, chain) fires and the message names the chain
    c3  console: line 15 (F.Quiet) is silent
    c4  console: line 16 (F.Ping, a cycle that reaches a dialog) fires
    c5  console: line 17 (F.Loop1, a cycle with no dialog) is silent and the run terminates
    c6  console: line 18 (ShowDone, stand-alone) still fires, with the unchanged 1.52 message (control)
    c7  console: exactly lines 13,14,16,18
    c8  service: USvc.pas lines 22 (FFoo.Greet) and 23 (FFoo.Wrap) fire, 28 (Quiet) and 33 (Loop1) are silent
    c9  gui: no finding at all (twin of c1)
    p0  positive control: the per-file rule still fires on a direct dialog in a console file

  Usage: pwsh -File tests\autotest\run_v156_G62R.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v156_g62r_$PID"
)
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $Root 'src\cli\Win64\Debug\drag-lint.exe' }
if (-not (Test-Path $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }
. (Join-Path $PSScriptRoot 'lib\EngineCompanions.ps1')
[void](Initialize-EngineCompanions -Exe $Exe)
$Exe  = (Resolve-Path $Exe).Path
$Rule = 'ui-call-in-console-or-service'

$script:Fail = 0
$script:Pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function Get-Findings([string]$Db) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Db --json 2>$null }) -join "`n"
  Write-Host ("  raw[{0}]: {1}" -f (Split-Path $Db -Leaf), $out.Substring(0, [Math]::Min(200, $out.Length)))
  if ($out.Trim() -eq '') { return @() }
  return @($out | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.rule -eq $Rule })
}
function In-File($Findings, [string]$Name) { @($Findings | Where-Object { [IO.Path]::GetFileName([string]$_.file_path) -eq $Name }) }

[void](New-Item -ItemType Directory -Force -Path $WorkDir)
$Fix = Join-Path $Root 'tests\fixtures\v156-g62r'
foreach ($k in 'console', 'service', 'gui') { Copy-Item (Join-Path $Fix $k) $WorkDir -Recurse -Force }
Push-Location $WorkDir
try {
  foreach ($k in 'console', 'service', 'gui') {
    & { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $WorkDir $k) --db (Join-Path $WorkDir "$k.sqlite") *> (Join-Path $WorkDir "index-$k.log") }
  }
  $c0 = Join-Path $WorkDir 'Direct.pas'
  [IO.File]::WriteAllText($c0, "program Direct;`r`n`r`n{`$APPTYPE CONSOLE}`r`n`r`nuses Vcl.Dialogs;`r`n`r`nbegin`r`n  ShowMessage('x');`r`nend.`r`n")
  $d = (& { $ErrorActionPreference = 'Continue'; & $Exe lint $c0 --json 2>$null }) -join "`n"
  $d0 = @(if ($d.Trim() -eq '') { @() } else { @($d | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object { $_.rule -eq $Rule }) })
  Check 'p0 positive control: per-file rule fires on a direct dialog call' ($d0.Count -ge 1) "raw: $d"

  $fc   = Get-Findings (Join-Path $WorkDir 'console.sqlite')
  $prog = In-File $fc 'ConsoleProg.dpr'
  $lines = @($prog | ForEach-Object { [int]$_.start_line } | Sort-Object)
  Write-Host ("  console ConsoleProg.dpr lines: " + ($lines -join ','))
  $m14 = [string](@($prog | Where-Object { $_.start_line -eq 14 })[0].message)
  $m18 = [string](@($prog | Where-Object { $_.start_line -eq 18 })[0].message)
  Check 'c1 console: F.Greet (method) fires'                 ($lines -contains 13)
  Check 'c2 console: F.Wrap fires and names the chain'       (($lines -contains 14) -and $m14 -match 'Wrap' -and $m14 -match 'Greet' -and $m14 -match '->') "msg: $m14"
  Check 'c3 console: F.Quiet is silent'                      (-not ($lines -contains 15))
  Check 'c4 console: F.Ping (cycle reaching a dialog) fires' ($lines -contains 16)
  Check 'c5 console: F.Loop1 (cycle, no dialog) is silent'   (-not ($lines -contains 17))
  Check 'c6 console: ShowDone still fires, 1.52 message'     (($lines -contains 18) -and $m18 -like 'Call to ShowDone (unit ufoo) shows a dialog in a console program*') "msg: $m18"
  Check 'c7 console: exactly 13,14,16,18'                    (($lines -join ',') -eq '13,14,16,18') ("got " + ($lines -join ','))

  $fs = Get-Findings (Join-Path $WorkDir 'service.sqlite')
  $sl = @((In-File $fs 'USvc.pas') | ForEach-Object { [int]$_.start_line } | Sort-Object)
  Write-Host ("  service USvc.pas lines: " + ($sl -join ','))
  Check 'c8 service: Greet and Wrap fire, Quiet and Loop1 silent' (($sl -join ',') -eq '22,23') ("got " + ($sl -join ','))

  $fg = Get-Findings (Join-Path $WorkDir 'gui.sqlite')
  Check 'c9 gui: no finding' ($fg.Count -eq 0) ("got " + $fg.Count)
}
finally { Pop-Location }

Write-Host ("run_v156_G62R: {0} pass, {1} failure(s)" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
