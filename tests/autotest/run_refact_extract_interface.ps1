<#
  run_refact_extract_interface.ps1 -- lane 146 g3, E-REFACTOR-5: `extract-interface` declares an interface from the members
  the project uses, adds it to the class, and writes only after a build on a scratch mirror AND the compile gate.

  The fixture tests\fixtures\refactor\extractiface\EiWidget.pas says on each line what must happen: IN / LEFT <kind> / OUT
  on TEiWidget's members, REFUSE <kind> on a class. Needs dcc for the apply half: that half SKIPs without rsvars.bat.

  Positive controls: C1 the markers hold every outcome; P1 the comparer sees a wrong answer; S-layer: TEiBroken is a rewrite the
  plan accepts and only a build rejects; R1 the test seam breaks a sound rewrite past the scratch, so the second gate is proved.
  Real bytes: the program prints the same before and after; a NEW program compiles against the interface and calls through it.
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
$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
function Tree-Hash([string]$Dir) {
  return (Get-ChildItem $Dir -Recurse -File | Where-Object { $_.Extension -notin '.sqlite', '.dcu', '.exe', '.rsm', '.map', '.drc', '.sqlite-wal', '.sqlite-shm', '.res', '.identcache', '.local', '.log' -and $_.FullName -notmatch '\\Win64\\|\\__history\\' } |
      Sort-Object FullName | ForEach-Object { "$($_.Name)|$([long]($_.LastWriteTimeUtc.Ticks / 10000000))|$((Get-FileHash $_.FullName -Algorithm SHA1).Hash)" }) -join "`n"
}
function Build-Project([string]$Proj, [string]$Tmp) {
  $bat = Join-Path $Tmp ([guid]::NewGuid().ToString('N') + '.bat')
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /d `"$(Split-Path $Proj)`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal `"$(Split-Path $Proj -Leaf)`"`r`nexit /b %ERRORLEVEL%`r`n", [Text.Encoding]::ASCII)
  $p = Start-Process -Wait -PassThru -NoNewWindow cmd.exe -ArgumentList "/c `"$bat`"" -RedirectStandardOutput "$bat.log" -RedirectStandardError "$bat.err"
  return $p.ExitCode
}
function Bare-Lf([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  $lf = 0; for ($i = 0; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10 -and ($i -eq 0 -or $bytes[$i - 1] -ne 13)) { $lf++ } }
  return $lf
}
$Fx = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\extractiface").Path
$Tmp = Join-Path $env:TEMP ("refact_ei_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function New-Project([string]$Name) {
  $d = Join-Path $Tmp $Name
  Copy-Item $Fx $d -Recurse
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'EiProj.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Name.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Name exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'EiProj.dproj'); Unit = (Join-Path $d 'EiWidget.pas'); Prog = (Join-Path $d 'Win64\Debug\EiProj.exe') }
}
function Run-Json($P, [string[]]$More) {
  $o = & $Exe extract-interface --db $P.Db --project $P.Proj --library-db none --format json @More 2> (Join-Path $Tmp 'run.err')
  $script:LastExit = $LASTEXITCODE
  return (($o -join "`n") | ConvertFrom-Json)
}
function Read-Markers([string]$Path) {
  $map = @{}; $inClass = $false
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    if ($l -match '//\s*EXTRACT\s*$') { $inClass = $true; continue }
    if ($inClass -and $l -match '^\s*end;') { break }
    if ($inClass) {
      $m = [regex]::Match($l, '^\s*(?:(?:class\s+)?(?:function|procedure|constructor|property)\s+)?(\w+).*//\s*(IN|OUT|LEFT [a-z-]+)\s*$')
      if ($m.Success) { $map[$m.Groups[1].Value] = $m.Groups[2].Value }
    }
  }
  return $map
}
function Outcomes($Plan) {
  $map = @{}
  foreach ($m in $Plan.members) { $map[$m.name] = 'IN' }
  foreach ($m in $Plan.left_out) { $map[$m.name] = "LEFT $($m.left_kind)" }
  return $map
}
function Compare-Map($Want, $Got) {
  $bad = @()
  foreach ($k in $Want.Keys) {
    $w = if ($Want[$k] -eq 'OUT') { '' } else { $Want[$k] }
    $g = if ($Got.ContainsKey($k)) { $Got[$k] } else { '' }
    if ($w -cne $g) { $bad += "${k}: want [$w] got [$g]" }
  }
  return $bad
}

