<#
  run_refact_narrow_param.ps1 -- lane 144 refact1, item 2: `narrow-param` retypes a class-typed parameter only when the
  static proof holds, names every refusal, and writes through the compile gate.

  The fixture tests\fixtures\refactor\narrowparam\NpUse.pas says on each routine's declaration line what must happen:
  NARROW <type> / REFUSE <kind> / NONE. Needs dcc for the apply half: that half SKIPs when rsvars.bat is missing.

  Positive controls: the markers must hold every outcome; P1 the comparer sees a wrong type; H1 hidden binding: after
  the apply the program still calls TMid.Hidden, proved by the type written (TMid, never TBase), since dcc would accept TBase.
#>
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\narrowparam").Path
$Tmp = Join-Path $env:TEMP ("refact_narrow_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function New-Project([string]$Name) {
  $d = Join-Path $Tmp $Name
  Copy-Item $Fx $d -Recurse
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'NarrowParam.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Name.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Name exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'NarrowParam.dproj'); Use = (Join-Path $d 'NpUse.pas') }
}
function Run-Json($P, [string[]]$More) {
  $o = & $Exe narrow-param --db $P.Db --project $P.Proj --library-db none --format json @More 2> (Join-Path $Tmp 'run.err')
  $script:LastExit = $LASTEXITCODE
  return (($o -join "`n") | ConvertFrom-Json)
}
function Tree-Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Extension -notin '.sqlite', '.dcu', '.exe', '.rsm', '.map', '.drc', '.sqlite-wal', '.sqlite-shm', '.res', '.identcache', '.local' -and $_.FullName -notmatch '\\Win64\\|\\__history\\' } |
      Sort-Object FullName | ForEach-Object { "$($_.Name)|$([long]($_.LastWriteTimeUtc.Ticks / 10000000))|$((Get-FileHash $_.FullName -Algorithm SHA1).Hash)" }) -join "`n"
}
# routine name -> outcome, for the parameter pP, from the markers (a routine's first marker: overloads share one)
function Read-Markers([string]$Path) {
  $map = @{}
  $host_ = ''
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    if ($l -match '^\s*implementation\s*$') { break }
    if ($l -match '^\s*(T\w+)\s*=\s*class') { $host_ = $Matches[1] }
    $m = [regex]::Match($l, '^\s*(?:procedure|function)\s+(\w+)\(.*//\s*(NARROW \w+|REFUSE [a-z-]+|NONE)\s*$')
    if ($m.Success) { $k = if ($l -match '^\s\s') { "NpUse.$host_.$($m.Groups[1].Value)" } else { "NpUse.$($m.Groups[1].Value)" }; if (-not $map.ContainsKey($k)) { $map[$k] = $m.Groups[2].Value } }
  }
  return $map
}
function Outcomes($Plan) {
  $map = @{}
  foreach ($f in $Plan.fixes) { if ($f.param -eq 'pP') { $map[$f.routine] = "NARROW $($f.to)" } }
  foreach ($f in $Plan.refused) { if ($f.param -eq 'pP' -and -not $map.ContainsKey($f.routine)) { $map[$f.routine] = "REFUSE $($f.kind)" } }
  return $map
}
function Compare-Map($Want, $Got) {
  $bad = @()
  foreach ($k in $Want.Keys) {
    $w = if ($Want[$k] -eq 'NONE') { '' } else { $Want[$k] }
    $g = if ($Got.ContainsKey($k)) { $Got[$k] } else { '' }
    if ($w -cne $g) { $bad += "${k}: want [$w] got [$g]" }
  }
  return $bad
}

