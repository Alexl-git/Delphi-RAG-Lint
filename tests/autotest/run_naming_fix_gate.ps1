<#
  run_naming_fix_gate.ps1 -- wave 148 RN item 5 (146 r2 follow-up): `lint --fix --apply` naming renames go through the
  compile gate whenever --project names a .dproj, with or without --compile-gate. 146 r2 made them proof-only: a
  rename was proved but written unbuilt. A rename is the one fix that edits declaration + every use across files, so
  it is the fix the build must see.

  Fixture: tests\fixtures\refactor\gatefix + one routine with a mis-cased local (local-var-casing, a naming rename).
  The gate is observed through a project whose BASELINE does not build (a second unit with a syntax error in the
  .dpr): the gate refuses dirty-baseline, the proof alone would write.
    g1  naming fix + --project (no --compile-gate), broken baseline: exit 1, REFUSED named, bytes identical.
    g2  naming fix + --project, clean baseline: exit 0, local renamed, the written project builds.
    c1  POSITIVE CONTROL: the same naming fix with NO --project writes on the broken baseline (exit 0, renamed):
        the guard fails if the naming fix stops firing (g1 would then pass vacuously).
    c2  CONTROL: a NON-naming fix (redundant-as-tobject, line 27) with --project and no --compile-gate still writes
        on the broken baseline: only renames are auto-gated, R3's opt-in for the other fixers is unchanged.
  RED on 1.46.0-alpha / lane/147-int 6fac0082: g1 writes the rename (exit 0).
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
$env:DRAGLINT_RENAME_TEST_UNGATED = '1' # no library in the fixture: the proof's own seam; the build gate is what is tested
$Fx  = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\gatefix").Path
$Tmp = Join-Path $env:TEMP ('namingfix_gate_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
$Ascii = [Text.Encoding]::ASCII
$Extra = "`r`nprocedure Counted;`r`nvar`r`n  my_count: Integer;`r`nbegin`r`n  my_count:= 1;`r`n  Inc(my_count);`r`nend;`r`n"
function New-Case([string]$Tag, [bool]$Broken) {
  $d = Join-Path $Tmp $Tag
  Copy-Item $Fx $d -Recurse
  $u = Join-Path $d 'GfUnit.pas'
  $t = [IO.File]::ReadAllText($u)
  $t = $t.Replace("procedure RunAll;`r`nbegin", $Extra.TrimStart() + "`r`nprocedure RunAll;`r`nbegin").Replace("  UseGood;`r`nend;", "  UseGood;`r`n  Counted;`r`nend;")
  [IO.File]::WriteAllText($u, $t, $Ascii)
  if ($Broken) {
    [IO.File]::WriteAllText((Join-Path $d 'GfBroken.pas'), "unit GfBroken;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nprocedure X;`r`nbegin`r`n  NoSuchRoutine(;`r`nend;`r`n`r`nend.`r`n", $Ascii)
    $dpr = Join-Path $d 'GfDemo.dpr'
    [IO.File]::WriteAllText($dpr, ([IO.File]::ReadAllText($dpr).Replace("GfUnit in 'GfUnit.pas';", "GfUnit in 'GfUnit.pas',`r`n  GfBroken in 'GfBroken.pas';")), $Ascii)
  }
  $db = Join-Path $d 'p.sqlite'
  & $Exe index --project (Join-Path $d 'GfDemo.dproj') --db $db --library-db none *> (Join-Path $Tmp "$Tag.index.log")
  return @{ Dir = $d; Db = $db; Proj = (Join-Path $d 'GfDemo.dproj'); Unit = $u }
}
function Fix($C, [string]$Rule, [string[]]$More) {
  $a = @('lint', '--in', $C.Unit, '--db', $C.Db, '--enable', $Rule, '--fix', '--fix-rule', $Rule, '--apply', '--no-backup', '--rsvars', $Rsvars) + $More
  $out = & $Exe @a 2>&1 | Out-String
  return @{ Code = $LASTEXITCODE; Out = $out }
}
function Hash($p) { return (Get-FileHash $p -Algorithm SHA1).Hash }
$Naming = 'local-var-casing'
try {
  $G1 = New-Case 'g1' $true; $h1 = Hash $G1.Unit
  $r = Fix $G1 $Naming @('--project', $G1.Proj)
  Check 'g1 broken baseline + --project: exit 1' ($r.Code -eq 1) "exit $($r.Code) $($r.Out)"
  Check 'g1 REFUSED named' ($r.Out -match 'REFUSED') $r.Out
  Check 'g1 bytes identical' ((Hash $G1.Unit) -eq $h1) ([IO.File]::ReadAllText($G1.Unit))

  $G2 = New-Case 'g2' $false
  $r = Fix $G2 $Naming @('--project', $G2.Proj)
  $t2 = [IO.File]::ReadAllText($G2.Unit)
  Check 'g2 clean baseline: exit 0' ($r.Code -eq 0) "exit $($r.Code) $($r.Out)"
  Check 'g2 local renamed' ($t2 -cnotmatch 'my_count' -and $t2 -match 'Inc\(\w+\)') $t2
  $bat = Join-Path $Tmp 'b.bat'
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /D `"$($G2.Dir)`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal GfDemo.dproj`r`n", $Ascii)
  $p = Start-Process -Wait -PassThru -NoNewWindow -FilePath cmd.exe -ArgumentList '/c', $bat -RedirectStandardOutput (Join-Path $Tmp 'b.out')
  Check 'g2 written project builds' ($p.ExitCode -eq 0) "msbuild exit $($p.ExitCode)"

  $C1 = New-Case 'c1' $true
  $r = Fix $C1 $Naming @()
  Check 'c1 POSITIVE CONTROL: no --project writes the rename (exit 0)' ($r.Code -eq 0 -and ([IO.File]::ReadAllText($C1.Unit) -cnotmatch 'my_count')) "exit $($r.Code) $($r.Out)"

  $C2 = New-Case 'c2' $true
  $r = Fix $C2 'redundant-as-tobject' @('--project', $C2.Proj, '--fix-line', '27')
  Check 'c2 CONTROL: a non-naming fix with --project stays ungated (writes)' ($r.Code -eq 0 -and ((Get-Content $C2.Unit)[26].Trim() -eq 'Take(P);')) "exit $($r.Code) $($r.Out)"
}
finally { try { [IO.Directory]::Delete($Tmp, $true) } catch { } }
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_naming_fix_gate: PASS'
