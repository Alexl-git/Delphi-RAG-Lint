<#
  run_v152_INITAPI_order.ps1 -- 1.52 lane INITAPI: ProgramInitOrders and InitializesBefore
  (DRagLint.Lint.InitSections), the init-order API the happens-before roots (HBROOTS) and the
  finalization-order planner (FINCUT, ruling B9a) build on.

  Fixture tests\fixtures\v152-initapi\order (indexed with the engine under test, --db in the work folder):
    P1.dpr  uses A, D; A -> B -> C, C implementation-uses A (a cycle); C's initialization reads A.GVal.
            Computed order C, B, A, D.
    P2.dpr  uses Y, V, X; X uses {$IFDEF INITAPI_FOO} Z, {$ENDIF} W. Computed order Y, V, W, X; X's
            uses clause is conditional.
  Harness tests\fixtures\v152-initapi\InitApiHarness.dpr is compiled with dcc64 against the source.

    c1  P1 order is C,B,A,D, reliable, with a program block
    c2  the SAME order as a second engine call: init-order-hazard (lint-all) reports C reading A.GVal
        because "A initializes after C in P1.dpr" -- the order the rule walks
    c3  the SAME order as the compiler: P1.exe (built from the fixture) prints INIT C, B, A, D
    c4  P2 order is Y,V,W,X and UNRELIABLE, naming X.pas
    c5  InitializesBefore P1 C A = before; A C = not-before; A A = not-before
    c6  config-dependent: P2 W Y (X, placed after both, reaches W: a DFS ancestor decides)
    c7  CONTROL: P2 Y V = before (X decides nothing about two units placed before it that it does not reach)
    c8  unplaced: an unknown unit; a unit the program does not reach; an unknown program
    c9  every program (''): C A = before; W Y = config-dependent

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v152_initapi_$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
# H01-AUTOWRAP (v152 DDFIX5): the work dir is removed in the finally below; DL_KEEP_WORKDIR=1 keeps it.
. (Join-Path $PSScriptRoot 'lib\WorkDirCleanup.ps1')
try {
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:fail = $false
function Check([bool]$Ok, [string]$What) {
  Write-Host ("{0}  {1}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $What)
  if (-not $Ok) { $script:fail = $true }
}
function Invoke-Dcc([string]$Dir, [string]$Dpr, [string]$Out, [string]$Dcu, [string]$Extra, [string]$Log) {
  $bat = Join-Path $WorkDir ("build_{0}.bat" -f [IO.Path]::GetFileNameWithoutExtension($Dpr))
  $lines = @('@echo off', 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"',
    ('cd /d "{0}"' -f $Dir),
    ('dcc64 -B {0} -E"{1}" -NU"{2}" {3}' -f $Extra, $Out, $Dcu, $Dpr),
    'echo BUILD_EXITCODE=%ERRORLEVEL%')
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $Log -RedirectStandardError "$Log.err" -NoNewWindow -Wait | Out-Null
  $b = Get-Content $Log -Raw
  if ($b -notmatch 'BUILD_EXITCODE=0') { Write-Host $b; Write-Host "FATAL: $Dpr did not compile"; exit 2 }
}

$exePath = (Resolve-Path $Exe).Path
$fix     = Join-Path $repo 'tests\fixtures\v152-initapi'
$src     = Join-Path $WorkDir 'order'
$dcu     = Join-Path $WorkDir 'dcu'
$out     = Join-Path $WorkDir 'out'
foreach ($d in @($WorkDir, $dcu, $out)) { [void](New-Item -ItemType Directory -Force -Path $d) }
Copy-Item (Join-Path $fix 'order') $WorkDir -Recurse -Force
$db = Join-Path $WorkDir 'initapi.sqlite'
Push-Location $WorkDir
try {
  & { $ErrorActionPreference = 'Continue'; & $exePath index $src --db $db *> (Join-Path $WorkDir 'index.log') }

  . (Join-Path $repo 'tests\autotest\lib\CliBuildPaths.ps1')
  $cli = Get-CliDcc64Args
  Invoke-Dcc $fix 'InitApiHarness.dpr' $out $dcu $cli.Args (Join-Path $WorkDir 'harness.log')
  [void](Copy-TreeSitterDlls -Dest $out)
  $h = Join-Path $out 'InitApiHarness.exe'
  $pairs = @('P1:C:A', 'P1:A:C', 'P1:A:A', 'P2:W:Y', 'P2:Y:V', 'P1:NoSuch:A', 'P1:W:A', 'P9:C:A', ':C:A', ':W:Y')
  $raw = @(& { $ErrorActionPreference = 'Continue'; & $h $db @pairs 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" })
  $raw | ForEach-Object { Write-Host "  raw: $_" }
  function Order([string]$Prog) { return ,@($raw | Where-Object { $_ -like "ORDER|$Prog|*" }) }
  function Pair([string]$Key) {
    $p = $Key.Split(':')
    $row = @($raw | Where-Object { $_ -like ("PAIR|{0}|{1}|{2}|*" -f $p[0], $p[1], $p[2]) })
    if ($row.Count -ne 1) { return '<missing>' }
    return $row[0].Split('|')[4]
  }

  # c1
  $o1 = Order 'P1.dpr'
  $f1 = @(if ($o1.Count -eq 1) { $o1[0].Split('|') } else { @('', '', '', '', '', '') })
  Check (($o1.Count -eq 1) -and ($f1[5] -eq 'C,B,A,D') -and ($f1[2] -eq '0') -and ($f1[4] -eq 'yes')) "c1 P1 order C,B,A,D, reliable, program block (got '$($o1 -join ' / ')')"

  # c2: second engine call -- the order init-order-hazard walks
  $lj = (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --rule init-order-hazard --json 2>$null }) -join "`n"
  Write-Host "  lint raw: $($lj.Substring(0, [Math]::Min(400, $lj.Length)))"
  $lint = @(($lj | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ })
  $hz = @($lint | Where-Object { ([IO.Path]::GetFileName([string]$_.file_path) -eq 'C.pas') -and ($_.message -match 'A\.GVal') })
  $m = if ($hz.Count -ge 1) { [regex]::Match($hz[0].message, 'but (\w+) initializes after (\w+) in (\S+):') } else { $null }
  $lintSaysAAfterC = ($null -ne $m) -and $m.Success -and ($m.Groups[1].Value -eq 'A') -and ($m.Groups[2].Value -eq 'C') -and ($m.Groups[3].Value -eq 'P1.dpr')
  $apiUnits = $f1[5].Split(',')
  Check ($lintSaysAAfterC -and ([array]::IndexOf($apiUnits, 'C') -lt [array]::IndexOf($apiUnits, 'A')) -and ($apiUnits.Count -eq 4)) "c2 init-order-hazard's order (A after C in P1.dpr) equals the API's (hazard rows: $($hz.Count))"

  # c3: the compiler's order -- build and run the fixture program
  $pout = Join-Path $WorkDir 'p1out'; $pdcu = Join-Path $WorkDir 'p1dcu'
  foreach ($d in @($pout, $pdcu)) { [void](New-Item -ItemType Directory -Force -Path $d) }
  Invoke-Dcc $src 'P1.dpr' $pout $pdcu '-NSSystem' (Join-Path $WorkDir 'p1.log')
  $run = @(& (Join-Path $pout 'P1.exe') | ForEach-Object { "$_" })
  Write-Host "  P1.exe: $($run -join ' / ')"
  $ran = @($run | Where-Object { $_ -like 'INIT *' } | ForEach-Object { $_.Split(' ')[1] }) -join ','
  Check ($ran -eq $f1[5]) "c3 P1.exe initializes in the API's order (exe '$ran', api '$($f1[5])')"

  # c4
  $o2 = Order 'P2.dpr'
  $f2 = @(if ($o2.Count -eq 1) { $o2[0].Split('|') } else { @('', '', '', '', '', '') })
  Check (($o2.Count -eq 1) -and ($f2[5] -eq 'Y,V,W,X') -and ($f2[2] -eq '1') -and ($f2[3] -like 'X.pas:*')) "c4 P2 order Y,V,W,X, unreliable at X.pas (got '$($o2 -join ' / ')')"

  # c5..c9
  Check ((Pair 'P1:C:A') -eq 'before')            "c5 P1 C before A (got $(Pair 'P1:C:A'))"
  Check ((Pair 'P1:A:C') -eq 'not-before')        "c5 P1 A not before C (got $(Pair 'P1:A:C'))"
  Check ((Pair 'P1:A:A') -eq 'not-before')        "c5 P1 A not before itself (got $(Pair 'P1:A:A'))"
  Check ((Pair 'P2:W:Y') -eq 'config-dependent')  "c6 P2 W/Y config-dependent: X reaches W (got $(Pair 'P2:W:Y'))"
  Check ((Pair 'P2:Y:V') -eq 'before')            "c7 CONTROL P2 Y before V, X does not decide (got $(Pair 'P2:Y:V'))"
  Check ((Pair 'P1:NoSuch:A') -eq 'unplaced')     "c8 unknown unit unplaced (got $(Pair 'P1:NoSuch:A'))"
  Check ((Pair 'P1:W:A') -eq 'unplaced')          "c8 unit P1 does not reach unplaced (got $(Pair 'P1:W:A'))"
  Check ((Pair 'P9:C:A') -eq 'unplaced')          "c8 unknown program unplaced (got $(Pair 'P9:C:A'))"
  Check ((Pair ':C:A') -eq 'before')              "c9 every program: C before A (got $(Pair ':C:A'))"
  Check ((Pair ':W:Y') -eq 'config-dependent')    "c9 every program: W/Y config-dependent (got $(Pair ':W:Y'))"
}
finally {
  Pop-Location
}
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0
} finally { Remove-WorkDir $WorkDir -Keep:($env:DL_KEEP_WORKDIR -eq '1') }
