<#
  run_refact_redundant_cast.ps1 -- lane 144 refact1, T0 + item 1: `lint --fix --fix-rule redundant-cast`
  removes identity casts only, names every refusal, and writes through the compile gate.

  The fixture tests\fixtures\refactor\redcast\RcUse.pas says on each cast line what must happen:
  FIX / REFUSE <kind> / NONE, in column order. Needs dcc for the apply half: that half SKIPs when
  rsvars.bat is missing. Every project and DB copy lives under %TEMP%.

  Positive controls: the marker reader must find at least one of each outcome (a reader that finds
  nothing would pass vacuously); P1 a plan with a dropped fix is detected by the same comparer;
  the batch check A9 fails on any engine whose text fixer still strips the cast.
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
$Fx = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\redcast").Path
$Tmp = Join-Path $env:TEMP ("refact_redcast_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
$RuleArgs = @('--fix', '--fix-rule', 'redundant-cast', '--library-db', 'none')

function New-Project([string]$Name) {
  $d = Join-Path $Tmp $Name
  Copy-Item $Fx $d -Recurse
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'RedCast.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Name.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Name exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'RedCast.dproj'); Use = (Join-Path $d 'RcUse.pas') }
}
function Plan-Json($P, [string[]]$More = @()) {
  $o = & $Exe lint @RuleArgs --db $P.Db --project $P.Proj --format json @More 2> (Join-Path $Tmp 'plan.err')
  $script:LastExit = $LASTEXITCODE
  return (($o -join "`n") | ConvertFrom-Json)
}
function Tree-Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Extension -notin '.sqlite', '.dcu', '.exe', '.rsm', '.map', '.drc', '.sqlite-wal', '.sqlite-shm', '.res', '.identcache', '.local' -and $_.FullName -notmatch '\\Win64\\|\\__history\\' } |
      Sort-Object FullName | ForEach-Object { "$($_.Name)|$([long]($_.LastWriteTimeUtc.Ticks / 10000000))|$((Get-FileHash $_.FullName -Algorithm SHA1).Hash)" }) -join "`n"
}
# line -> ordered outcomes, from the markers
function Read-Markers([string]$Path) {
  $map = @{}
  $n = 0
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    $n++
    $m = [regex]::Match($l, '//\s*((FIX|NONE|REFUSE\s+[a-z-]+)(\s+(FIX|REFUSE\s+[a-z-]+))*)\s*$')
    if ($m.Success -and $n -gt 8) { $map[$n] = @([regex]::Matches($m.Groups[1].Value, 'FIX|NONE|REFUSE\s+[a-z-]+') | ForEach-Object { ($_.Value -replace '\s+', ' ') }) }
  }
  return $map
}
function Outcomes($Plan, [string]$FileLeaf) {
  $all = @()
  foreach ($f in $Plan.fixes) { if ((Split-Path $f.file -Leaf) -eq $FileLeaf) { $all += [pscustomobject]@{ line = [int]$f.line; col = [int]$f.col; o = 'FIX' } } }
  foreach ($f in $Plan.refused) { if ((Split-Path $f.file -Leaf) -eq $FileLeaf) { $all += [pscustomobject]@{ line = [int]$f.line; col = [int]$f.col; o = "REFUSE $($f.kind)" } } }
  $map = @{}
  foreach ($g in ($all | Group-Object line)) { $map[[int]$g.Name] = @($g.Group | Sort-Object col | ForEach-Object o) }
  return $map
}
function Compare-Map($Want, $Got) {
  $bad = @()
  foreach ($k in $Want.Keys) {
    $w = @($Want[$k] | Where-Object { $_ -ne 'NONE' }) -join ','
    $g = if ($Got.ContainsKey($k)) { @($Got[$k]) -join ',' } else { '' }
    if ($w -cne $g) { $bad += "line ${k}: want [$w] got [$g]" }
  }
  foreach ($k in $Got.Keys) { if (-not $Want.ContainsKey($k)) { $bad += "line ${k}: unmarked [$(@($Got[$k]) -join ',')]" } }
  return $bad
}

