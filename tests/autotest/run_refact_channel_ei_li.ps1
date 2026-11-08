<#
  run_refact_channel_ei_li.ps1 -- wave 148 RN item 9a (146 g3 owed row): `extract-interface --apply` and
  `lazy-init --apply` open the control channel, like narrow-param / redundant-cast / create-enum-helper (E-NARROW-CHANNEL),
  so `drag-lint shutdown --db <db>` kills the build they wait on, rolls the written files back and ends the run exit 1.
  Before: no channel, shutdown found no listener, the run went on and wrote.

  Same harness as run_gate_adoption.ps1: a FAKE rsvars.bat (--rsvars) calls the real one and, once a .BCK backup exists
  in the project folder (the compile gate's after-build; the scratch build runs in a copy, so it never parks), parks
  in a ping on a loopback address nobody else pings, so the cancel lands in the after-build by construction.
    EI1 / LI1  shutdown stops the run: exit 1, not killed.
    EI2 / LI2  the tree is byte-identical to before.
    EI3 / LI3  the parked build is gone.
    C1 / C2    POSITIVE CONTROL: the same --apply run with the real rsvars and no shutdown writes (exit 0, tree
               changed): the guard fails if the verbs stop writing, so EI2/LI2 cannot pass vacuously.
  RED on lane/147-int 6fac0082 (1.46.0-alpha + 147): EI1/LI1 fail (no listener; the run is killed or writes).
  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing.
#>
param(
  [string]$Exe    = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor").Path
$Tmp = Join-Path $env:TEMP ('chan_eili_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
function Wait-For([scriptblock]$Cond, [int]$Seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Seconds) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 250 }
  return (& $Cond)
}
function Cancel-Run([string]$Tag, $P, [string[]]$Args_) {
  $flag = Join-Path $Tmp "$Tag-parked.flag"
  $bat  = Join-Path $Tmp "$Tag-rsvars.bat"
  $lines = @('@echo off', "call `"$Rsvars`"", "if not exist `"$($P.Dir)\*.BCK*`" goto :eof", "echo.> `"$flag`"", "ping -n 300 $PingHost > nul")
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
  $q = ($Args_ + @('--rsvars', $bat, '--build-timeout', '600') | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
  $run = Start-Process -FilePath $Exe -ArgumentList $q -RedirectStandardOutput (Join-Path $Tmp "$Tag.out") -RedirectStandardError (Join-Path $Tmp "$Tag.err") -NoNewWindow -PassThru
  $parked = Wait-For { (Test-Path $flag) -or $run.HasExited } 400
  if (-not ($parked -and (Test-Path $flag) -and -not $run.HasExited)) { try { $run.Kill() } catch { }; Stop-Parked; return @{ Parked = $false; Exit = $null; Left = 0 } }
  $null = & $Exe shutdown --db $P.Db --wait 60 2>&1
  $ended = Wait-For { $run.HasExited } 60
  $code = if ($ended) { $run.ExitCode } else { try { $run.Kill() } catch { }; $null }
  Start-Sleep -Milliseconds 500
  $left = (Parked).Count
  Stop-Parked
  return @{ Parked = $true; Exit = $code; Left = $left }
}
$Cases = @(
  @{ Tag = 'EI'; Fixture = 'extractiface'; Dproj = 'EiProj.dproj'; Verb = @('extract-interface', '--class', 'TEiWidget') },
  @{ Tag = 'LI'; Fixture = 'lazyinit'; Dproj = 'LiProj.dproj'; Verb = @('lazy-init', '--unit', 'LiHeavy') }
)
try {
  foreach ($c in $Cases) {
    $t = $c.Tag
    Write-Host "$($c.Verb[0]) --apply: shutdown reaches it"
    $P = New-Project $c.Fixture $c.Dproj ($t.ToLower() + 'x')
    $before = Tree-Hash $P.Dir
    $cr = Cancel-Run $t $P ($c.Verb + @('--apply', '--project', $P.Proj, '--db', $P.Db, '--library-db', 'none'))
    Check "${t}0 setup: the after-build parked" $cr.Parked
    Check "${t}1 shutdown stops it: exit 1 (rolled back), not killed" ($cr.Exit -eq 1) "exit $($cr.Exit); $(Get-Content (Join-Path $Tmp "$t.err") -Raw -ErrorAction SilentlyContinue)"
    Check "${t}2 the tree is byte-identical to before" ((Tree-Hash $P.Dir) -ceq $before)
    Check "${t}3 the parked build is gone" ($cr.Left -eq 0) "$($cr.Left) left"
    $Q = New-Project $c.Fixture $c.Dproj ($t.ToLower() + 'c')
    $qBefore = Tree-Hash $Q.Dir
    $a = $c.Verb + @('--apply', '--project', $Q.Proj, '--db', $Q.Db, '--library-db', 'none', '--rsvars', $Rsvars)
    $null = & $Exe @a *> (Join-Path $Tmp "$t-control.log")
    Check "${t}-C POSITIVE CONTROL: the same --apply without shutdown writes (exit 0, tree changed)" (($LASTEXITCODE -eq 0) -and ((Tree-Hash $Q.Dir) -cne $qBefore)) "exit $LASTEXITCODE"
  }
}
finally {
  Stop-Parked
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'run_refact_channel_ei_li: PASS' -ForegroundColor Green; exit 0 }
