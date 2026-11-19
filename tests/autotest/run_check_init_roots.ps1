<#
  run_check_init_roots.ps1 -- 1.52 lane HBROOTS: the happens-before roots
  (DRagLint.Query.HappensBefore.Roots, spec 2026-11-17-happens-before-design.md 5.2).

  Fixtures tests\fixtures\happens-before\roots-* (indexed together into one --db in the work folder):
    roots-order        RootsOrder.dpr uses OrdA, OrdD; OrdA -> OrdB -> OrdC, OrdC impl-uses OrdB, OrdB impl-uses
                       OrdA. Computed order OrdC, OrdB, OrdA, OrdD, then the program block.
    roots-conditional  RootsCond.dpr; CndX has an {$IFDEF} uses entry -> the chain is unreliable-order.
    roots-escaped      RootsEsc.dpr + EscUnit + EscForm(.dfm): one routine per escape class, plus controls.
  Harness tests\fixtures\happens-before\roots-harness\RootsHarness.dpr is compiled with dcc64 against the source.

    c1  roots-order chain = initialization of OrdC, OrdB, OrdA, OrdD, then program block; reliable
    c2  the SAME order as a second engine call: init-order-hazard (lint-all) says OrdB initializes after OrdC
        and OrdA after OrdB in RootsOrder.dpr; CONTROL: no hazard row for OrdD
    c3  roots-conditional chain is unreliable, naming CndX.pas
    c4  CONTROL: no ordered root (initialization, program block) is itself escaped
    c5  each escape class of spec 5.2 reported with its class name
    c6  CONTROL: a plain called routine, a called virtual, an override reached through its base and two functions
        called on the right of := (bare and qualified, no parentheses) are NOT escaped
    c7  unknown QName answers <missing> (the harness does not invent a class)

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_v152_hbroots_$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
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
  if ($b -notmatch 'BUILD_EXITCODE=0') {
    $b -split "`r?`n" | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 15 | ForEach-Object { Write-Host "  dcc: $_" }
    Write-Host "FATAL: $Dpr did not compile"; Write-Host 'RESULT: FAIL'; exit 2
  }
}