try {
  Write-Host 'plan on the fixture'
  $A = New-Project 'plan'
  $before = Tree-Hash $A.Dir
  $plan = Run-Json $A @('--all', '--plan')
  Check 'D1 the plan exits 0' ($script:LastExit -eq 0) "exit $script:LastExit"
  Check 'D2 the document is narrow-param/1' ($plan.schema -eq 'narrow-param/1') "$($plan.schema)"
  $want = Read-Markers $A.Use
  $vals = @($want.Values)
  Check 'C1 control: the markers hold every outcome' ((@($vals | Where-Object { $_ -like 'NARROW*' }).Count -ge 4) -and ($vals -contains 'NONE') -and (@($vals | Where-Object { $_ -like 'REFUSE*' }).Count -ge 12)) ($vals -join ' ')
  $got = Outcomes $plan
  $bad = Compare-Map $want $got
  Check 'D3 every routine gets its marked outcome' ($bad.Count -eq 0) ("`n    " + ($bad -join "`n    "))
  $wrong = @{}; foreach ($k in $got.Keys) { $wrong[$k] = $got[$k] }; $wrong['NpUse.THost.ViaHidden'] = 'NARROW TBase'
  Check 'P1 control: the comparer sees a wrong type' (@(Compare-Map $want $wrong).Count -gt 0)
  Check 'H1 hidden non-virtual: narrows to the class that hides, never past it' ($got['NpUse.THost.ViaHidden'] -eq 'NARROW TMid') "$($got['NpUse.THost.ViaHidden'])"
  Check 'D4 uses are told: TRoot lives in a unit NpUse does not use' (@($plan.fixes | Where-Object { $_.routine -eq 'NpUse.THost.ViaRoot' -and $_.adds_uses -eq 'NpRoot' }).Count -eq 1)
  $reasonless = @($plan.refused | Where-Object { [string]::IsNullOrWhiteSpace($_.reason) -or [string]::IsNullOrWhiteSpace($_.kind) })
  Check 'D5 every refusal has a name and a reason' ($reasonless.Count -eq 0)
  Check 'D6 the plan wrote nothing' ((Tree-Hash $A.Dir) -ceq $before)
  $one = Run-Json $A @('--routine', 'NpUse.THost.ViaBase', '--param', 'pP', '--plan')
  Check 'D7 --routine narrows the scope' ((@($one.fixes).Count -eq 1) -and ($one.fixes[0].to -eq 'TBase') -and (@($one.refused).Count -eq 0))
  $txt = (& $Exe narrow-param --db $A.Db --library-db none --all --plan 2>&1) -join "`n"
  Check 'D8 the text form names counts and refusals' (($txt -match 'can narrow') -and ($txt -match 'refused\s+\S*NpUse\.pas:\d+.*with-body --'))

  Write-Host 'surface'
  & $Exe narrow-param --db $A.Db --library-db none *> $null
  Check 'S1 no scope exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  & $Exe narrow-param --db $A.Db --library-db none --routine NpUse.THost.ViaBase --apply *> $null
  Check 'S2 --apply without --project exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  $null = Run-Json $A @('--routine', 'NpUse.THost.ViaBase', '--apply', '--no-compile')
  Check 'S3 --apply --no-compile exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--routine', 'NpUse.THost.NoSuchRoutine', '--plan')
  Check 'S4 an unknown routine exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  Check 'S5 none of them wrote anything' ((Tree-Hash $A.Dir) -ceq $before)

  $rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
  if (-not (Test-Path $rsvars)) { Write-Host 'SKIP the apply half: no rsvars.bat' }
  else {
    Write-Host 'apply through the gate'
    $B = New-Project 'apply'
    $r = Run-Json $B @('--all', '--apply')
    Check 'A1 --all --apply exits 0, applied' (($script:LastExit -eq 0) -and ($r.applied -eq $true)) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail)"
    $t = [IO.File]::ReadAllText($B.Use)
    Check 'A2 both headers of a method are retyped' (([regex]::Matches($t, 'ViaBase\(pP: TBase\)').Count -eq 2) -and ($t -notmatch 'ViaBase\(pP: TLeaf\)'))
    Check 'A3 hidden: TMid in both headers' ([regex]::Matches($t, 'ViaHidden\(pP: TMid\)').Count -eq 2)
    Check 'A4 a free routine: declaration and body' ([regex]::Matches($t, 'FreeRoutine\(pP: TMid\)').Count -eq 2)
    Check 'A5 the unit of TRoot joined the interface uses' ($t -match '(?m)^\s*uses\s*\r?\n\s*NpRoot,|uses NpRoot,')
    Check 'A6 refused routines keep their type' (($t -match 'ViaWith\(pP: TLeaf\)') -and ($t -match 'ViaOver\(pP: TLeaf\)') -and ($t -match 'ViaGrouped\(pP, pQ: TLeaf\)'))
    Check 'A7 a backup and recovery.txt' ((Test-Path "$($B.Use).BCK1") -and (Test-Path (Join-Path $B.Dir 'recovery.txt')))
    $bytes = [IO.File]::ReadAllBytes($B.Use)
    $lf = 0; for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) { $lf++ } }
    Check 'A8 CRLF kept' ($lf -eq 0) "$lf bare LF"
    & $Exe index --project $B.Proj --db $B.Db --library-db none *> $null
    $again = Run-Json $B @('--all', '--plan')
    Check 'A9 fixed point: nothing left to narrow after a re-index' (@($again.fixes).Count -eq 0) (@($again.fixes | ForEach-Object { "$($_.routine) $($_.to)" }) -join '; ')

    Write-Host 'rollback'
    $C = New-Project 'broken'
    $cBefore = Tree-Hash $C.Dir
    $env:DRAGLINT_GATE_TEST_BREAK = '1'
    try { $r = Run-Json $C @('--all', '--apply') } finally { $env:DRAGLINT_GATE_TEST_BREAK = '' }
    Check 'R1 a failed after build exits 1, refusal compile-error, rolled back' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'compile-error') -and ($r.gate.rolled_back -eq $true)) "exit $script:LastExit; $($r.gate.refusal)"
    Check 'R2 the tree is byte- and time-identical' ((Tree-Hash $C.Dir) -ceq $cBefore)
  }
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
