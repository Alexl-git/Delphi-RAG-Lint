<#
run_lint_tree_compile_shadow.ps1 -- tier 3 compiles dependents against the
UNSAVED buffer, and the shadow copy beats a stale .dcu.

WHY THE STALE .DCU STEP IS THE WHOLE TEST. lint-tree --compile stages the edited
unit into a shadow directory and puts that directory FIRST on dcc's unit search
path, so a dependent compiled from its real location binds the SHADOW uB rather
than the one on disk. That precedence is an ASSUMPTION until something proves
it: dcc will happily bind a previously built uB.dcu instead, in which case tier 3
reports a clean compile for exactly the edit it exists to catch -- a silent
all-clear, the worst failure this feature can have.

So case 2 builds uB.dcu FIRST, from the version that still declares FreeProc,
and only then asks tier 3 to compile against a buffer that removes it. If the
shadow loses to the .dcu, the compile succeeds and this guard goes red. Without
that step a passing run would prove nothing at all.

THE NEGATIVE MATTERS AS MUCH. Case 3 runs --compile with a buffer identical to
disk. Tier 3 must report NOTHING: a tier that fires on an unchanged interface
would spend seconds of dcc per idle keystroke and be switched off within a week.

WHAT THIS DOES NOT COVER. dcc grandchildren inheriting BELOW_NORMAL_PRIORITY_CLASS
is an IDE-felt property that no headless runner can observe; it is an owner-
attended check (plan P6), not something to fake here.

Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''}))
  if(-not $ok){ $script:fail = $true }
}

Check 'engine present' (Test-Path $Exe) $Exe
if(-not (Test-Path $Exe)){ Write-Host 'LINT-TREE COMPILE GUARD: FAIL' -ForegroundColor Red; exit 1 }

$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc32.exe'
if(-not (Test-Path $dcc)){
  Write-Host "[SKIP] dcc32 not found at $dcc -- tier 3 cannot be exercised on this machine"
  Write-Host 'LINT-TREE COMPILE GUARD: PASS' -ForegroundColor Green; exit 0
}

