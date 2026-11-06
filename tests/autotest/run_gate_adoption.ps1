<#
  run_gate_adoption.ps1 -- wave 146 lane r3: the compile gate reaches every rewriting verb that can use it, and
  a stand-down request reaches the gated verbs that run long.

  E-NARROW-CHANNEL: `narrow-param --apply` and `lint --fix --fix-rule redundant-cast --apply` open the control
  channel, so `drag-lint shutdown --db <db>` kills the build they wait on, rolls the written files back and ends
  the run with exit 1 (before this lane: no channel, shutdown found nothing, the run went on).
  E-UNWITH-LINTFIX: `lint --fix --fix-rule with-statement` is `unwith` (no --apply = --plan; --apply needs --project).
  E-COMPILEGATE-ADOPT: `extract-method` and `create-enum-helper` write through the gate when --project is given
  (a project that does not build is refused with nothing written); without --project they write as they always did.

  The stand-down halves use a FAKE rsvars.bat (--rsvars): it calls the real one and, only once a .BCK backup
  exists in the project folder (the after-build), parks in a ping on a loopback address nobody else pings, so the
  cancel lands in the after-build by construction. Needs dcc: SKIPs (exit 0) when rsvars.bat is missing.
  Positive controls: Run it against the 1.44.1 engine and N1/N2/R1/R2/X1/X2/G2/G3/E2 fail (that is the RED).
#>
param(
  [string]$Exe    = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor").Path
$Tmp = Join-Path $env:TEMP ('gate_adopt_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
$PingHost = '127.{0}.{1}.{2}' -f (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250)
function Parked { return @(Get-CimInstance Win32_Process -Filter "Name = 'PING.EXE' OR Name = 'ping.exe'" | Where-Object { "$($_.CommandLine)" -match [regex]::Escape($PingHost) }) }
function Stop-Parked { foreach ($p in (Parked)) { try { [Diagnostics.Process]::GetProcessById([int]$p.ProcessId).Kill() } catch { } } }

function Tree-Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Name -ne 'nul' -and $_.Extension -notin '.sqlite', '.dcu', '.exe', '.rsm', '.map', '.drc', '.sqlite-wal', '.sqlite-shm', '.res', '.identcache', '.local', '.flag', '.log', '.err', '.out' -and $_.FullName -notmatch '\\Win64\\|\\Win32\\|\\__history\\|\\__recovery\\' } |
      Sort-Object FullName | ForEach-Object { "$($_.Name)|$((Get-FileHash $_.FullName -Algorithm SHA1).Hash)" }) -join "`n"
}
function New-Project([string]$Fixture, [string]$Dproj, [string]$Tag) {
  $d = Join-Path $Tmp $Tag
  Copy-Item (Join-Path $Fx $Fixture) $d -Recurse
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d $Dproj) --db $db --library-db none *> (Join-Path $Tmp "$Tag.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Tag exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d $Dproj) }
}
function New-FakeRsvars([string]$Tag, [string]$ProjDir) {
  $flag = Join-Path $Tmp "$Tag-parked.flag"
  $bat  = Join-Path $Tmp "$Tag-rsvars.bat"
  $lines = @('@echo off', "call `"$Rsvars`"", "if not exist `"$ProjDir\*.BCK*`" goto :eof", "echo.> `"$flag`"", "ping -n 300 $PingHost > nul")
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  return @{ Bat = $bat; Flag = $flag }
}
function Wait-For([scriptblock]$Cond, [int]$Seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Seconds) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 250 }
  return (& $Cond)
}
# Start the verb, wait until its after-build parks, send shutdown --db, return the run's exit code (or $null: never parked / never exited).
function Cancel-Run([string]$Tag, $P, [string[]]$Args_) {
  $fake = New-FakeRsvars $Tag $P.Dir
  $q = ($Args_ + @('--rsvars', $fake.Bat, '--build-timeout', '600') | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $run = Start-Process -FilePath $Exe -ArgumentList $q -RedirectStandardOutput (Join-Path $Tmp "$Tag.out") -RedirectStandardError (Join-Path $Tmp "$Tag.err") -NoNewWindow -PassThru
  $parked = Wait-For { (Test-Path $fake.Flag) -or $run.HasExited } 300
  if (-not ($parked -and (Test-Path $fake.Flag) -and -not $run.HasExited)) { try { $run.Kill() } catch { }; Stop-Parked; return @{ Parked = $false; Exit = $null } }
  $null = & $Exe shutdown --db $P.Db --wait 60 2>&1
  $ended = Wait-For { $run.HasExited } 60
  $code = if ($ended) { $run.ExitCode } else { try { $run.Kill() } catch { }; $null }
  $left = (Parked).Count
  Stop-Parked
  return @{ Parked = $true; Exit = $code; Left = $left }
}

try {
  Write-Host 'E-NARROW-CHANNEL: narrow-param'
  $N = New-Project 'narrowparam' 'NarrowParam.dproj' 'np'
  $nBefore = Tree-Hash $N.Dir
  $cr = Cancel-Run 'np' $N @('narrow-param', '--all', '--apply', '--project', $N.Proj, '--db', $N.Db, '--library-db', 'none')
  Check 'N0 setup: the after-build parked' $cr.Parked
  Check 'N1 shutdown stops it: exit 1 (rolled back), not killed' ($cr.Exit -eq 1) "exit $($cr.Exit)"
  Check 'N2 the tree is byte-identical to before' ((Tree-Hash $N.Dir) -ceq $nBefore)
  Check 'N3 the parked build is gone' ($cr.Left -eq 0) "$($cr.Left) left"

  Write-Host 'E-NARROW-CHANNEL: lint --fix --fix-rule redundant-cast'
  $RC = New-Project 'redcast' 'RedCast.dproj' 'rc'
  $rBefore = Tree-Hash $RC.Dir
  $cr = Cancel-Run 'rc' $RC @('lint', '--fix', '--fix-rule', 'redundant-cast', '--apply', '--project', $RC.Proj, '--db', $RC.Db, '--library-db', 'none')
  Check 'R0 setup: the after-build parked' $cr.Parked
  Check 'R1 shutdown stops it: exit 1 (rolled back)' ($cr.Exit -eq 1) "exit $($cr.Exit)"
  $rAfter = Tree-Hash $RC.Dir
  Check 'R2 the tree is byte-identical to before' ($rAfter -ceq $rBefore) ((Compare-Object ($rBefore -split "`n") ($rAfter -split "`n") | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join '; ')

  Write-Host 'E-UNWITH-LINTFIX: lint --fix --fix-rule with-statement'
  $U = New-Project 'unwith' 'UwDemo.dproj' 'uw'
  $uBefore = Tree-Hash $U.Dir
  $uFile = Join-Path $U.Dir 'UwCases.pas'
  $viaUnwith = (& $Exe unwith --db $U.Db --library-db none --in $uFile --plan 2>&1) -join "`n"
  $uCode = $LASTEXITCODE
  $viaLint = (& $Exe lint --fix --fix-rule with-statement --db $U.Db --library-db none --in $uFile 2>&1) -join "`n"
  $lCode = $LASTEXITCODE
  Check 'U0 control: the unwith plan is a real plan (not an error)' (($uCode -eq 0) -and ($viaUnwith.Length -gt 40)) "exit $uCode; $viaUnwith"
  Check 'U1 lint --fix --fix-rule with-statement prints the same plan, same exit' (($lCode -eq $uCode) -and ($viaLint -ceq $viaUnwith)) "exit $lCode; $viaLint"
  & $Exe lint --fix --fix-rule with-statement --apply --db $U.Db --library-db none --in $uFile *> $null
  Check 'U2 --apply without --project exits 2 (the gate needs a project), like unwith' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  Check 'U3 nothing was written' ((Tree-Hash $U.Dir) -ceq $uBefore)

  Write-Host 'E-COMPILEGATE-ADOPT: extract-method, create-enum-helper'
  function New-Gated([string]$Tag, [bool]$Dirty) {
    $P = New-Project 'narrowparam' 'NarrowParam.dproj' $Tag
    Copy-Item "$PSScriptRoot\..\refactor\extractmethod\Basic.pas" (Join-Path $P.Dir 'Basic.pas')
    $b = Join-Path $P.Dir 'Basic.pas'
    $t = [IO.File]::ReadAllText($b).Replace("procedure P(a: Integer);`r`nimplementation", "type`r`n  TColor = (cRed, cGreen, cBlue);`r`nprocedure P(a: Integer);`r`nimplementation")
    $t = $t.Replace("procedure P(a: Integer);`nimplementation", "type`n  TColor = (cRed, cGreen, cBlue);`nprocedure P(a: Integer);`nimplementation")
    [IO.File]::WriteAllText($b, $t, [Text.Encoding]::ASCII)
    $dpr = Join-Path $P.Dir 'NarrowParam.dpr'
    [IO.File]::WriteAllText($dpr, [IO.File]::ReadAllText($dpr).Replace("NpUse in 'NpUse.pas';", "NpUse in 'NpUse.pas',`r`n  Basic in 'Basic.pas';"), [Text.Encoding]::ASCII)
    if ($Dirty) { $np = Join-Path $P.Dir 'NpRoot.pas'; [IO.File]::WriteAllText($np, "this is not pascal`r`n" + [IO.File]::ReadAllText($np), [Text.Encoding]::ASCII) }
    & $Exe index --project $P.Proj --db $P.Db --library-db none *> (Join-Path $Tmp "$Tag.reindex.log")
    $P.Basic = $b
    return $P
  }
  $em = @('extract-method', '--from-line', '8', '--to-line', '9', '--name', 'Extracted', '--apply')
  # clean project, gated: the gate builds twice and the file is written
  $G = New-Gated 'g1' $false
  $g0 = [IO.File]::ReadAllText($G.Basic)
  $emLines = $g0 -split "`r?`n"
  $from = ([Array]::FindIndex($emLines, [Predicate[string]] { param($l) $l -match 't := a \+ 1' })) + 1
  $em = @('extract-method', '--from-line', "$from", '--to-line', "$($from + 1)", '--name', 'Extracted', '--apply')
  $null = & $Exe @em --file $G.Basic --project $G.Proj --rsvars $Rsvars 2>$null
  $g1 = [IO.File]::ReadAllText($G.Basic)
  Check 'G1 gated, clean project: exit 0, the method was extracted, a .BCK backup was made' (($LASTEXITCODE -eq 0) -and ($g1 -match 'procedure Extracted') -and (@(Get-ChildItem $G.Dir -Filter 'Basic.pas.BCK*').Count -ge 1)) "exit $LASTEXITCODE"
  # dirty baseline, gated: refused, nothing written
  $D = New-Gated 'g2' $true
  $dBefore = Tree-Hash $D.Dir
  $dErr = (& $Exe @em --file $D.Basic --project $D.Proj --rsvars $Rsvars 2>&1 | Out-String)
  Check 'G2 gated, project does not build: exit 1, REFUSED (dirty-baseline)' (($LASTEXITCODE -eq 1) -and ($dErr -match 'REFUSED \(dirty-baseline\)')) "exit $LASTEXITCODE; $dErr"
  Check 'G3 nothing was written' ((Tree-Hash $D.Dir) -ceq $dBefore)
  # control: no --project on the same project = the old, ungated write
  $null = & $Exe @em --file $D.Basic 2>$null
  Check 'G4 control: without --project the same run writes (opt-in gate)' (($LASTEXITCODE -eq 0) -and ([IO.File]::ReadAllText($D.Basic) -match 'procedure Extracted'))

  $E = New-Gated 'e1' $true
  $eBefore = Tree-Hash $E.Dir
  $eErr = (& $Exe create-enum-helper --qname Basic.TColor --db $E.Db --library-db none --project $E.Proj --rsvars $Rsvars --apply 2>&1 | Out-String)
  Check 'E1 control: the enum is found and a helper is planned' ($eErr -notmatch 'not_found|REFUSED: .*not found') $eErr
  Check 'E2 gated, project does not build: exit 1, REFUSED (dirty-baseline), nothing written' (($LASTEXITCODE -eq 1) -and ($eErr -match 'REFUSED \(dirty-baseline\)') -and ((Tree-Hash $E.Dir) -ceq $eBefore)) "exit $LASTEXITCODE; $eErr"
  $null = & $Exe create-enum-helper --qname Basic.TColor --db $E.Db --library-db none --apply 2>$null
  Check 'E3 control: without --project the helper is written' (($LASTEXITCODE -eq 0) -and ((Tree-Hash $E.Dir) -cne $eBefore))
}
finally {
  Stop-Parked
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