$exePath = (Resolve-Path $Exe).Path
$fix     = Join-Path $repo 'tests\fixtures\happens-before'
$src     = Join-Path $WorkDir 'src'
$dcu     = Join-Path $WorkDir 'dcu'
$out     = Join-Path $WorkDir 'out'
foreach ($d in @($WorkDir, $src, $dcu, $out)) { [void](New-Item -ItemType Directory -Force -Path $d) }
foreach ($case in @('roots-order', 'roots-conditional', 'roots-escaped')) { Copy-Item (Join-Path $fix $case) $src -Recurse -Force }
$db = Join-Path $WorkDir 'roots.sqlite'
Push-Location $WorkDir
try {
  & { $ErrorActionPreference = 'Continue'; & $exePath index $src --db $db *> (Join-Path $WorkDir 'index.log') }
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE (see $WorkDir\index.log)"; Write-Host 'RESULT: FAIL'; exit 2 }

  . (Join-Path $repo 'tests\autotest\lib\CliBuildPaths.ps1')
  $cli = Get-CliDcc64Args
  Invoke-Dcc (Join-Path $fix 'roots-harness') 'RootsHarness.dpr' $out $dcu $cli.Args (Join-Path $WorkDir 'harness.log')
  [void](Copy-TreeSitterDlls -Dest $out)
  $h = Join-Path $out 'RootsHarness.exe'

  $esc = [ordered]@{
    'EscForm.TEscMainForm.BtnGoClick' = 'dfm-event'
    'EscUnit.TEscPub.PubMethod'       = 'published'
    'EscUnit.TEscMsg.WMNull'          = 'message-handler'
    'EscUnit.TEscJob.Run'             = 'interface-method'
    'EscUnit.EscAddrProc'             = 'address-taken'
    'EscUnit.TEscHolder.HandlerEvt'   = 'address-taken'
    'EscUnit.EscExported'             = 'exported'
    'EscUnit.TEscThread.Execute'      = 'thread-execute'
    'EscUnit.TEscCls.CreateCls'       = 'class-ctor-dtor'
    'EscUnit.EscOrphan'               = 'zero-callers'
    'EscUnit.finalization'            = 'finalization'
    'EscUnit.EscPlain'                = 'none'
    'EscUnit.EscDriver'               = 'none'
    'EscUnit.TEscChild.DoIt'          = 'none'
    'EscUnit.TEscBase.DoIt'           = 'none'
    'EscUnit.EscValue'                = 'none'
    'EscUnit.TEscHolder.GetCount'     = 'none'
    'EscUnit.NoSuchRoutine'           = '<missing>'
  }
  $raw = @(& { $ErrorActionPreference = 'Continue'; & $h $db @($esc.Keys) 2>&1 | ForEach-Object { "$_" } } | ForEach-Object { "$_" })
  $raw | ForEach-Object { Write-Host "  raw: $_" }
  function Chain([string]$Prog) {
    $r = @($raw | Where-Object { $_ -like "CHAIN|$Prog|*" })
    if ($r.Count -ne 1) { return @('', '', '', '', '') }
    return $r[0].Split('|')
  }
  function EscOf([string]$Q) {
    $r = @($raw | Where-Object { $_ -like "ESC|$Q|*" })
    if ($r.Count -ne 1) { return '<no row>' }
    return $r[0].Split('|')[2]
  }

  # c1
  $o = @(Chain 'RootsOrder.dpr')
  $want = 'initialization of OrdC;initialization of OrdB;initialization of OrdA;initialization of OrdD;program block of RootsOrder.dpr'
  Check (($o[4] -eq $want) -and ($o[2] -eq '0')) "c1 roots-order chain C,B,A,D + program block, reliable (got '$($o -join '|')')"

  # c2: second engine call -- the order init-order-hazard walks
  $lj = (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --rule init-order-hazard --json 2>$null }) -join "`n"
  Write-Host "  lint raw: $($lj.Substring(0, [Math]::Min(600, $lj.Length)))"
  $lint = @(($lj | ConvertFrom-Json) | ForEach-Object { $_ })
  function Hazard([string]$File, [string]$Later, [string]$Earlier) {
    foreach ($f in @($lint | Where-Object { [IO.Path]::GetFileName([string]$_.file_path) -eq $File })) {
      $m = [regex]::Match([string]$f.message, 'but (\w+) initializes after (\w+) in (\S+):')
      if ($m.Success -and ($m.Groups[1].Value -eq $Later) -and ($m.Groups[2].Value -eq $Earlier) -and ($m.Groups[3].Value -eq 'RootsOrder.dpr')) { return $true }
    }
    return $false
  }
  $units = @($o[4].Split(';') | ForEach-Object { ($_ -replace '^initialization of ', '') })
  $bAfterC = Hazard 'OrdC.pas' 'OrdB' 'OrdC'
  $aAfterB = Hazard 'OrdB.pas' 'OrdA' 'OrdB'
  Check ($bAfterC -and ([array]::IndexOf($units, 'OrdC') -lt [array]::IndexOf($units, 'OrdB')) -and ([array]::IndexOf($units, 'OrdC') -ge 0)) "c2 init-order-hazard: OrdB initializes after OrdC, as the chain says"
  Check ($aAfterB -and ([array]::IndexOf($units, 'OrdB') -lt [array]::IndexOf($units, 'OrdA')) -and ([array]::IndexOf($units, 'OrdB') -ge 0)) "c2 init-order-hazard: OrdA initializes after OrdB, as the chain says"
  $dRows = @($lint | Where-Object { [IO.Path]::GetFileName([string]$_.file_path) -eq 'OrdD.pas' })
  Check (($lint.Count -ge 2) -and ($dRows.Count -eq 0)) "c2 CONTROL: no hazard row for OrdD (rows: $($lint.Count), OrdD: $($dRows.Count))"

  # c3
  $c = @(Chain 'RootsCond.dpr')
  Check (($c[2] -eq '1') -and ($c[3] -like 'CndX.pas:*')) "c3 roots-conditional chain is unreliable at CndX.pas (got '$($c -join '|')')"

  # c4
  $rootRows = @($raw | Where-Object { $_ -like 'ROOT|*' })
  $escapedRoots = @($rootRows | Where-Object { $_.Split('|')[3] -ne 'none' })
  Check (($rootRows.Count -ge 5) -and ($escapedRoots.Count -eq 0)) "c4 CONTROL: no ordered root is escaped (roots: $($rootRows.Count), escaped: $($escapedRoots -join ' / '))"

  # c5 .. c7
  foreach ($q in $esc.Keys) {
    $got = EscOf $q
    $tag = if ($esc[$q] -eq '<missing>') { 'c7' } elseif ($esc[$q] -eq 'none') { 'c6 CONTROL' } else { 'c5' }
    Check ($got -eq $esc[$q]) ("{0} {1} -> {2} (got {3})" -f $tag, $q, $esc[$q], $got)
  }
}
finally {
  Pop-Location
}
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'
exit 0