try {
  # ---- the plan --------------------------------------------------------------------------------
  Write-Host 'plan on the fixture'
  $A = New-Project 'plan'
  $before = Tree-Hash $A.Dir
  $plan = Plan-Json $A
  Check 'D1 the dry run exits 0' ($script:LastExit -eq 0) "exit $script:LastExit"
  Check 'D2 the document is redundant-cast/1' ($plan.schema -eq 'redundant-cast/1') "$($plan.schema)"
  $want = Read-Markers $A.Use
  $flat = @($want.Values | ForEach-Object { $_ })
  Check 'C1 control: the markers hold every outcome' ((($flat -contains 'FIX') -and ($flat -contains 'NONE') -and (@($flat | Where-Object { $_ -like 'REFUSE*' }).Count -ge 15))) ($flat -join ' ')
  $got = Outcomes $plan 'RcUse.pas'
  $bad = Compare-Map $want $got
  Check 'D3 every cast line gets the marked outcome, in column order' ($bad.Count -eq 0) ("`n    " + ($bad -join "`n    "))
  $dropped = @{}; foreach ($k in $got.Keys) { $dropped[$k] = $got[$k] }
  $firstFix = @($want.Keys | Where-Object { $want[$_] -contains 'FIX' } | Sort-Object)[0]
  $dropped.Remove($firstFix)
  Check 'P1 control: the comparer sees a dropped fix' (@(Compare-Map $want $dropped).Count -gt 0)
  Check 'D4 the real conversions are counted, not listed' ([int]$plan.not_identity -ge 2) "$($plan.not_identity)"
  $reasonless = @($plan.refused | Where-Object { [string]::IsNullOrWhiteSpace($_.reason) -or [string]::IsNullOrWhiteSpace($_.kind) })
  Check 'D5 every refusal has a name and a reason' ($reasonless.Count -eq 0)
  Check 'D6 the dry run wrote nothing' ((Tree-Hash $A.Dir) -ceq $before)
  $txt = (& $Exe lint @RuleArgs --db $A.Db --project $A.Proj 2>&1) -join "`n"
  Check 'D7 the text form names the counts and each refusal' (($txt -match 'identity cast\(s\) to remove') -and ($txt -match 'refused\s+\S*RcUse\.pas:\d+:\d+.*with-body --'))
  & $Exe lint @RuleArgs --db $A.Db --project $A.Proj --format json --fix-line 2 *> $null
  $one = Plan-Json $A @('--fix-line', [string]$firstFix)
  Check 'D8 --fix-line narrows to the line' ((@($one.fixes).Count -eq 1) -and (@($one.refused).Count -eq 0)) "fixes=$(@($one.fixes).Count) refused=$(@($one.refused).Count)"

  # ---- surface -----------------------------------------------------------------------------------
  Write-Host 'surface'
  & $Exe lint @RuleArgs --db $A.Db --apply *> $null
  Check 'S1 --apply without --project exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  & $Exe lint @RuleArgs --db $A.Db --project $A.Proj --apply --no-compile *> $null
  Check 'S2 --apply --no-compile exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  Check 'S3 neither wrote anything' ((Tree-Hash $A.Dir) -ceq $before)
  $batch = (& $Exe lint $A.Use --db $A.Db --library-db none --fix --apply --no-backup 2>&1) -join "`n"
  Check 'S4 a batch lint --fix leaves the casts to the gated path, and says so' (([IO.File]::ReadAllText($A.Use) -match 'B:= TBase\(B\); // FIX') -and ($batch -match 'compile gate')) ($batch.Substring(0, [Math]::Min(300, $batch.Length)))

  $rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
  if (-not (Test-Path $rsvars)) { Write-Host 'SKIP the apply half: no rsvars.bat' }
  else {
    # ---- the gate -------------------------------------------------------------------------------
    Write-Host 'apply through the gate'
    $B = New-Project 'apply'
    $srcBefore = [IO.File]::ReadAllLines($B.Use)
    $r = Plan-Json $B @('--apply')
    Check 'A1 --apply exits 0' ($script:LastExit -eq 0) "exit $script:LastExit; $($r.gate.detail)"
    Check 'A2 applied = true, the gate reports no refusal' (($r.applied -eq $true) -and ([string]$r.gate.refusal -eq '')) "$($r.gate.refusal)"
    $after = [IO.File]::ReadAllLines($B.Use)
    Check 'A3 line count unchanged' ($after.Count -eq $srcBefore.Count)
    Check 'A4 the identity forms are gone' (($after -contains '  B:= B; // FIX') -and ($after -contains '  TBase(B).Foo; // FIX' -eq $false) -and ($after -contains '  B.Foo; // FIX') -and ($after -contains '  B:= Hold.GetAt(N + 1); // FIX') -and ($after -contains '  E:= eB; // FIX'))
    Check 'A5 a nested cast loses its inner half' ($after -contains '  B:= TBase(B); // REFUSE nested-cast FIX')
    $refLines = @(); $n = 0
    foreach ($l in $srcBefore) { $n++; if ($l -match '// REFUSE [a-z-]+$' -and $l -notmatch 'nested-cast') { $refLines += $n } }
    $changed = @($refLines | Where-Object { $srcBefore[$_ - 1] -cne $after[$_ - 1] })
    Check 'A6 every refused line is byte-identical' ($changed.Count -eq 0) ($changed -join ',')
    Check 'A7 a backup per changed file, and recovery.txt' ((Test-Path "$($B.Use).BCK1") -and (Test-Path (Join-Path $B.Dir 'recovery.txt')))
    $bytes = [IO.File]::ReadAllBytes($B.Use)
    $lf = 0; for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) { $lf++ } }
    Check 'A8 CRLF kept' ($lf -eq 0) "$lf bare LF"
    & $Exe index --project $B.Proj --db $B.Db --library-db none *> $null
    $second = Plan-Json $B
    $outer = @($second.fixes | Where-Object { $_.cast -eq 'TBase(B)' })
    Check 'A9 after a re-index the nested outer half is a fix' ($outer.Count -ge 1) (@($second.fixes | ForEach-Object cast) -join ' ')
    $r2 = Plan-Json $B @('--apply')
    & $Exe index --project $B.Proj --db $B.Db --library-db none *> $null
    $third = Plan-Json $B
    Check 'A10 the third pass finds nothing left to fix (fixed point)' (($r2.applied -eq $true) -and (@($third.fixes).Count -eq 0)) (@($third.fixes | ForEach-Object cast) -join ' ')

    # the IDE's 'Fix it' (int2 1.44.1): the flags StructureForm.FixItClick builds; without --project it exited 2
    Write-Host 'the IDE command'
    $I = New-Project 'ide'
    $iSrc = [IO.File]::ReadAllLines($I.Use)
    $iLine = [Array]::IndexOf($iSrc, '  B:= TBase(B); // FIX') + 1
    $iBase = @('--file', $I.Use, '--fix', '--fix-line', $iLine, '--fix-rule', 'redundant-cast', '--library-db', 'none', '--db', $I.Db, '--apply')
    & $Exe lint @iBase *> $null
    Check 'I1 control: the old command, no --project, exits 2 and writes nothing' (($LASTEXITCODE -eq 2) -and ([IO.File]::ReadAllLines($I.Use)[$iLine - 1] -ceq $iSrc[$iLine - 1])) "exit $LASTEXITCODE"
    & $Exe lint @iBase --project $I.Proj --platform win64 *> $null
    Check 'I2 with --project it exits 0 and removes that cast' (($LASTEXITCODE -eq 0) -and ([IO.File]::ReadAllLines($I.Use)[$iLine - 1] -ceq '  B:= B; // FIX')) "exit $LASTEXITCODE"
    $iForm = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\src\delphi-plugin\DragLint.Plugin.StructureForm.pas'))
    Check 'I3 the plugin sends --project for this rule' ($iForm -match 'CRedundantCastRule\) then' -and $iForm.Contains('--fix-rule "%s" --project "%s" --db "%s" --platform %s --apply'))

    Write-Host 'rollback'
    $C = New-Project 'broken'
    $cBefore = Tree-Hash $C.Dir
    $env:DRAGLINT_GATE_TEST_BREAK = '1'
    try { $r = Plan-Json $C @('--apply') } finally { $env:DRAGLINT_GATE_TEST_BREAK = '' }
    Check 'R1 a failed after build exits 1, refusal compile-error' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'compile-error') -and ($r.gate.rolled_back -eq $true)) "exit $script:LastExit; $($r.gate.refusal); $($r.gate.detail)"
    Check 'R2 the tree is byte- and time-identical, no backup, no recovery.txt' ((Tree-Hash $C.Dir) -ceq $cBefore)

    Write-Host 'dirty baseline'
    $D = New-Project 'dirty'
    $o = Join-Path $D.Dir 'RcOther.pas'
    [IO.File]::WriteAllText($o, [IO.File]::ReadAllText($o).Replace('Result:= pValue;', 'Result:= pValueX;'))
    & $Exe index --project $D.Proj --db $D.Db --library-db none *> $null
    $dBefore = Tree-Hash $D.Dir
    $r = Plan-Json $D @('--apply')
    Check 'B1 a project that does not build refuses: exit 1, dirty-baseline' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'dirty-baseline')) "exit $script:LastExit; $($r.gate.refusal)"
    Check 'B2 nothing was written' ((Tree-Hash $D.Dir) -ceq $dBefore)
  }
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
