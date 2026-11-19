<#
  run_v151_GATE_compile_gate.ps1 -- wave v151 lane GATE (P14): the compile gate of `lint --fix --apply` is ON by
  default whenever --project names an existing .dproj, and it reports what the two builds said.

    build 1 (before the write) keeps ALL its messages: errors, warnings and hints. Any error stops the run
            (exit 1, REFUSED dirty-baseline, EVERY error line of build 1 on stderr, nothing written).
    build 2 (after the write) rolls every file back on an error (exit 1, REFUSED compile-error, every error line).
    success: the warnings and hints of build 2 that build 1 did not have are reported as NEW (keyed by file, code
            and message, never by line: the fix moves lines).

  Fixtures: tests\autotest\fixtures\v151-GATE\gtdemo (GtUnit.pas: Keep has `LOld:= 0` = H2077 in build 1 and build
  2; Probe has `LCount:= LCount` = W1036 + H2077, the self-assignment fix deletes it and dcc then says H2164 for
  LCount) and tests\fixtures\refactor\gatefix (line 35 `Take(AWalk as TObject)`: its fix does not compile).
    a  default ON: the breaking gatefix fix with --project and NO --compile-gate: exit 1, REFUSED (compile-error),
       bytes identical, the build-2 error line named.
    b  build 1 errors stop: gtdemo with TWO undeclared identifiers in Keep: exit 1, REFUSED (dirty-baseline), BOTH
       error lines on stderr (not just the first), build-1 counts line, bytes identical.
    c  NEW warnings / hints: clean gtdemo, self-assignment fix: exit 0, line 20 gone, H2164 for LCount reported as
       new, the H2077 for LOld (in both builds) NOT reported as new.
    d  POSITIVE CONTROL / opt-out: the breaking gatefix fix with --project --no-compile-gate writes `Take(AWalk);`
       (exit 0, no build): a gate that stopped firing would make a pass vacuously.
    e  --compile-gate together with --no-compile-gate: exit 2, nothing written.
  RED on 1.50.0-alpha (c96f0e65b): a writes (exit 0), b writes, c prints no report, d is an unknown flag.
  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing.
#>
param(
  [string]$Exe    = '',
  [string]$Rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'  # native stderr must not terminate; every call is checked by exit code
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$FxGt = (Resolve-Path "$PSScriptRoot\fixtures\v151-GATE\gtdemo").Path
$FxGf = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\gatefix").Path
$Tmp  = Join-Path $env:TEMP ('v151_gate_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function New-Case([string]$Tag, [string]$Fx, [string]$Proj, [string]$UnitName, [scriptblock]$Edit = $null) {
  $d = Join-Path $Tmp $Tag
  Copy-Item $Fx $d -Recurse
  $u = Join-Path $d $UnitName
  if ($Edit) { & $Edit $u }
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d $Proj) --db $db --library-db none *> (Join-Path $Tmp "$Tag.index.log")
  if ($LASTEXITCODE -ne 0) { throw "index $Tag exit $LASTEXITCODE" }
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d $Proj); Unit = $u }
}
function Fix($C, [string]$Rule, [int]$Line, [string[]]$Extra) {
  $a = @('lint', '--in', $C.Unit, '--db', $C.Db, '--enable', $Rule, '--fix', '--fix-rule', $Rule, '--fix-line', "$Line", '--apply', '--no-backup', '--rsvars', $Rsvars) + $Extra
  $out = & $Exe @a 2>&1 | Out-String
  return @{ Code = $LASTEXITCODE; Out = $out }
}
function Hash($p) { return (Get-FileHash $p -Algorithm SHA1).Hash }
function LineOf($p, [int]$n) { return (Get-Content $p)[$n - 1].Trim() }

