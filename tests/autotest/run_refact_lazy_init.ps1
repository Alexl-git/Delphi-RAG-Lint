<#
  run_refact_lazy_init.ps1 -- lane 146 g3, E-REFACTOR-6 phase 1: `lazy-init` names what an initialization section does and,
  with --apply, moves its body verbatim into a run-once routine the section calls, through the scratch build and the gate.

  Fixture: tests\fixtures\refactor\lazyinit. Needs dcc for the apply half: that half SKIPs without rsvars.bat.

  Positive controls: C1 the fixture has heavy and light sections and every refusal; P1 the comparison of the printed order
  sees a swap. Real bytes: the whole program prints the same lines in the same order before and after, finalization included.
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
$Fx = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\lazyinit").Path
$Tmp = Join-Path $env:TEMP ("refact_li_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function New-Project([string]$Name) {
  $d = Join-Path $Tmp $Name
  Copy-Item $Fx $d -Recurse
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'LiProj.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Name.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Name exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'LiProj.dproj'); Heavy = (Join-Path $d 'LiHeavy.pas'); Prog = (Join-Path $d 'Win64\Debug\LiProj.exe') }
}
function Run-Json($P, [string[]]$More) {
  $o = & $Exe lazy-init --db $P.Db --project $P.Proj --library-db none --format json @More 2> (Join-Path $Tmp 'run.err')
  $script:LastExit = $LASTEXITCODE
  return (($o -join "`n") | ConvertFrom-Json)
}

try {
  Write-Host 'plan on the fixture'
  $A = New-Project 'plan'
  $before = Tree-Hash $A.Dir
  $plan = Run-Json $A @('--unit', 'LiHeavy', '--plan')
  Check 'D1 the plan exits 0' ($script:LastExit -eq 0) "exit $script:LastExit"
  Check 'D2 the document is lazy-init/1' ($plan.schema -eq 'lazy-init/1') "$($plan.schema)"
  $sec = $plan.sections[0]
  Check 'D3 five top-level statements' (@($sec.statements).Count -eq 5) (@($sec.statements | ForEach-Object text) -join ' | ')
  $heavy = @($sec.statements | Where-Object heavy)
  Check 'C1 control: one statement heavy, four light' ($heavy.Count -eq 1 -and $sec.heavy -eq $true) "$($heavy.Count)"
  Check 'D4 the heavy statement is the file access' ($heavy[0].text -match 'TFile\.Exists') "$($heavy[0].text)"
  $gp = @($sec.globals | Where-Object name -eq 'GPrivate')[0]
  $gs = @($sec.globals | Where-Object name -eq 'GShared')[0]
  Check 'D5 a private global read only in its unit is a candidate' (($gp.lazy_candidate -eq $true) -and ($gp.readers_elsewhere -eq 0)) "$($gp | ConvertTo-Json -Compress)"
  Check 'D6 an interface global read elsewhere is not' (($gs.lazy_candidate -eq $false) -and ($gs.readers_elsewhere -ge 1)) "$($gs | ConvertTo-Json -Compress)"
  $light = (Run-Json $A @('--unit', 'LiLight', '--plan')).sections[0]
  Check 'D7 a light section says so' ($light.heavy -eq $false)
  foreach ($c in @(@('LiNone', 'no-section'), @('LiBeginForm', 'no-section'), @('LiEmpty', 'empty-section'), @('LiIfdef', 'ifdef-around-section'), @('LiInc', 'include-in-section'))) {
    $r = (Run-Json $A @('--unit', $c[0], '--plan')).sections[0]
    Check "D8 $($c[0]) refuses $($c[1])" (($r.refusal.kind -eq $c[1]) -and ($r.refusal.reason -ne '') -and ($script:LastExit -eq 0)) "$($r.refusal.kind); exit $script:LastExit"
  }
  $all = Run-Json $A @('--all', '--plan')
  Check 'D9 --all lists only the sections the rule reports' ((@($all.sections).Count -eq 1) -and ($all.sections[0].unit -eq 'LiHeavy')) (@($all.sections | ForEach-Object unit) -join ' ')
  $named = (Run-Json $A @('--unit', 'LiHeavy', '--plan', '--name', 'BootHeavy')).sections[0]
  Check 'D10 --name names the routine' ($named.text -match 'procedure BootHeavy;')
  Check 'D11 the plans wrote nothing' ((Tree-Hash $A.Dir) -ceq $before)

  Write-Host 'surface'
  & $Exe lazy-init --db $A.Db --library-db none *> $null
  Check 'S1 no scope exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  $null = Run-Json $A @('--unit', 'LiHeavy', '--all', '--plan')
  Check 'S2 --unit and --all together exit 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--all', '--apply')
  Check 'S3 --all --apply exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  & $Exe lazy-init --db $A.Db --library-db none --unit LiHeavy --apply *> $null
  Check 'S4 --apply without --project exits 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  $null = Run-Json $A @('--unit', 'LiHeavy', '--apply', '--no-compile')
  Check 'S5 --apply --no-compile exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--unit', 'LiNoSuchUnit', '--plan')
  Check 'S6 an unknown unit exits 2' ($script:LastExit -eq 2) "exit $script:LastExit"
  $null = Run-Json $A @('--unit', 'LiNone', '--apply')
  Check 'S7 --apply on a refusal exits 1' ($script:LastExit -eq 1) "exit $script:LastExit"
  Check 'S8 none of them wrote anything' ((Tree-Hash $A.Dir) -ceq $before)

  if (-not (Test-Path $Rsvars)) { Write-Host 'SKIP the apply half: no rsvars.bat' }
  else {
    Write-Host 'apply: real bytes'
    $B = New-Project 'apply'
    $orig = [IO.File]::ReadAllText($B.Heavy)
    Check 'A0 the untouched program builds' ((Build-Project $B.Proj $Tmp) -eq 0)
    $out1 = @(& $B.Prog)
    Check 'C2 control: the program prints sections, main and finalization' (($out1 -contains 'LiHeavy init 1') -and ($out1 -contains 'LiHeavy final') -and (@($out1 | Where-Object { $_ -like 'main*' }).Count -eq 1)) ($out1 -join ' | ')
    $r = Run-Json $B @('--unit', 'LiHeavy', '--apply')
    Check 'A1 --apply exits 0, applied' (($script:LastExit -eq 0) -and ($r.applied -eq $true)) "exit $script:LastExit; $($r.gate.refusal) $($r.gate.detail)"
    $t = [IO.File]::ReadAllText($B.Heavy)
    $bodyStart = $orig.IndexOf('  // the order of these lines')
    $bodyEnd = ([regex]::Match($orig, '(?m)^finalization')).Index
    $body = $orig.Substring($bodyStart, $bodyEnd - $bodyStart).TrimEnd()
    Check 'A2 the body moved verbatim' ($t.Contains($body + "`r`nend;"))
    Check 'A3 the section only calls the routine' ($t -match '(?s)initialization\r\n  EnsureLiHeavyInitialized;\r\n\r\nfinalization')
    Check 'A4 the code above the section is untouched' ($t.StartsWith($orig.Substring(0, ([regex]::Match($orig, '(?m)^initialization')).Index)))
    Check 'A5 finalization is untouched' ($t.EndsWith($orig.Substring($bodyEnd)))
    Check 'A6 a backup and recovery.txt' ((Test-Path "$($B.Heavy).BCK1") -and (Test-Path (Join-Path $B.Dir 'recovery.txt')))
    Check 'A7 CRLF kept' ((Bare-Lf $B.Heavy) -eq 0)
    $out2 = @(& $B.Prog)
    Check 'A8 the program prints the same lines in the same order' (($out1 -join "`n") -ceq ($out2 -join "`n")) (($out2) -join ' | ')
    $swapped = @($out2); $t0 = $swapped[0]; $swapped[0] = $swapped[1]; $swapped[1] = $t0
    Check 'P1 control: the comparison sees a swap' (($out1 -join "`n") -cne ($swapped -join "`n"))
    & $Exe index --project $B.Proj --db $B.Db --library-db none *> $null
    $fp = (Run-Json $B @('--unit', 'LiHeavy', '--plan')).sections[0]
    Check 'A9 fixed point: a second run after a re-index is name-taken' ($fp.refusal.kind -eq 'name-taken') "$($fp.refusal.kind)"
    $r = Run-Json $B @('--unit', 'LiLight', '--apply')
    Check 'A10 a second unit in the same program applies' (($script:LastExit -eq 0) -and ($r.applied -eq $true)) "$($r.gate.refusal) $($r.gate.detail)"
    Check 'A11 still the same output' ((@(& $B.Prog) -join "`n") -ceq ($out1 -join "`n"))

    Write-Host 'the second gate'
    $G = New-Project 'rollback'
    $gBefore = Tree-Hash $G.Dir
    $env:DRAGLINT_GATE_TEST_BREAK = '1'
    try { $r = Run-Json $G @('--unit', 'LiHeavy', '--apply') } finally { $env:DRAGLINT_GATE_TEST_BREAK = '' }
    Check 'R1 past the scratch, a failed after build rolls back' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'compile-error') -and ($r.gate.rolled_back -eq $true)) "exit $script:LastExit; $($r.gate.refusal)"
    Check 'R2 the tree is byte- and time-identical' ((Tree-Hash $G.Dir) -ceq $gBefore)

    Write-Host 'the scratch gate'
    $H = New-Project 'unusable'
    $cross = Join-Path $H.Dir 'LiCrossReader.pas'
    [IO.File]::WriteAllText($cross, [IO.File]::ReadAllText($cross).Replace('function CrossValue: Integer;' + "`r`n`r`nimplementation", "nonsense here;`r`n`r`nimplementation"), [Text.Encoding]::ASCII)
    $hBefore = Tree-Hash $H.Dir
    $r = Run-Json $H @('--unit', 'LiHeavy', '--apply')
    Check 'G1 a program the mirror cannot build: exit 1, scratch-unusable' (($script:LastExit -eq 1) -and ($r.gate.refusal -eq 'scratch-unusable')) "exit $script:LastExit; $($r.gate.refusal)"
    Check 'G2 the tree is identical, never built' (((Tree-Hash $H.Dir) -ceq $hBefore) -and -not (Test-Path (Join-Path $H.Dir 'Win64')))
  }
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }