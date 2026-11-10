<#
  run_lintfix_compilegate.ps1 -- wave 147 lane R3 (E-COMPILEGATE-ADOPT-FIXERS): the generic `lint --fix` writers
  adopt the opt-in compile gate. `lint --fix --apply --project <X.dproj> --compile-gate` writes through the gate:
  baseline build, all-or-nothing write, after build, rollback on a compile error. Without --compile-gate nothing
  changes (--project stays the ownership filter).

  Fixture tests\fixtures\refactor\gatefix: GfUnit.pas line 27 `Take(P as TObject)` (redundant: the fix compiles),
  line 35 `Take(AWalk as TObject)` where AWalk is an INTERFACE named Walker (the rule flags it, the fix is
  `Take(AWalk)` = E2010, the project no longer builds).
    a  bad fix + gate: exit 1, REFUSED on stderr, GfUnit.pas byte-identical.
    b  good fix + gate: exit 0, line 27 is `Take(P);`, line 35 untouched, the written project builds.
    c  POSITIVE CONTROL: the same bad fix WITHOUT --compile-gate writes `Take(AWalk);` (exit 0): the guard fails
       if the fix stops being a breaking one or the gate is on by default.
    d  --json path: bad fix + gate: exit 1, bytes identical.
    e  --compile-gate without --project <X.dproj>, and without --fix: exit 2, nothing written.
  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing. Run against the 1.46.0 engine: a is the RED (the flag is unknown).
#>
param(
  [string]$Exe    = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Continue'  # native stderr (the engine's 'loaded defaults' banner) must not terminate; every call is checked by exit code
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\gatefix").Path
$Tmp = Join-Path $env:TEMP ('lintfix_gate_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
$Rule = 'redundant-as-tobject'
function New-Case([string]$Tag) {
  $d = Join-Path $Tmp $Tag
  Copy-Item $Fx $d -Recurse
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'GfDemo.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Tag.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Tag exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'GfDemo.dproj'); Unit = (Join-Path $d 'GfUnit.pas') }
}
function Fix($C, [int]$Line, [string[]]$Extra) {
  $a = @('lint', '--in', $C.Unit, '--db', $C.Db, '--enable', $Rule, '--fix', '--fix-rule', $Rule, '--fix-line', "$Line", '--apply', '--no-backup', '--rsvars', $Rsvars) + $Extra
  $out = & $Exe @a 2>&1 | Out-String
  return @{ Code = $LASTEXITCODE; Out = $out }
}
function Hash($p) { return (Get-FileHash $p -Algorithm SHA1).Hash }
function LineOf($p, [int]$n) { return (Get-Content $p)[$n - 1].Trim() }
try {
  # a: the bad fix is refused and rolled back
  $A = New-Case 'a'; $h0 = Hash $A.Unit
  $r = Fix $A 35 @('--project', $A.Proj, '--compile-gate')
  Check 'a1 exit 1' ($r.Code -eq 1) "exit $($r.Code) $($r.Out)"
  Check 'a2 REFUSED named' ($r.Out -match 'REFUSED \(') $r.Out
  Check 'a3 bytes identical' ((Hash $A.Unit) -eq $h0) (LineOf $A.Unit 35)
  # d: the same through --json
  $D = New-Case 'd'; $hd = Hash $D.Unit
  $r = Fix $D 35 @('--project', $D.Proj, '--compile-gate', '--json')
  Check 'd1 json exit 1' ($r.Code -eq 1) "exit $($r.Code)"
  Check 'd2 json bytes identical' ((Hash $D.Unit) -eq $hd) (LineOf $D.Unit 35)
  # b: the good fix lands and the project builds
  $B = New-Case 'b'
  $r = Fix $B 27 @('--project', $B.Proj, '--compile-gate')
  Check 'b1 exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  Check 'b2 line 27 rewritten' ((LineOf $B.Unit 27) -eq 'Take(P);') (LineOf $B.Unit 27)
  Check 'b3 line 35 untouched' ((LineOf $B.Unit 35) -eq 'Take(AWalk as TObject);') (LineOf $B.Unit 35)
  $bat = Join-Path $Tmp 'b.bat'
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /D `"$($B.Dir)`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal GfDemo.dproj`r`n", [Text.Encoding]::ASCII)
  $p = Start-Process -Wait -PassThru -NoNewWindow -FilePath cmd.exe -ArgumentList '/c', $bat -RedirectStandardOutput (Join-Path $Tmp 'b.out')
  Check 'b4 written project builds' ($p.ExitCode -eq 0) "msbuild exit $($p.ExitCode)"
  # c: positive control, no gate = the break is written
  $Cc = New-Case 'c'
  $r = Fix $Cc 35 @('--project', $Cc.Proj)
  Check 'c1 control exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  Check 'c2 control wrote the breaking fix' ((LineOf $Cc.Unit 35) -eq 'Take(AWalk);') (LineOf $Cc.Unit 35)
  # e: usage errors
  $E = New-Case 'e'; $he = Hash $E.Unit
  $r = Fix $E 27 @('--compile-gate')
  Check 'e1 no --project exit 2' ($r.Code -eq 2) "exit $($r.Code) $($r.Out)"
  $r = & $Exe lint --in $E.Unit --db $E.Db --enable $Rule --project $E.Proj --compile-gate 2>&1 | Out-String
  Check 'e2 no --fix exit 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  Check 'e3 nothing written' ((Hash $E.Unit) -eq $he)
  # f: lint-all / lint-project / check-ast share the lint option parse; without --fix they REFUSE
  #    --compile-gate (exit 2) instead of ignoring it (controller ruling 2026-11-08). Control: the same
  #    verb without the flag is not exit 2.
  foreach ($v in 'lint-all', 'lint-project', 'check-ast') {
    $r = & $Exe $v --db $E.Db --compile-gate 2>&1 | Out-String
    Check "f $v --compile-gate without --fix exit 2" (($LASTEXITCODE -eq 2) -and ($r -match 'needs --fix')) "exit $LASTEXITCODE"
  }
  $r = & $Exe lint-all --output "$env:TEMP\dl-lintall-$PID.txt" --db $E.Db 2>&1 | Out-String
  Check 'f control: lint-all without the flag is not exit 2' ($LASTEXITCODE -ne 2) "exit $LASTEXITCODE"
}
finally { try { [IO.Directory]::Delete($Tmp, $true) } catch { } }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_lintfix_compilegate: PASS'