$work = Join-Path $env:TEMP ("dl-treecc-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$buf  = Join-Path $work 'buf'; New-Item -ItemType Directory -Force -Path $buf | Out-Null

function Write-Ascii([string]$p, [string[]]$lines){
  [IO.File]::WriteAllText($p, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $work 'TreeB.pas') @(
  'unit TreeB;','','interface','','procedure FreeProc;','','implementation','',
  'procedure FreeProc;','begin','end;','','end.')
Write-Ascii (Join-Path $work 'TreeA.pas') @(
  'unit TreeA;','','interface','','uses','  TreeB;','','procedure UseIt;','',
  'implementation','','procedure UseIt;','begin','  FreeProc;','end;','','end.')
Write-Ascii (Join-Path $work 'TreeP.dpr') @(
  'program TreeP;','','uses',"  TreeB in 'TreeB.pas',","  TreeA in 'TreeA.pas';",'','begin','end.')
[IO.File]::WriteAllText((Join-Path $work 'TreeP.dproj'), @"
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>TreeP.dpr</MainSource></PropertyGroup>
  <ItemGroup><DCCReference Include="TreeB.pas"/><DCCReference Include="TreeA.pas"/></ItemGroup>
</Project>
"@, [Text.Encoding]::ASCII)

# the buffer: FreeProc removed from the interface AND the implementation
Write-Ascii (Join-Path $buf 'TreeB.buf.pas') @(
  'unit TreeB;','','interface','','implementation','','end.')

$db    = Join-Path $work 'fx.sqlite'
$dproj = Join-Path $work 'TreeP.dproj'
$unit  = Join-Path $work 'TreeB.pas'
$base  = Join-Path $work 'b.json'

& $Exe index $work --db $db --rebuild *> $null
& $Exe lint-tree --unit $unit --db $db --write-baseline $base *> $null
Check 'baseline captured' (Test-Path $base) $base

# --- case 1: BUILD A STALE .DCU FIRST ----------------------------------------
Push-Location $work
& $dcc -Q -B TreeP.dpr *> $null
Pop-Location
$dcuB = Join-Path $work 'TreeB.dcu'
Check 'a STALE TreeB.dcu exists before tier 3 runs' (Test-Path $dcuB) `
      'without it, a passing compile proves nothing about shadow precedence'

function Run-Compile([string]$buffer){
  $a = @('lint-tree','--unit',$unit,'--db',$db,'--baseline',$base,'--project',$dproj,
         '--platform','win32','--compile','--format','json')
  if($buffer){ $a += @('--buffer',$buffer) }
  $o = & $Exe @a 2>$null
  try { ($o | Out-String) | ConvertFrom-Json } catch { $null }
}

# --- case 2: the shadow must beat the stale .dcu ------------------------------
$r = Run-Compile (Join-Path $buf 'TreeB.buf.pas')
Check 'tier 3 ran' ($null -ne $r -and $r.compiled -eq $true) "compiled=$($r.compiled)"
$cc = @($r.findings | Where-Object { $_.ref_kind -eq 'compile' })
Check 'the shadow buffer BEAT the stale .dcu' ($cc.Count -ge 1) `
      'zero compile errors here means dcc bound TreeB.dcu, not the shadow TreeB.pas -- a silent all-clear'
Check 'the compile error names the removed routine' `
      (($cc | Where-Object { $_.message -match 'FreeProc' }).Count -ge 1) `
      ($cc | ForEach-Object { $_.message } | Select-Object -First 2) -join ' | '
# T6, 2026-09-11: tier 3 now compiles ONCE via a generated probe unit instead of
# once per dependent, and findings are remapped through the closure. The OLD loop
# remapped only the EDITED unit, so a dependent's finding kept a
# C:\TEMP\draglint_tree_...\X.pas path that no IDE can place -- a finding you
# cannot navigate to is most of a finding wasted. Assert the remap, and assert
# the probe never leaks into the output as a finding of its own.
# NON-VACUITY, asserted rather than assumed: the remap check below only means
# something if a finding actually comes from a DEPENDENT. The edited unit was
# always remapped correctly, even by the old per-dependent loop; it is the
# dependent's finding that used to keep a C:\TEMP\draglint_tree_... path. So
# pin that at least one compile finding is in TreeA, the dependent.
Check 'a compile finding comes from the DEPENDENT (makes the remap check real)' `
      (@($cc | Where-Object { $_.file -match 'TreeA' }).Count -ge 1) `
      'if every finding were in the edited unit, the remap assertions below would pass vacuously'

Check 'no finding points into the shadow directory' `
      (@($cc | Where-Object { $_.file -match 'draglint_tree_' }).Count -eq 0) `
      'a shadow path cannot be opened by the IDE; findings must map back to the real unit'
Check 'the generated probe unit never appears as a finding' `
      (@($cc | Where-Object { $_.file -match 'draglint_probe' }).Count -eq 0) `
      "the probe's own F2063 echoes carry nothing the named unit does not"

Check 'compile findings are errors, not warnings' `
      (($cc | Where-Object { $_.severity -ne 'error' }).Count -eq 0) ''

# --- case 3: an unchanged buffer must compile nothing -------------------------
$r2 = Run-Compile $null
$cc2 = @($r2.findings | Where-Object { $_.ref_kind -eq 'compile' })
Check 'NEG unchanged buffer -> tier 3 reports nothing' ($cc2.Count -eq 0) `
      "got $($cc2.Count) -- a tier that fires on an unchanged interface gets switched off"
Check 'NEG unchanged buffer -> tier 3 does not even run' ($r2.compiled -ne $true) `
      'compiling a closure speculatively burns a core per idle keystroke'

# --- case 4: the shadow directory is cleaned up ------------------------------
$leftovers = @(Get-ChildItem $env:TEMP -Directory -Filter 'draglint_tree_*' -ErrorAction SilentlyContinue)
Check 'no shadow directory is left behind' ($leftovers.Count -eq 0) `
      "found $($leftovers.Count); a leftover is harmless but accumulates"

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue

if($fail){ Write-Host 'LINT-TREE COMPILE GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'LINT-TREE COMPILE GUARD: PASS' -ForegroundColor Green; exit 0 }