try {
  Write-Host 'plan on the fixture'
  $A = New-Project 'plan'
  $before = Tree-Hash $A.Dir
  $plan = Run-Json $A @('--class', 'TEiWidget', '--plan')
  Check 'D1 the plan exits 0' ($script:LastExit -eq 0) "exit $script:LastExit"
  Check 'D2 the document is extract-interface/1' ($plan.schema -eq 'extract-interface/1') "$($plan.schema)"
  $want = Read-Markers $A.Unit
  $vals = @($want.Values)
  Check 'C1 control: the markers hold every outcome' ((@($vals | Where-Object { $_ -eq 'IN' }).Count -ge 6) -and (@($vals | Where-Object { $_ -eq 'OUT' }).Count -ge 3) -and (@($vals | Where-Object { $_ -like 'LEFT*' } | Sort-Object -Unique).Count -ge 5)) ($vals -join ' ')
  $got = Outcomes $plan
  $bad = @(Compare-Map $want $got)
  Check 'D3 every member gets its marked outcome' ($bad.Count -eq 0) ("`n    " + ($bad -join "`n    "))
  $wrong = @{}; foreach ($k in $got.Keys) { $wrong[$k] = $got[$k] }; $wrong['Hidden'] = 'IN'
  Check 'P1 control: the comparer sees a wrong outcome' (@(Compare-Map $want $wrong).Count -gt 0)
  Check 'D4 a directive the interface cannot hold is gone, overload stays' (($plan.text -match 'function Virt: string;') -and ($plan.text -notmatch 'virtual') -and ([regex]::Matches($plan.text, 'overload;').Count -eq 2))
  Check 'D5 the accessors of a used property join it, private as they are' (($plan.text -match 'function GetCount') -and ($plan.text -match 'procedure SetCount') -and ($plan.text -match 'property Count: Integer read GetCount write SetCount;'))
  Check 'D6 the own class in a signature gets a forward' (($plan.adds_forward -eq $true) -and ($plan.text -match '(?m)^\s*TEiWidget = class;'))
  Check 'D7 the heritage entry is planned' ($plan.heritage_after -eq 'TEiWidget = class(TInterfacedObject, IEiWidget)') "$($plan.heritage_after)"
  $again = Run-Json $A @('--class', 'TEiWidget', '--plan')
  Check 'D8 the GUID is the same on a second plan' (($plan.guid -eq $again.guid) -and ($plan.guid -match '^\{[0-9A-F-]{36}\}$')) "$($plan.guid)"
  $mine = Run-Json $A @('--class', 'TEiWidget', '--plan', '--members', 'Value,Nope', '--name', 'IMine')
  Check 'D9 --members replaces the set, --name names it, an unknown member is named' ((@($mine.members).Count -eq 1) -and ($mine.members[0].name -eq 'Value') -and ($mine.interface -eq 'IMine') -and (@($mine.left_out | Where-Object { $_.left_kind -eq 'no-such-member' }).Count -eq 1))
  $hidden = Run-Json $A @('--class', 'TEiWidget', '--plan', '--members', 'Hidden')
  Check 'D10 --members cannot widen visibility' (($hidden.refusal.kind -eq 'no-used-members') -and (@($hidden.left_out | Where-Object { $_.left_kind -eq 'not-public' }).Count -eq 1)) "$($hidden.refusal.kind)"

  foreach ($l in [IO.File]::ReadAllLines($A.Unit)) {
    $m = [regex]::Match($l, '^\s*(T\w+)(?:<T>)?\s*=\s*class.*//\s*REFUSE ([a-z-]+)\s*$')
    if ($m.Success) {
      $r = Run-Json $A @('--class', $m.Groups[1].Value, '--plan')
      Check "D11 $($m.Groups[1].Value) refuses $($m.Groups[2].Value)" (($r.refusal.kind -eq $m.Groups[2].Value) -and ($r.refusal.reason -ne '') -and ($script:LastExit -eq 0)) "$($r.refusal.kind); exit $script:LastExit"
    }
  }
  $r = Run-Json $A @('--class', 'TEiPlain', '--plan')
  Check 'D12 no IInterface: refused, the flag named' (($r.refusal.kind -eq 'no-iinterface') -and ($r.refusal.reason -match 'reparent-interfaced')) "$($r.refusal.kind)"
  $r = Run-Json $A @('--class', 'TEiDeep', '--plan', '--reparent-interfaced')
  Check 'D13 --reparent-interfaced stops at a direct TObject parent' ($r.refusal.kind -eq 'no-iinterface') "$($r.refusal.kind)"
  $r = Run-Json $A @('--class', 'TEiPlain', '--plan', '--reparent-interfaced=norefcount')
  Check 'D15 norefcount without System.Generics.Defaults in the unit: refused base-unit-missing' (($r.refusal.kind -eq 'base-unit-missing') -and ($r.refusal.reason -match 'Generics.Defaults')) "$($r.refusal.kind)"
  $r = Run-Json $A @('--class', 'TEiDeep', '--plan', '--reparent-interfaced=norefcount')
  Check 'D16 norefcount keeps the TObject-parent-only rule (control)' ($r.refusal.kind -eq 'no-iinterface') "$($r.refusal.kind)"
  $N = New-Project 'norefcount'
  $nt = [IO.File]::ReadAllText($N.Unit)
  [IO.File]::WriteAllText($N.Unit, ($nt -replace '(?m)^implementation\s*$', "implementation`r`n`r`nuses System.Generics.Defaults;"), [Text.Encoding]::ASCII)
  & $Exe index --project $N.Proj --db $N.Db --library-db none *> $null
  $r = Run-Json $N @('--class', 'TEiPlain', '--plan', '--reparent-interfaced=norefcount')
  Check 'D17 norefcount: the parent is TSingletonImplementation' ($r.heritage_after -eq 'TEiPlain = class(TSingletonImplementation, IEiPlain)') "$($r.heritage_after) $($r.refusal.kind)"
  $r = Run-Json $N @('--class', 'TEiPlain', '--plan', '--reparent-interfaced')
  Check 'D18 the bare flag still writes TInterfacedObject (control)' ($r.heritage_after -eq 'TEiPlain = class(TInterfacedObject, IEiPlain)') "$($r.heritage_after)"
  Check 'D14 the plans wrote nothing' ((Tree-Hash $A.Dir) -ceq $before)

  Write-Host 'surface'
  & $Exe extract-interface --db $A.Db --library-db none *> $null
  Check 'S1 no --class exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  & $Exe extract-interface --db $A.Db --library-db none --class TEiWidget --apply *> $null
  Check 'S2 --apply without --project exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  $null = Run-Json $A @('--class', 'TEiWidget', '--apply', '--no-compile')
  Check 'S3 --apply --no-compile exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--class', 'TNoSuchClass', '--plan')
  Check 'S4 an unknown class exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--class', 'TEiGeneric', '--apply')
  Check 'S5 --apply on a refusal exits 1' ($script:LastExit -eq 1) "exit $script:LastExit"
  Check 'S6 none of them wrote anything' ((Tree-Hash $A.Dir) -ceq $before)

  if (-not (Test-Path $Rsvars)) { Write-Host 'SKIP the apply half: no rsvars.bat' }
  else {
    Write-Host 'apply: real bytes'
    $B = New-Project 'apply'
    $orig = [IO.File]::ReadAllText($B.Unit)
    Check 'A0 the untouched program builds' ((Build-Project $B.Proj $Tmp) -eq 0)
    $out1 = (& $B.Prog) -join "`n"
    $planned = Run-Json $B @('--class', 'TEiWidget', '--plan')
    $r = Run-Json $B @('--class', 'TEiWidget', '--apply')
    Check 'A1 --apply exits 0, applied' (($script:LastExit -eq 0) -and ($r.applied -eq $true)) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail)"
    $t = [IO.File]::ReadAllText($B.Unit)
    Check 'A2 the file holds the planned text, byte for byte' ($t.Contains($planned.text))
    $restored = $t.Replace($planned.text, '').Replace('class(TInterfacedObject, IEiWidget)', 'class(TInterfacedObject)')
    Check 'A3 the plan text and the heritage entry are the ONLY change' ($restored -ceq $orig)
    Check 'A4 the interface stands before the class and its doc comment' ($t.IndexOf('IEiWidget = interface') -lt $t.IndexOf('/// <summary>The main case.'))
    Check 'A5 a backup and recovery.txt' ((Test-Path "$($B.Unit).BCK1") -and (Test-Path (Join-Path $B.Dir 'recovery.txt')))
    Check 'A6 CRLF kept' ((Bare-Lf $B.Unit) -eq 0)
    $out2 = (& $B.Prog) -join "`n"
    Check 'A7 the program prints what it printed' (($out1 -ne '') -and ($out1 -ceq $out2)) "[$out1] vs [$out2]"
    Check 'P2 control: the comparison sees a changed output' ($out1 -cne ($out2 + 'x'))
    $proof = Join-Path $B.Dir 'EiProof.dpr'
    [IO.File]::WriteAllText($proof, "program EiProof;`r`n{`$APPTYPE CONSOLE}`r`nuses EiWidget;`r`nvar I: IEiWidget;`r`nbegin`r`n  I:= TEiDesc.Create;`r`n  I.Count:= 11;`r`n  I.Over('abc');`r`n  Writeln(I.Virt, ' ', I.Count, ' ', I.Sum(1, 2), ' ', I.Value);`r`nend.`r`n", [Text.Encoding]::ASCII)
    $bat = Join-Path $Tmp 'proof.bat'
    [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /d `"$($B.Dir)`"`r`ndcc64 -B -Q EiProof.dpr`r`nexit /b %ERRORLEVEL%`r`n", [Text.Encoding]::ASCII)
    $p = Start-Process -Wait -PassThru -NoNewWindow cmd.exe -ArgumentList "/c `"$bat`"" -RedirectStandardOutput "$bat.log" -RedirectStandardError "$bat.err"
    Check 'A8 a NEW program compiles against the interface' ($p.ExitCode -eq 0) "exit $($p.ExitCode)"
    $po = (& (Join-Path $B.Dir 'EiProof.exe')) -join ''
    Check 'A9 a call through the interface reaches the override and the class' ($po -eq 'desc 3 3 42') "[$po]"
    & $Exe index --project $B.Proj --db $B.Db --library-db none *> $null
    $fp = Run-Json $B @('--class', 'TEiWidget', '--plan')
    Check 'A10 fixed point: a second run after a re-index is name-taken' ($fp.refusal.kind -eq 'name-taken') "$($fp.refusal.kind)"

    Write-Host 'apply: reparent'
    $C = New-Project 'reparent'
    $r = Run-Json $C @('--class', 'TEiPlain', '--reparent-interfaced', '--apply')
    Check 'A11 --reparent-interfaced applies' (($script:LastExit -eq 0) -and ($r.applied -eq $true)) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail)"
    Check 'A12 the parent is written' ([IO.File]::ReadAllText($C.Unit) -match 'TEiPlain = class\(TInterfacedObject, IEiPlain\)')
    Check 'A13 the program still prints what it printed' (((& $C.Prog) -join "`n") -ceq $out1)

    Write-Host 'the scratch gate'
    $D = New-Project 'broken'
    $dBefore = Tree-Hash $D.Dir
    $r = Run-Json $D @('--class', 'TEiBroken', '--apply')
    Check 'G1 a rewrite only a build rejects: exit 1, scratch-compile-error' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'scratch-compile-error')) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail)"
    Check 'G2 the first dcc line is named' ($r.gate.detail -match 'E\d{4}') "$($r.gate.detail)"
    Check 'G3 the tree is byte- and time-identical, no backup' ((Tree-Hash $D.Dir) -ceq $dBefore)
    Check 'G4 the real tree was never built' (-not (Test-Path (Join-Path $D.Dir 'Win64')))

    $E = New-Project 'unusable'
    $use = Join-Path $E.Dir 'EiUse.pas'
    [IO.File]::AppendAllText($use, "this does not compile", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($use, [IO.File]::ReadAllText($use).Replace('procedure RunAll;' + "`r`n`r`nimplementation", "procedure RunAll;`r`nnonsense here;`r`n`r`nimplementation"), [Text.Encoding]::ASCII)
    $eBefore = Tree-Hash $E.Dir
    $r = Run-Json $E @('--class', 'TEiWidget', '--apply')
    Check 'G5 a project the mirror cannot build: exit 1, scratch-unusable' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'scratch-unusable')) "exit $script:LastExit; $($r.gate.refusal)"
    Check 'G6 the tree is identical' ((Tree-Hash $E.Dir) -ceq $eBefore)

    $F = New-Project 'outputs'
    $abs = Join-Path $Tmp 'absolute_output'
    [IO.Directory]::CreateDirectory($abs) | Out-Null
    $x = [IO.File]::ReadAllText($F.Proj)
    [IO.File]::WriteAllText($F.Proj, $x.Replace('<DCC_ExeOutput>.\$(Platform)\$(Config)</DCC_ExeOutput>', "<DCC_ExeOutput>$abs</DCC_ExeOutput>"), [Text.Encoding]::ASCII)
    $second = Join-Path $Tmp 'rs'
    [IO.Directory]::CreateDirectory($second) | Out-Null
    $wrap = Join-Path $second 'rsvars.bat'
    [IO.File]::WriteAllText($wrap, "@echo off`r`nif exist `"%~dp0once`" (set PATH=) else (echo x> `"%~dp0once`" & call `"$Rsvars`")`r`n", [Text.Encoding]::ASCII)
    $r = Run-Json $F @('--class', 'TEiWidget', '--apply', '--rsvars', $wrap)
    Check 'G7 the scratch build passed, the real baseline failed by construction' ($r.gate.refusal -eq 'dirty-baseline') "$($r.gate.refusal) $($r.gate.detail)"
    Check 'G8 the scratch build linked nothing into an absolute output folder' (@(Get-ChildItem $abs -File).Count -eq 0) (@(Get-ChildItem $abs -File | ForEach-Object Name) -join ' ')

    Write-Host 'the second gate'
    $G = New-Project 'rollback'
    $gBefore = Tree-Hash $G.Dir
    $env:DRAGLINT_GATE_TEST_BREAK = '1'
    try { $r = Run-Json $G @('--class', 'TEiWidget', '--apply') } finally { $env:DRAGLINT_GATE_TEST_BREAK = '' }
    Check 'R1 past the scratch, a failed after build rolls back' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'compile-error') -and ($r.gate.rolled_back -eq $true)) "exit $script:LastExit; $($r.gate.refusal)"
    Check 'R2 the tree is byte- and time-identical' ((Tree-Hash $G.Dir) -ceq $gBefore)
  }
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }