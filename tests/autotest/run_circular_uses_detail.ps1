<#
run_circular_uses_detail.ps1 -- the circular-uses report section must say WHAT
to move, not just that a cycle exists.

THE COMPLAINT THIS PINS, owner, 2026-09-13, reading a real ORM3 report:
"Line 3 and 4 have circular uses report, but it is abbreviated. The report I saw
days ago would tell me specifically what items have to be moved out. This report
doesn't say anything except that there is a circular dependence and mentions
units, but not ways to fix."

He was right. The section named the units and then advised "extract the shared
code into a new unit" -- correct, and unusable, because the one thing needed is
WHICH code. The section now prints, per edge of the cycle: source -> target, the
uses SECTION that edge goes through, and the declarations that actually cross
it. Those declarations are the extraction candidates.

WHY THE ADVICE LINE IS ASSERTED SEPARATELY. The first version of this feature
closed every cycle with "remove one INTERFACE edge" and was wrong on the very
first real corpus it met: BOTH ORM3 cycles are entirely implementation-section,
so there was no interface edge to remove and the reader was being sent to hunt
for one that does not exist. The guard therefore checks BOTH shapes -- a cycle
with an interface edge must say BREAK HERE, and an implementation-only cycle
must say the opposite -- because an advice line that is right half the time is
what this rule already shipped once.

THE MULTI-LINE DETAIL MUST NOT REACH THE FINDING LINE. A finding is one parsed
record (`<path>:<line>:<col>  [sev] <rule>: <msg>`) and the IDE plugin splits on
the two spaces before '['. Case 5 asserts the finding message stayed single-line,
because putting the narrative there would corrupt every consumer of that format.

Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){
  Write-Host ("  [{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''}))
  if(-not $ok){ $script:fail = $true }
}

$work = Join-Path $env:TEMP ("dl-cyc-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
function W([string]$p,[string[]]$l){ [IO.File]::WriteAllText($p, (($l -join "`r`n")+"`r`n"), [Text.Encoding]::ASCII) }

# --- cycle 1: uAlpha <-> uBeta, and uAlpha's edge is an INTERFACE uses. -------
# The index records uses edges as written; it does not have to be a program the
# compiler would accept, and an interface edge is the case that must say BREAK.
W (Join-Path $work 'uAlpha.pas') @(
  'unit uAlpha;','','interface','','uses','  uBeta;','','type',
  '  TAlphaThing = class','  public','    procedure AlphaRun;','  end;','',
  'implementation','','procedure TAlphaThing.AlphaRun;','var','  B: TBetaThing;',
  'begin','  B:= TBetaThing.Create;','  B.BetaRun;','end;','','end.')

W (Join-Path $work 'uBeta.pas') @(
  'unit uBeta;','','interface','','type',
  '  TBetaThing = class','  public','    procedure BetaRun;','  end;','',
  'implementation','','uses','  uAlpha;','','procedure TBetaThing.BetaRun;',
  'var','  A: TAlphaThing;','begin','  A:= TAlphaThing.Create;','  A.AlphaRun;',
  'end;','','end.')

# --- cycle 2: uGam <-> uDel, BOTH edges implementation-only. ------------------
W (Join-Path $work 'uGam.pas') @(
  'unit uGam;','','interface','','type',
  '  TGamThing = class','  public','    procedure GamRun;','  end;','',
  'implementation','','uses','  uDel;','','procedure TGamThing.GamRun;',
  'var','  D: TDelThing;','begin','  D:= TDelThing.Create;','  D.DelRun;','end;','','end.')

W (Join-Path $work 'uDel.pas') @(
  'unit uDel;','','interface','','type',
  '  TDelThing = class','  public','    procedure DelRun;','  end;','',
  'implementation','','uses','  uGam;','','procedure TDelThing.DelRun;',
  'var','  G: TGamThing;','begin','  G:= TGamThing.Create;','  G.GamRun;','end;','','end.')

$db = Join-Path $work 'fx.sqlite'
& $Exe index $work --db $db --rebuild *> $null
Check '0. fixture indexed' (Test-Path $db) $db

Push-Location $work
try { & $Exe lint-all --db $db --quiet *> $null } finally { Pop-Location }

$rep = Get-ChildItem (Join-Path $work '_D-RAG') -Filter 'lint-report-*.txt' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $rep) { $rep = Get-ChildItem $work -Filter 'lint-report-*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
Check '0b. a report was written' ($null -ne $rep) "under $work"
if (-not $rep) { Write-Host 'CIRCULAR DETAIL GUARD: FAIL' -ForegroundColor Red; exit 1 }

$txt   = Get-Content $rep.FullName -Raw
$lines = Get-Content $rep.FullName
# The narrative section ends at the first standard finding line.
$secEnd = 0
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '  \[(error|warning|info|hint)\]') { $secEnd = $i; break } }
$section = ($lines[0..([Math]::Max(0,$secEnd-1))] -join "`n")

Write-Host ''
Write-Host 'THE FIX -- the section names the declarations that couple the units' -ForegroundColor Cyan

Check '1. CONTROL: a cycle is reported at all' `
      ($section -match 'Circular unit dependency') `
      'no cycle found -- every assertion below would be vacuous'

Check '2. per-edge lines appear, with the uses SECTION named' `
      ($section -match '->.*\[(interface|implementation) uses\]') `
      'this is the line that did not exist before'

Check '3. the coupling SYMBOLS are named (the actual answer to "what do I move")' `
      ($section -match 'needs: \w') `
      "section=[$section]"

Check '4. the interface-edge cycle is marked BREAK HERE' `
      ($section -match 'BREAK HERE') `
      'uAlpha uses uBeta in its INTERFACE, so that edge is the one forcing the cycle'

Write-Host ''
Write-Host 'THE ADVICE MUST MATCH THE EDGES (the bug this shipped with once)' -ForegroundColor Cyan

Check '5. an implementation-only cycle says so, instead of naming a nonexistent interface edge' `
      ($section -match 'every edge is implementation-section') `
      'uGam/uDel couple only through implementation uses'

Check '6. and it is NOT told to break an interface edge it does not have' `
      ($section -notmatch 'break it at an edge marked BREAK HERE[\s\S]*every edge is implementation-section[\s\S]*break it at an edge marked') `
      'the two advice shapes must not both attach to the same cycle'

Write-Host ''
Write-Host 'THE TOOLING CONTRACT IS UNHARMED' -ForegroundColor Cyan

# Every circular-uses FINDING line must still be exactly one line in the
# standard shape. A newline in Message would split it and every downstream
# parser -- the IDE plugin included -- would mis-read the remainder.
$findingLines = @($lines | Where-Object { $_ -match '\[warning\] circular-uses:' })
Check '7. circular-uses still emits standard one-line findings' `
      ($findingLines.Count -ge 2) `
      "found $($findingLines.Count) (expected one per cycle)"

Check '8. no finding line carries the narrative indent (detail leaked into Message)' `
      (($findingLines | Where-Object { $_ -match 'needs: |BREAK HERE' }).Count -eq 0) `
      'the detail belongs to the section, never to the parsed record'

Write-Host ''
try { [IO.Directory]::Delete($work, $true) } catch { }
if($fail){ Write-Host 'CIRCULAR DETAIL GUARD: FAIL' -ForegroundColor Red; exit 1 }
else     { Write-Host 'CIRCULAR DETAIL GUARD: PASS' -ForegroundColor Green; exit 0 }
