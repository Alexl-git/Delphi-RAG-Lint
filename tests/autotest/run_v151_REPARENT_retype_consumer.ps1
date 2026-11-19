<#
  run_v151_REPARENT_retype_consumer.ps1 -- lane v151 REPARENT (P22): `extract-interface --retype-consumer <Routine>.<param>`
  retypes ONE parameter from a class to the interface the class implements, after the interface exists.

  The proof is a lifetime proof (the class's IInterface never counts references, so the interface temporary a caller's object
  reference turns into cannot free the caller's instance) plus a use proof (the body uses the parameter only through the
  interface, a nil test or Assigned). Every write goes through the scratch build and the compile gate.

  Fixture tests\autotest\fixtures\v151-REPARENT\retype: each consumer's declaration line in RcUse.pas says what must happen:
  `// RETYPE <routine>.<param> <class>`, `// REFUSE <kind> <routine>.<param> <class>`, or `// GATE ...` (the plan proves it,
  only the build rejects it). Needs dcc for the apply half: that half SKIPs without rsvars.bat.

  Positive controls: C1 the markers hold every outcome; P1 the comparer sees a wrong outcome; G* a retype only the build
  rejects is rolled back by the gate, so the plan is not the only proof. Real bytes: the program prints the same before and
  after each applied retype, and the instance a caller passed is still alive after the call.