try {
  # a: default ON -- no --compile-gate, the breaking fix is refused and rolled back
  $A = New-Case 'a' $FxGf 'GfDemo.dproj' 'GfUnit.pas'; $ha = Hash $A.Unit
  $r = Fix $A 'redundant-as-tobject' 35 @('--project', $A.Proj)
  Check 'a1 default gate: exit 1' ($r.Code -eq 1) "exit $($r.Code) $($r.Out)"
  Check 'a2 REFUSED (compile-error)' ($r.Out -match 'REFUSED \(compile-error\)') $r.Out
  Check 'a3 bytes identical' ((Hash $A.Unit) -eq $ha) (LineOf $A.Unit 35)
  Check 'a4 build-2 error line named' ($r.Out -match 'compile gate: build 2 error: .*E2010') $r.Out

  # b: build 1 has two errors: both reported, nothing written
  $B = New-Case 'b' $FxGt 'GtDemo.dproj' 'GtUnit.pas' {
    param($u)
    $t = [IO.File]::ReadAllText($u).Replace('LOld:= 0;', 'LOld:= GateMissingOne + GateMissingTwo;')
    [IO.File]::WriteAllText($u, $t, [Text.Encoding]::ASCII)
  }
  $hb = Hash $B.Unit
  $r = Fix $B 'self-assignment' 20 @('--project', $B.Proj)
  Check 'b1 dirty baseline: exit 1' ($r.Code -eq 1) "exit $($r.Code) $($r.Out)"
  Check 'b2 REFUSED (dirty-baseline)' ($r.Out -match 'REFUSED \(dirty-baseline\)') $r.Out
  Check 'b3 first error listed' ($r.Out -match 'compile gate: build 1 error: .*GateMissingOne') $r.Out
  Check 'b4 second error listed' ($r.Out -match 'compile gate: build 1 error: .*GateMissingTwo') $r.Out
  # dcc: two E2003 in GtUnit + F2063 in the .dpr; a unit that fails emits no warnings or hints
  Check 'b5 build-1 counts line' ($r.Out -match 'compile gate: build 1 \(before the write\): 3 error\(s\), 0 warning\(s\), 0 hint\(s\)') $r.Out
  Check 'b7 fatal F2063 listed too' ($r.Out -match 'compile gate: build 1 error: .*F2063') $r.Out
  Check 'b6 bytes identical' ((Hash $B.Unit) -eq $hb)

  # c: clean project, the fix lands; build 2's new hint is reported, build 1's surviving hint is not
  $Cc = New-Case 'c' $FxGt 'GtDemo.dproj' 'GtUnit.pas'
  $r = Fix $Cc 'self-assignment' 20 @('--project', $Cc.Proj)
  Check 'c1 exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  Check 'c2 self-assignment removed' (-not ([IO.File]::ReadAllText($Cc.Unit) -match 'LCount:= LCount')) (LineOf $Cc.Unit 20)
  Check 'c3 build-1 counts' ($r.Out -match 'compile gate: build 1 \(before the write\): 0 error\(s\), 1 warning\(s\), 2 hint\(s\)') $r.Out
  Check 'c4 new-message header' ($r.Out -match 'compile gate: 1 new warning\(s\)/hint\(s\) after the write') $r.Out
  Check 'c5 H2164 for LCount is new' ($r.Out -match 'compile gate: new: .*H2164.*LCount') $r.Out
  Check 'c6 LOld (both builds) is not new' (-not ($r.Out -match 'compile gate: new: .*LOld')) $r.Out
  Check 'c7 gone count' ($r.Out -match 'compile gate: 2 warning\(s\)/hint\(s\) of build 1 are gone') $r.Out

  # d: positive control -- opting out writes the breaking fix
  $D = New-Case 'd' $FxGf 'GfDemo.dproj' 'GfUnit.pas'
  $r = Fix $D 'redundant-as-tobject' 35 @('--project', $D.Proj, '--no-compile-gate')
  Check 'd1 opt-out exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  Check 'd2 opt-out wrote the breaking fix' ((LineOf $D.Unit 35) -eq 'Take(AWalk);') (LineOf $D.Unit 35)
  Check 'd3 opt-out did not build' (-not ($r.Out -match 'compile gate: build 1')) $r.Out

  # e: both flags
  $E = New-Case 'e' $FxGf 'GfDemo.dproj' 'GfUnit.pas'; $he = Hash $E.Unit
  $r = Fix $E 'redundant-as-tobject' 27 @('--project', $E.Proj, '--compile-gate', '--no-compile-gate')
  Check 'e1 both flags exit 2' ($r.Code -eq 2) "exit $($r.Code) $($r.Out)"
  Check 'e2 nothing written' ((Hash $E.Unit) -eq $he)
}
finally { try { [IO.Directory]::Delete($Tmp, $true) } catch { } }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_v151_GATE_compile_gate: PASS'
