<#
run_lint_tree_compile_probe.ps1 -- tier 3 compiles ONCE via a probe unit, stages
each dependent's .dfm, and reports findings against REAL paths.

WHY THIS EXISTS. T6 replaced 207 per-dependent dcc invocations with a single one:
a generated draglint_probe.pas in the shadow dir whose interface `uses` every
dependent. That change carries three things the older guard cannot see:

  * the RE-RUN. dcc stops at the first unit with errors, so a broken dependent
    must be excluded and the probe re-run, or every unit after it goes unchecked
    and tier 3 silently answers about half the closure.
  * the .dfm STAGING (T5). A form dependent carries an R-directive for its .dfm
    and dcc resolves that next to the unit -- which for a staged copy is the
    shadow dir. Without the sibling .dfm every form dependent dies F1026. This
    was invisible until the include path was fixed, because the compile died
    earlier, so it has never actually been demonstrated.
  * the REMAP. The old loop remapped only the edited unit, leaving dependents
    with a C:\TEMP\draglint_tree_... path no IDE can open.

ProbeD is the whole point of the .dfm case and it is reached only on the SECOND
pass, after ProbeA1 is excluded -- so a single assertion covers both the re-run
and the staging. If the re-run regresses, ProbeD is never compiled and the .dfm
assertion cannot fail for the right reason; the "ProbeD was actually reached"
check below exists to stop that passing vacuously.

Needs dcc64. Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Work = "$env:TEMP\dl-probe-guard"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($d){" -- $d"}else{''}))
  if(-not $ok){ $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $Work | Out-Null
Get-ChildItem $Work -File -ErrorAction SilentlyContinue | ForEach-Object { [IO.File]::Delete($_.FullName) }
function W([string]$p,[string[]]$l){ [IO.File]::WriteAllText($p, (($l -join "`r`n")+"`r`n"), [Text.Encoding]::ASCII) }

# ProbeB: the edited unit. Declares FreeProc; the buffer removes it.
W "$Work\ProbeB.pas" @(
  'unit ProbeB;','interface','procedure FreeProc;','procedure KeepProc;','implementation',
  'procedure FreeProc; begin end;','procedure KeepProc; begin end;','end.')
# ProbeA1: breaks when FreeProc goes.
W "$Work\ProbeA1.pas" @(
  'unit ProbeA1;','interface','implementation','uses ProbeB;',
  'procedure Go; begin FreeProc; end;','end.')
# ProbeD: fine, but carries a resource directive for its sibling .dfm (T5).
W "$Work\ProbeD.pas" @(
  'unit ProbeD;','interface','implementation','uses ProbeB;',
  '{$R ProbeD.dfm}','procedure GoD; begin FreeProc; end;','end.')
W "$Work\ProbeD.dfm" @('object ProbeDForm: TProbeDForm','end')
W "$Work\ProbeProj.dpr" @(
  'program ProbeProj;','uses',"  ProbeB in 'ProbeB.pas',","  ProbeA1 in 'ProbeA1.pas',","  ProbeD in 'ProbeD.pas';",'begin','end.')
# buffer: FreeProc removed from BOTH interface and implementation, so ProbeB
# itself still compiles and dcc gets as far as the dependents.
W "$Work\buf.pas" @(
  'unit ProbeB;','interface','procedure KeepProc;','implementation',
  'procedure KeepProc; begin end;','end.')

$db = "$Work\probe.sqlite"
& $Exe index $Work --db $db --rebuild *> $null
Check 'fixture indexed' (Test-Path $db)

$base = "$Work\base.json"
& $Exe lint-tree --unit "$Work\ProbeB.pas" --db $db --write-baseline $base --project "$Work\ProbeProj.dpr" --platform Win64 --format json *> $null
Check 'baseline captured' (Test-Path $base)

$raw = & $Exe lint-tree --unit "$Work\ProbeB.pas" --db $db --buffer "$Work\buf.pas" --baseline $base --project "$Work\ProbeProj.dpr" --platform Win64 --compile --format json 2>$null
$r = try { ($raw | Out-String) | ConvertFrom-Json } catch { $null }
Check 'lint-tree returned JSON' ($null -ne $r)
$cc = @($r.findings | Where-Object { $_.ref_kind -eq 'compile' })
Write-Host ("  compile findings: " + (($cc | ForEach-Object { (Split-Path $_.file -Leaf) + ':' + $_.message }) -join ' | ')) -ForegroundColor DarkGray

Check 'tier 3 ran' ($r.compiled -eq $true)
Check 'the BROKEN dependent is reported' `
      (@($cc | Where-Object { $_.file -match 'ProbeA1' }).Count -ge 1) `
      'ProbeA1 calls FreeProc, which the buffer removed'

# THE RE-RUN + .dfm STAGING, and the control that stops it passing vacuously.
# THE RE-RUN CONTROL, and it must be able to FAIL. ProbeD also calls FreeProc, so
# it breaks too -- but dcc stops at the FIRST failing unit, so ProbeD can only be
# reported if ProbeA1 was excluded and the probe re-run. If the re-run regresses,
# ProbeD is never compiled and this goes red.
#
# (The first version of this check asserted `.Count -ge 0`, which is true of every
#  possible input. That is the "guard incapable of failing" shape this repo has
#  shipped four times; it is recorded here because I wrote it into the very
#  control meant to prevent one.)
Check 'CONTROL the re-run happened -- ProbeD is reported too' `
      (@($cc | Where-Object { $_.file -match 'ProbeD' }).Count -ge 1) `
      'dcc stops at ProbeA1, so ProbeD is only compiled on the second pass'
Check 'T5: ProbeD fails on its CODE, not on a missing .dfm' `
      ((@($cc | Where-Object { $_.file -match 'ProbeD' -and $_.message -match 'E2003' }).Count -ge 1) -and
       (@($cc | Where-Object { $_.message -match 'F1026' -and $_.message -match '\.dfm' }).Count -eq 0)) `
      'ProbeD carries a resource directive; without its .dfm staged it dies F1026 before reaching the real error'

Check 'no finding points into the shadow directory' `
      (@($cc | Where-Object { $_.file -match 'draglint_tree_' }).Count -eq 0) `
      'a shadow path cannot be opened by an IDE'
Check 'the generated probe unit never appears as a finding' `
      (@($cc | Where-Object { $_.file -match 'draglint_probe' }).Count -eq 0)

# NEG: an unchanged buffer must not compile anything at all.
$raw2 = & $Exe lint-tree --unit "$Work\ProbeB.pas" --db $db --buffer "$Work\ProbeB.pas" --baseline $base --project "$Work\ProbeProj.dpr" --platform Win64 --compile --format json 2>$null
$r2 = try { ($raw2 | Out-String) | ConvertFrom-Json } catch { $null }
Check 'NEG unchanged buffer -> tier 3 does not run' ($r2.compiled -ne $true) `
      'compiling a closure on an unchanged interface burns a core per keystroke'

if($fail){ Write-Host 'PROBE GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PROBE GUARD: PASS' -ForegroundColor Green; exit 0