#>
param(
  [string]$Exe = ''
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
$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
function Tree-Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Extension -notin '.sqlite', '.dcu', '.exe', '.rsm', '.map', '.drc', '.sqlite-wal', '.sqlite-shm', '.res', '.identcache', '.local', '.log' -and $_.FullName -notmatch '\\Win64\\|\\__history\\' } |
      Sort-Object FullName | ForEach-Object { "$($_.Name)|$([long]($_.LastWriteTimeUtc.Ticks / 10000000))|$((Get-FileHash $_.FullName -Algorithm SHA1).Hash)" }) -join "`n"
}
function Build-Project([string]$Proj, [string]$Tmp) {
  $bat = Join-Path $Tmp ([guid]::NewGuid().ToString('N') + '.bat')
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /d `"$(Split-Path $Proj)`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal `"$(Split-Path $Proj -Leaf)`"`r`nexit /b %ERRORLEVEL%`r`n", [Text.Encoding]::ASCII)
  $p = Start-Process -Wait -PassThru -NoNewWindow cmd.exe -ArgumentList "/c `"$bat`"" -RedirectStandardOutput "$bat.log" -RedirectStandardError "$bat.err"; $null = $p.Handle
  return $p.ExitCode
}
function Bare-Lf([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $lf = 0; for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) { $lf++ } }
  return $lf
}
$Fx = (Resolve-Path "$PSScriptRoot\fixtures\v151-REPARENT\retype").Path
$Tmp = Join-Path $env:TEMP ("v151_reparent_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function Reindex($P) {
  & { $ErrorActionPreference = 'Continue'; & $Exe index --project $P.Proj --db $P.Db --library-db none *> (Join-Path $Tmp "index.log") }
  if ($LASTEXITCODE -ne 0) { throw "index exit $LASTEXITCODE" }
}
function New-Project([string]$Name) {
  $d = Join-Path $Tmp $Name
  Copy-Item $Fx $d -Recurse
  $P = @{ Dir = $d; Db = (Join-Path $d 'p.sqlite'); Proj = (Join-Path $d 'RcProj.dproj'); Use = (Join-Path $d 'RcUse.pas'); Widget = (Join-Path $d 'RcWidget.pas'); Prog = (Join-Path $d 'Win64\Debug\RcProj.exe') }
  Reindex $P
  return $P
}
function Run-Json($P, [string[]]$More) {
  $o = & { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath((Join-Path $Tmp 'run.err')); [IO.File]::WriteAllText($dlErrFile, ''); & $Exe extract-interface --db $P.Db --project $P.Proj --library-db none --format json @More 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } }
  $script:LastExit = $LASTEXITCODE
  $script:LastErr = [IO.File]::ReadAllText((Join-Path $Tmp 'run.err'))
  try { return (($o -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) } catch { return $null }
}
function Read-Markers([string]$Path) {
  $list = @()
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    $m = [regex]::Match($l, '//\s*(RETYPE|REFUSE ([a-z-]+)|GATE)\s+(\S+)\s+(T\w+)\s*$')
    if ($m.Success) { $list += [pscustomobject]@{ Want = $(if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[1].Value }); Consumer = $m.Groups[3].Value; Class = $m.Groups[4].Value } }
  }
  return $list
}
function Outcome($Plan) {
  if ($null -eq $Plan) { return '<no document>' }
  if ($Plan.mode -ne 'retype-consumer') { return '<not a retype>' }
  if ($Plan.refusal) { return $Plan.refusal.kind }
  if (@($Plan.edits).Count -ge 1 -and @($Plan.edits | Where-Object { $_.after -notmatch [regex]::Escape($Plan.interface) }).Count -eq 0) { return 'RETYPE' }
  return '<no edit>'
}

try {
  Write-Host 'plan on the fixture'
  $A = New-Project 'plan'
  $before = Tree-Hash $A.Dir
  $marks = @(Read-Markers $A.Use)
  $kinds = @($marks | Where-Object { $_.Want -notin 'RETYPE', 'GATE' } | ForEach-Object Want | Sort-Object -Unique)
  Check 'C1 control: the markers hold every outcome' ((@($marks | Where-Object Want -eq 'RETYPE').Count -ge 5) -and ($kinds.Count -ge 12) -and (@($marks | Where-Object Want -eq 'GATE').Count -eq 1)) "$($marks.Count) markers; kinds: $($kinds -join ' ')"
  $got = @{}
  foreach ($mk in $marks) {
    $r = Run-Json $A @('--class', $mk.Class, '--retype-consumer', $mk.Consumer, '--plan')
    $o = Outcome $r
    $got[$mk.Consumer] = $o
    $want = if ($mk.Want -eq 'GATE') { 'RETYPE' } else { $mk.Want }
    Check "D1 $($mk.Consumer) ($($mk.Class)): $want" (($o -eq $want) -and ($script:LastExit -eq 0)) "got [$o] exit $script:LastExit $($r.refusal.reason) $script:LastErr"
    if ($r.refusal) { Check "D2 $($mk.Consumer): the refusal has a reason" ($r.refusal.reason -ne '') }
  }
  $wrong = @{}; foreach ($k in $got.Keys) { $wrong[$k] = $got[$k] }; $wrong['Leak.pC'] = 'RETYPE'
  Check 'P1 control: the comparer sees a wrong outcome' ($wrong['Leak.pC'] -ne (($marks | Where-Object Consumer -eq 'Leak.pC').Want))
  $r = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'ShowCount.pC', '--plan')
  Check 'D3 the plan names the interface, the type and the lifetime base' (($r.interface -eq 'IRcCounter') -and ($r.param_type -eq 'TRcCounter') -and ($r.lifetime -match 'TSingletonImplementation')) "$($r.interface) $($r.param_type) $($r.lifetime)"
  Check 'D4 a unit procedure: two edits, interface and implementation' ((@($r.edits).Count -eq 2) -and ($r.edits[0].after -match 'const pC: IRcCounter\); // RETYPE') -and ($r.edits[1].after -ceq 'procedure ShowCount(const pC: IRcCounter);')) (($r.edits | ForEach-Object after) -join ' | ')
  $r = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'TRcHost.Look.pC', '--plan')
  Check 'D5 a method: the class line and the implementation header' ((@($r.edits).Count -eq 2) -and ($r.edits[1].after -ceq 'procedure TRcHost.Look(pC: IRcCounter);')) (($r.edits | ForEach-Object after) -join ' | ')
  $r = Run-Json $A @('--class', 'TRcCounted', '--retype-consumer', 'CountedUse.pC', '--plan')
  Check 'D6 lifetime-refcounted names the counting base and the way out' (($r.refusal.reason -match 'TInterfacedObject') -and ($r.refusal.reason -match 'TSingletonImplementation'))
  $r = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'Peek.pC', '--plan')
  Check 'D7 use-not-interface names the line' ($r.refusal.reason -match 'Secret') "$($r.refusal.reason)"
  $r = Run-Json $A @('--class', 'TRcCounterKid', '--retype-consumer', 'KidUse.pK', '--plan', '--name', 'IRcNope')
  Check 'D8 --name that the chain does not list: not-implemented' ($r.refusal.kind -eq 'not-implemented') "$($r.refusal.kind)"
  Check 'D9 the plans wrote nothing' ((Tree-Hash $A.Dir) -ceq $before)

  Write-Host 'surface'
  $null = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'ShowCount.pC', '--plan', '--members', 'Bump')
  Check 'S1 --retype-consumer with --members exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'ShowCount.pC', '--plan', '--reparent-interfaced')
  Check 'S2 --retype-consumer with --reparent-interfaced exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'NoSuchRoutine.pC', '--plan')
  Check 'S3 an unknown routine exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'ShowCount.pNope', '--plan')
  Check 'S4 an unknown parameter exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--class', 'TRcCounter', '--retype-consumer', 'ShowCount', '--plan')
  Check 'S5 a spec without a dot exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--class', 'TRcCounted', '--retype-consumer', 'CountedUse.pC', '--apply')
  Check 'S6 --apply on a refusal exits 1' ($script:LastExit -eq 1) "exit $script:LastExit"
  Check 'S7 none of them wrote anything' ((Tree-Hash $A.Dir) -ceq $before)

  if (-not (Test-Path $Rsvars)) { Write-Host 'SKIP the apply half: no rsvars.bat' }
  else {
    Write-Host 'apply: real bytes'
    $B = New-Project 'apply'
    $orig = [IO.File]::ReadAllText($B.Use)
    Check 'A0 the untouched program builds' ((Build-Project $B.Proj $Tmp) -eq 0)
    $out1 = (& $B.Prog) -join "`n"
    Check 'A0b the program proves the instance outlives the calls' ($out1 -match 'final 3 42') "[$out1]"
    $r = Run-Json $B @('--class', 'TRcCounter', '--retype-consumer', 'ShowCount.pC', '--apply')
    Check 'A1 --apply exits 0, applied' (($script:LastExit -eq 0) -and ($r.applied -eq $true)) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail) $($r.refusal.kind)"
    Check 'A2 the gate reports its builds on stderr' ($script:LastErr -match 'compile gate:') "[$script:LastErr]"
    $t = [IO.File]::ReadAllText($B.Use)
    Check 'A3 the two headers are the ONLY change' ($t.Replace('const pC: IRcCounter', 'const pC: TRcCounter') -ceq $orig)
    Check 'A4 both headers changed' ([regex]::Matches($t, 'const pC: IRcCounter').Count -eq 2)
    Check 'A5 a backup, CRLF kept' ((Test-Path "$($B.Use).BCK1") -and ((Bare-Lf $B.Use) -eq 0))
    $out2 = (& $B.Prog) -join "`n"
    Check 'A6 the program prints what it printed: the caller''s instance survived the interface temporaries' (($out1 -ne '') -and ($out1 -ceq $out2)) "[$out1] vs [$out2]"
    Check 'P2 control: the comparison sees a changed output' ($out1 -cne ($out2 + 'x'))
    Reindex $B
    $fp = Run-Json $B @('--class', 'TRcCounter', '--retype-consumer', 'ShowCount.pC', '--plan')
    Check 'A7 fixed point: after a re-index the parameter is no longer the class' ($fp.refusal.kind -eq 'param-not-class') "$($fp.refusal.kind)"
    $r = Run-Json $B @('--class', 'TRcCounter', '--retype-consumer', 'TRcHost.Look.pC', '--apply')
    Check 'A8 a method applies: class line and implementation header' (($r.applied -eq $true) -and ([regex]::Matches([IO.File]::ReadAllText($B.Use), 'Look\(pC: IRcCounter\)').Count -eq 2)) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail)"
    Check 'A9 the program still prints what it printed' (((& $B.Prog) -join "`n") -ceq $out1)

    Write-Host 'apply: extract-interface first, then the retype'
    Reindex $B
    $r = Run-Json $B @('--class', 'TRcPlain', '--reparent-interfaced=norefcount', '--apply')
    Check 'E1 extract-interface --reparent-interfaced=norefcount applies' (($r.applied -eq $true) -and ([IO.File]::ReadAllText($B.Widget) -match 'TRcPlain = class\(TSingletonImplementation, IRcPlain\)')) "exit $script:LastExit; $($r.refusal.kind) $($r.gate.refusal) $($r.gate.detail)"
    $r = Run-Json $B @('--class', 'TRcPlain', '--retype-consumer', 'PlainUse.pP', '--plan')
    Check 'E2 before a re-index the retype does not see the interface' ($r.refusal.kind -in 'stale-file', 'no-iinterface', 'not-implemented') "$($r.refusal.kind)"
    Reindex $B
    $r = Run-Json $B @('--class', 'TRcPlain', '--retype-consumer', 'PlainUse.pP', '--apply')
    Check 'E3 after the re-index the retype applies' (($r.applied -eq $true) -and ([regex]::Matches([IO.File]::ReadAllText($B.Use), 'PlainUse\(pP: IRcPlain\)').Count -eq 2)) "exit $script:LastExit; $($r.refusal.kind) $($r.gate.refusal) $($r.gate.detail)"
    Check 'E4 the program still prints what it printed' (((& $B.Prog) -join "`n") -ceq $out1)

    Write-Host 'the gate'
    $G = New-Project 'gate'
    $gBefore = Tree-Hash $G.Dir
    $r = Run-Json $G @('--class', 'TRcCounter', '--retype-consumer', 'Hooked.pC', '--apply')
    Check 'G1 a retype only the build rejects: exit 1, refused by a build' (($script:LastExit -eq 1) -and ($r.gate.refusal -in 'scratch-compile-error', 'compile-error')) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail)"
    Check 'G2 the first dcc error is named' ($r.gate.detail -match 'E\d{4}') "$($r.gate.detail)"
    Check 'G3 the tree is byte- and time-identical' ((Tree-Hash $G.Dir) -ceq $gBefore)
  }
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
exit 0
