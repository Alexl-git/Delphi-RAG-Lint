<#
  run_cyclefix_f5_field_dcc.ps1 -- owner ruling D1 (a+), 2026-10-25: the F5 base-class plan for a
  container-shaped FIELD (`FOrders: TArray<TOrder>` -> `TArray<TOrderBase>`), followed, COMPILES
  and the program behaves exactly as before. Needs RAD Studio (msbuild via rsvars).

  Trees: docs\examples\circular-uses-demo as shipped ('demo'), and the same with
  `function FirstId: Integer` reading `FOrders[0].Id` ('memberread', the base class pulls Id).
  Each gets a console program F5Demo.dpr this runner writes (and a .dproj derived from
  tests\fixtures\cyclefix\r1extend\R1Extend.dproj). The runner builds the untouched copy (msbuild,
  Win64 Debug) and keeps its stdout, plans `cycles --plan` on a second copy, applies cycle 1 with
  tools\follow-cycle-plan.ps1, checks the cycle is GONE (`cycles` on a re-index), builds it
  (BUILD_EXITCODE=0, no `error E` / `fatal F` line), runs it and compares stdout BYTE-FOR-BYTE.

  POSITIVE CONTROL: the followed demo with its field line put back to `TArray<TOrder>` must NOT
  compile (Customers no longer uses Orders) -- so the build check can fail.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-f5field-dcc-$PID",
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo  = Join-Path $Repo 'docs\examples\circular-uses-demo'
$Ascii = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

$Dpr = @'
program F5Demo;

{$APPTYPE CONSOLE}

uses
  Customers in 'Customers.pas',
  Orders in 'Orders.pas';

var
  C: TCustomer;
  O: TOrder;
begin
  C := TCustomer.Create('Ada');
  O := TOrder.Create(7, C);
  C.AddOrder(O);
  C.AddOrder(TOrder.Create(8, C));
  Writeln(C.Name, ' has ', C.OrderCount, ' orders');
  Writeln(O.Describe);
end.
'@

function New-Tree([string]$Dir, [scriptblock]$Edit) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Get-ChildItem $Demo -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $Dir $_.Name) -Force }
  if ($Edit) { $cu = Join-Path $Dir 'Customers.pas'; Set-Text $cu (& $Edit ([IO.File]::ReadAllText($cu))) }
  Set-Text (Join-Path $Dir 'F5Demo.dpr') $Dpr
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'F5Demo').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{6B2D8FA5-3C7E-4014-9DAB-8F4C2E1A3B96}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        <DCCReference Include=`"Customers.pas`"/>`r`n        <DCCReference Include=`"Orders.pas`"/>")
  Set-Text (Join-Path $Dir 'F5Demo.dproj') $pj
}

function Invoke-Build([string]$Dproj) {
  $dir = Split-Path $Dproj
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $dir -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $dir),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}

function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\F5Demo.exe'
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

function Invoke-Cycles([string]$Dproj, [string]$Tag, [string[]]$Extra) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $db + '"'), '--library-db', 'none') + $Extra) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o; Text = [IO.File]::ReadAllText($o) }
}

function Test-Tree([string]$Tag, [scriptblock]$Edit) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $base = Join-Path $WorkDir "$Tag-base"; $work = Join-Path $WorkDir "$Tag-edit"
  New-Tree $base $Edit; New-Tree $work $Edit
  $b0 = Invoke-Build (Join-Path $base 'F5Demo.dproj')
  Check "$Tag 0 the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'F5Demo.dproj')
  $plan = Invoke-Cycles (Join-Path $work 'F5Demo.dproj') "$Tag-plan" @('--plan')
  Check "$Tag 1 planned (exit 0), no base-class refusal" (($plan.Exit -eq 0) -and ($plan.Text -notmatch 'refused: base-class')) "exit=$($plan.Exit)"
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle 1 -Root $work 2>&1 | Out-String
  Check "$Tag 2 the follower applies cycle 1 (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $cu = [IO.File]::ReadAllText((Join-Path $work 'Customers.pas'))
  Check "$Tag 3 Customers.pas now holds TArray<TOrderBase>" ($cu -match 'FOrders\s*:\s*TArray<TOrderBase>;') ''
  $after = Invoke-Cycles (Join-Path $work 'F5Demo.dproj') "$Tag-after" @()
  Check "$Tag 4 the cycle is gone after a re-index" ($after.Text -notmatch 'customers <-> orders|orders <-> customers') ($after.Text.Trim() -replace "`r?`n", ' | ')
  $b1 = Invoke-Build (Join-Path $work 'F5Demo.dproj')
  Check "$Tag 5 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $work 'F5Demo.dproj')
  Check "$Tag 6 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return $work
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $demoTree = Test-Tree 'demo' $null
  $null = Test-Tree 'memberread' {
    param($t)
    $t = $t.Replace("    function OrderCount: Integer;`r`n", "    function OrderCount: Integer;`r`n    function FirstId: Integer;`r`n")
    return $t -replace 'end\.\s*$', "function TCustomer.FirstId: Integer;`r`nbegin`r`n  Result := FOrders[0].Id;`r`nend;`r`n`r`nend.`r`n"
  }

  Write-Host '== positive control: the followed demo with the field line put back' -ForegroundColor Cyan
  $cuP = Join-Path $demoTree 'Customers.pas'
  $t = [IO.File]::ReadAllText($cuP)
  $t2 = $t -replace 'TArray<TOrderBase>', 'TArray<TOrder>'
  Set-Text $cuP $t2
  Check 'pc0 the field line was changed back' ($t2 -ne $t) ''
  $bc = Invoke-Build (Join-Path $demoTree 'F5Demo.dproj')
  Check 'pc1 it does NOT compile (the build check has teeth)' (-not $bc.Ok) $bc.Errors
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
