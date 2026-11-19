<#
  run_v152_BK-GATE.ps1 -- lane BK-GATE (1.52) follow-ups of GATE2 (B20-B24).

  B20 IDE Rename / Extract Method apply gets a longer stall budget than a preview (the gate builds the project twice
      -- baseline and after -- by design; source check on the plugin).
  B21 extract-method opens the stand-down channel: `drag-lint shutdown --db` stops its after-build, rolled back, exit 1.
  B22 a gated create-enum-helper / lint --fix says ".BCK backup written", not ".bak".
  B23 lint --fix --apply with --db on a unit that NO project builds: REFUSED (no-project), exit 2, nothing written
      (owner ruling 2026-11-18); --no-compile-gate writes unbuilt; a loose file with no index is unchanged.
  B24 NOT changed: rename already widens the gate to every manifest-known project that compiles the unit
      (RenameAcrossOwners, run_rename_multiproject_gate.ps1); only projects no manifest/DB knows are left (design).

  Needs dcc for B21/B22: those are skipped when rsvars.bat is missing.
#>
param(
  [string]$Exe    = '',
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor").Path
$Tmp = Join-Path $env:TEMP ('bkgate_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
# the engine walks UP from the CWD for .drag-lint.json: run from the scratch dir so no shared config leaks in
Push-Location $Tmp
$PingHost = '127.{0}.{1}.{2}' -f (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250), (Get-Random -Min 2 -Max 250)
function Parked { return @(Get-CimInstance Win32_Process -Filter "Name = 'PING.EXE' OR Name = 'ping.exe'" | Where-Object { "$($_.CommandLine)" -match [regex]::Escape($PingHost) }) }
function Stop-Parked { foreach ($p in (Parked)) { try { [Diagnostics.Process]::GetProcessById([int]$p.ProcessId).Kill() } catch { } } }
function Tree-Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Name -ne 'nul' -and $_.Extension -notin '.sqlite', '.dcu', '.exe', '.rsm', '.map', '.drc', '.sqlite-wal', '.sqlite-shm', '.res', '.identcache', '.local', '.flag', '.log', '.err', '.out' -and $_.FullName -notmatch '\\Win64\\|\\Win32\\|\\__history\\|\\__recovery\\' } |
      Sort-Object FullName | ForEach-Object { "$($_.Name)|$((Get-FileHash $_.FullName -Algorithm SHA1).Hash)" }) -join "`n"
}
function Wait-For([scriptblock]$Cond, [int]$Seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Seconds) { if (& $Cond) { return $true }; Start-Sleep -Milliseconds 250 }
  return (& $Cond)
}
function New-Fx([string]$Tag) {
  $d = Join-Path $Tmp $Tag
  Copy-Item (Join-Path $Fx 'narrowparam') $d -Recurse
  $b = Join-Path $d 'Basic.pas'
  $t = [IO.File]::ReadAllText("$PSScriptRoot\..\refactor\extractmethod\Basic.pas") -replace "`r?`n", "`r`n"
  $t = $t.Replace("procedure P(a: Integer);`r`nimplementation", "type`r`n  TColor = (cRed, cGreen, cBlue);`r`nprocedure P(a: Integer);`r`nimplementation")
  [IO.File]::WriteAllText($b, $t, [Text.Encoding]::ASCII)
  $dpr = Join-Path $d 'NarrowParam.dpr'
  [IO.File]::WriteAllText($dpr, [IO.File]::ReadAllText($dpr).Replace("NpUse in 'NpUse.pas';", "NpUse in 'NpUse.pas',`r`n  Basic in 'Basic.pas';"), [Text.Encoding]::ASCII)
  $db = Join-Path $d 'p.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $d 'NarrowParam.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Tag.index.log") }
  if ($LASTEXITCODE -ne 0) { throw "index $Tag exit $LASTEXITCODE" }
  $lines = $t -split "`r`n"
  $from = ([Array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match 't := a \+ 1' })) + 1
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'NarrowParam.dproj'); Basic = $b; From = $from }
}
function Run([string[]]$CliArgs) {
  $out = (& { $ErrorActionPreference = 'Continue'; & $Exe @CliArgs 2>&1 | ForEach-Object { "$_" } } | Out-String)
  return @{ Code = $LASTEXITCODE; Out = $out }
}

try {
  Write-Host 'B20: plugin apply stall budget (source check)'
  $rf = [IO.File]::ReadAllText("$PSScriptRoot\..\..\src\delphi-plugin\DragLint.Plugin.RefactorForm.pas")
  Check 'B20a REFACTOR_APPLY_STALL_MS is declared and larger than REFACTOR_STALL_MS' (($rf -match 'REFACTOR_APPLY_STALL_MS\s*=\s*(\d+)') -and ([int]$Matches[1] -gt 60000))
  Check 'B20b Rename apply and Extract Method apply pass it' (([regex]::Matches($rf, 'end, REFACTOR_APPLY_STALL_MS\)')).Count -eq 2)

  if (Test-Path $Rsvars) {
    Write-Host 'B21: extract-method stand-down channel'
    $P = New-Fx 'b21'
    $before = Tree-Hash $P.Dir
    $flag = Join-Path $Tmp 'b21-parked.flag'
    $bat  = Join-Path $Tmp 'b21-rsvars.bat'
    $lines = @('@echo off', "call `"$Rsvars`"", "if not exist `"$($P.Dir)\*.BCK*`" goto :eof", "echo.> `"$flag`"", "ping -n 300 $PingHost > nul")
    [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    $a = @('extract-method', '--file', $P.Basic, '--from-line', "$($P.From)", '--to-line', "$($P.From + 1)", '--name', 'Extracted', '--apply', '--db', $P.Db, '--rsvars', $bat, '--build-timeout', '600')
    $q = ($a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $run = Start-Process -FilePath $Exe -ArgumentList $q -RedirectStandardOutput (Join-Path $Tmp 'b21.out') -RedirectStandardError (Join-Path $Tmp 'b21.err') -WorkingDirectory $Tmp -NoNewWindow -PassThru
    $parked = Wait-For { (Test-Path $flag) -or $run.HasExited } 300
    $isParked = $parked -and (Test-Path $flag) -and -not $run.HasExited
    Check 'S0 setup: the after-build parked' $isParked
    if ($isParked) {
      $null = & { $ErrorActionPreference = 'Continue'; & $Exe shutdown --db $P.Db --wait 60 2>&1 | ForEach-Object { "$_" } }
      $ended = Wait-For { $run.HasExited } 60
      $code = if ($ended) { $run.ExitCode } else { try { $run.Kill() } catch { }; $null }
      Check 'S1 shutdown stops it: exit 1 (rolled back), not killed' ($code -eq 1) "exit $code"
      Check 'S2 the tree is byte-identical to before' ((Tree-Hash $P.Dir) -ceq $before)
    } else { try { $run.Kill() } catch { } }
    Stop-Parked

    Write-Host 'B22: gated create-enum-helper says .BCK'
    $P = New-Fx 'b22'
    $r = Run @('create-enum-helper', '--qname', 'Basic.TColor', '--db', $P.Db, '--library-db', 'none', '--apply', '--rsvars', $Rsvars)
    Check 'M1 gated write: exit 0, the message says ".BCK backup written" and not ".bak"' (($r.Code -eq 0) -and ($r.Out -match '\.BCK backup written') -and ($r.Out -notmatch '\.bak written')) "exit $($r.Code); $($r.Out)"
  } else { Write-Host 'SKIP B21/B22: no rsvars.bat' -ForegroundColor Yellow }

  Write-Host 'B23: lint --fix --apply on a unit no project builds'
  $d = Join-Path $Tmp 'b23'; [IO.Directory]::CreateDirectory($d) | Out-Null
  $src = "unit redundant_parens;`r`ninterface`r`nimplementation`r`n`r`nprocedure P(var X: Integer; const A, B: Integer);`r`nbegin`r`n  X := ((A + B));`r`nend;`r`n`r`nend.`r`n"
  $u = Join-Path $d 'redundant_parens.pas'
  [IO.File]::WriteAllText($u, $src, [Text.Encoding]::ASCII)
  $db = Join-Path $d 'loose.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $d --db $db --library-db none *> (Join-Path $Tmp 'b23.index.log') }
  $fixArgs = @('lint', '--file', $u, '--db', $db, '--library-db', 'none', '--fix', '--fix-line', '7', '--fix-rule', 'redundant-parentheses', '--apply')
  $before = Tree-Hash $d
  $r = Run $fixArgs
  Check 'F1 with --db, no project names the unit: exit 2, REFUSED (no-project), nothing written' (($r.Code -eq 2) -and ($r.Out -match 'REFUSED \(no-project\)') -and ((Tree-Hash $d) -ceq $before)) "exit $($r.Code); $($r.Out)"
  $r = Run ($fixArgs + '--no-compile-gate')
  Check 'F2 control: --no-compile-gate writes unbuilt (exit 0, parens stripped)' (($r.Code -eq 0) -and ([IO.File]::ReadAllText($u) -match 'X := \(A \+ B\);')) "exit $($r.Code); $($r.Out)"
  $d2 = Join-Path $Tmp 'b23loose'; [IO.Directory]::CreateDirectory($d2) | Out-Null
  $u2 = Join-Path $d2 'redundant_parens.pas'
  [IO.File]::WriteAllText($u2, $src, [Text.Encoding]::ASCII)
  $r = Run @('lint', $u2, '--fix', '--fix-line', '7', '--fix-rule', 'redundant-parentheses', '--apply')
  Check 'F3 control: a loose file with no index is unchanged (exit 0, parens stripped)' (($r.Code -eq 0) -and ([IO.File]::ReadAllText($u2) -match 'X := \(A \+ B\);')) "exit $($r.Code); $($r.Out)"
}
finally {
  Stop-Parked
  Pop-Location
  Write-Host "scratch: $Tmp"
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
exit 0
