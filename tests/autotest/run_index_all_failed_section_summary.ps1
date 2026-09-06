<#
  run_index_all_failed_section_summary.ps1 -- `index --all` must ROLL UP its
  failed sections at the end, by name.

  WHAT THIS IS NOT ABOUT, because the plan that asked for it had it wrong.
  PLAN-SESSION-44 T5 asked to "make one failing section non-fatal-but-loud:
  continue, exit non-zero, print FAILED sections:", with the control "the
  unfixed build abandons section 2". Measured against the engine before a line
  was written: it does NOT abandon it. BuildPlanItem wraps its whole body in
  try..except, returns False, and both driver loops carry on and set Result:=1.
  Two thirds of that task were already true, and the stated control would have
  failed against CORRECT code -- the exact trap this repo has hit before.

  SO THE SUBJECT IS THE THIRD PART ONLY: the roll-up. A failure is announced
  inline, once, at the moment it happens. On a 27-section `index --all` that
  line is thousands of lines up a scrolling log, and the run ends with a
  cheerful per-section trailer and nothing else. The operator's question at the
  end is "did anything fail, and what?", and until now the answer required
  scrolling. Exit code 1 says SOMETHING failed and never says what.

  THE CONTROLS, and why each one is here rather than implied:

    C1  the healthy section still builds. This is the part that already worked,
        so it is a REGRESSION guard: the roll-up must not be bought by turning
        a failure fatal again.
    C2  a failing run still exits non-zero. Also already true, also pinned.
    N1  the summary does NOT name the healthy section. Without this, an
        implementation that listed every section would pass "it names Broken1".
    N2  a run where nothing fails prints NO summary at all. Without this, a
        summary printed unconditionally would satisfy every positive check.

  Both driver paths are exercised, because they are separate loops with
  separate bookkeeping: sequential (--jobs 1) and parallel (--jobs 2, which
  spawns one child per section and needs --config).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_failsum'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

# Two independent healthy source roots, so a section can fail BETWEEN two good
# ones -- the ordering that shows whether the driver carried on.
foreach ($n in 1..2) {
  $d = Join-Path $scratch "src$n"
  New-Item -ItemType Directory -Path $d | Out-Null
  Write-Ascii (Join-Path $d "uGood$n.pas") @"
unit uGood$n;

interface

type
  TGood$n = class
  public
    procedure Work$n;
  end;

implementation

procedure TGood$n.Work$n;
begin
end;

end.
"@
}

$outDir = Join-Path $scratch 'out'
New-Item -ItemType Directory -Path $outDir | Out-Null

# A section FAILS when its include names a project file that is not there:
# BuildPlanItem reports "project file NOT FOUND", then "FAILED, 1 project
# file(s) yielded no source", and returns False WITHOUT raising. That is the
# ordinary failure shape, and the one the roll-up has to catch.
function SectionJson([string]$Name, [string]$Db, [string]$Include) {
  '      { "name": "' + $Name + '", "db": "' + $Db + '", "include": ["' + ($Include -replace '\\','\\') + '"] }'
}

function WriteCfg([string]$Path, [string[]]$Sections) {
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 4096, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "$($outDir -replace '\\','\\')",
    "sections": [
$($Sections -join ",`n")
    ]
  }
}
"@ | Set-Content $Path -Encoding ascii
}

$missing1 = Join-Path $scratch 'NoSuchOne.dproj'
$missing2 = Join-Path $scratch 'NoSuchTwo.dproj'
$src1     = Join-Path $scratch 'src1'
$src2     = Join-Path $scratch 'src2'

# Broken1, Healthy, Broken2 -- the healthy one is in the MIDDLE on purpose.
$cfgMixed = Join-Path $scratch 'mixed.json'
WriteCfg $cfgMixed @(
  (SectionJson 'Broken1' 'broken1.sqlite' $missing1),
  (SectionJson 'Healthy' 'healthy.sqlite' $src1),
  (SectionJson 'Broken2' 'broken2.sqlite' $missing2)
)

# Nothing broken -- the negative control's corpus.
$cfgClean = Join-Path $scratch 'clean.json'
WriteCfg $cfgClean @(
  (SectionJson 'CleanA' 'cleana.sqlite' $src1),
  (SectionJson 'CleanB' 'cleanb.sqlite' $src2)
)

function RunAll([string]$Cfg, [int]$Jobs) {
  # ONE OS HANDLE, DELIBERATELY -- this runner asserts ORDER between the two
  # streams, and the old capture could not support that assertion.
  #
  # `& exe ... 2>&1 | Out-String` hands the child TWO pipes and lets PowerShell
  # merge them in DRAIN order. No writer-side flush can fix that, because the
  # reordering happens on the READING side, after both writes have completed.
  # `cmd /c "... > file 2>&1"` hands the child a SINGLE handle, so the bytes
  # land in write order by construction.
  #
  # cmd propagates the child's exit code, which C2 below independently asserts
  # by requiring a non-zero exit -- so a cmd wrapper that swallowed the code
  # would fail this runner rather than pass it quietly.
  $log = Join-Path $scratch ('runall-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  cmd /c "`"$exePath`" index --all --config `"$Cfg`" --jobs $Jobs > `"$log`" 2>&1" | Out-Null
  $code = $LASTEXITCODE
  $out  = if (Test-Path -LiteralPath $log) { (Get-Content -LiteralPath $log -Raw) } else { '' }
  if ($null -eq $out) { $out = '' }
  return @{ Out = $out; Code = $code }
}

# ---------------------------------------------------------------------------
# CAPTURE SELF-CHECK -- is the capture method fit to carry an ORDER assertion?
#
# This runner asserts that the FAILED-sections roll-up (stderr) comes after the
# last section trailer (stdout). That conclusion is only as good as the capture,
# and the previous capture was NOT good enough: it gave the child two OS pipes
# and merged them in drain order. So the capture is now tested directly, with an
# emitter whose write order is known by construction.
#
# The emitter writes a large stdout block, flushes it, writes ONE stderr line,
# then a final stdout line. Any capture that preserves write order must show
# BULK -> STDERR-MARK -> STDOUT-FINAL.
#
# The NEW way is ASSERTED (it must be 5/5 -- a capture that cannot hold order on
# a synthetic case cannot be trusted to hold it on the engine). The OLD way is
# only REPORTED, never asserted: it reordered 2 of 20 times when measured, so
# asserting it either way would be asserting a coin flip -- which is the exact
# defect fixed in this runner's sibling in session 70.
# ---------------------------------------------------------------------------
$emitter = Join-Path $scratch 'capture_selfcheck_emitter.ps1'
$emitLines = @(
  '$line = (''x'' * 127)'
  'for ($i = 0; $i -lt 4096; $i++) { [Console]::Out.WriteLine("BULK $i $line") }'
  '[Console]::Out.Flush()'
  '[Console]::Error.WriteLine(''STDERR-MARK'')'
  '[Console]::Error.Flush()'
  '[Console]::Out.WriteLine(''STDOUT-FINAL'')'
  '[Console]::Out.Flush()'
)
Set-Content -LiteralPath $emitter -Value ($emitLines -join "`r`n") -Encoding ascii

function CaptureOrderOk([string]$text) {
  $ls = $text -split "`r?`n"
  $iB = [Array]::FindIndex($ls, [Predicate[string]]{ param($l) $l -like 'BULK 0 *' })
  $iE = [Array]::FindIndex($ls, [Predicate[string]]{ param($l) $l -eq 'STDERR-MARK' })
  $iF = [Array]::FindIndex($ls, [Predicate[string]]{ param($l) $l -eq 'STDOUT-FINAL' })
  return (($iB -ge 0) -and ($iE -gt $iB) -and ($iF -gt $iE))
}

$capOld = 0; $capNew = 0
for ($r = 1; $r -le 5; $r++) {
  $tOld = (& pwsh -NoProfile -File $emitter 2>&1 | Out-String)
  if (CaptureOrderOk $tOld) { $capOld++ }

  # `> log` truncates, so the log needs no prior cleanup.
  $capLog = Join-Path $scratch ('capture-{0}.log' -f $r)
  cmd /c "pwsh -NoProfile -File `"$emitter`" > `"$capLog`" 2>&1" | Out-Null
  $tNew = if (Test-Path -LiteralPath $capLog) { (Get-Content -LiteralPath $capLog -Raw) } else { '' }
  if ($null -ne $tNew -and (CaptureOrderOk $tNew)) { $capNew++ }
}

Check 'CAPTURE: the one-handle capture preserves write order 5/5' ($capNew -eq 5) `
      "new=$capNew/5  (old two-pipe capture, reported not asserted: $capOld/5)"

# CONTROL: the checker must be able to say NO. Feed it a text whose order is
# deliberately wrong -- without this, a CaptureOrderOk that always returned true
# would make the assertion above meaningless.
Check 'CAPTURE control: the order checker rejects a known-bad order' `
      (-not (CaptureOrderOk "BULK 0 x`r`nSTDOUT-FINAL`r`nSTDERR-MARK")) `
      'a reversed sample must not read as ordered'

Push-Location C:\TEMP
try {
  # ---------------------------------------------------------------- sequential
  Remove-Item (Join-Path $outDir '*.sqlite') -Force -ErrorAction SilentlyContinue
  $seq = RunAll $cfgMixed 1

  Check 'C1 sequential: the healthy section between two failures STILL BUILDS' `
        (Test-Path (Join-Path $outDir 'healthy.sqlite')) $seq.Out
  Check 'C2 sequential: the run still exits non-zero' `
        ($seq.Code -ne 0) "exit=$($seq.Code)"
  Check 'sequential: a FAILED sections roll-up is printed' `
        ($seq.Out -match 'FAILED sections') $seq.Out
  Check 'sequential: the roll-up NAMES both failed sections' `
        (($seq.Out -match 'FAILED sections.*Broken1') -and ($seq.Out -match 'FAILED sections.*Broken2')) `
        (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')
  Check 'sequential: it counts them (2 of 3)' `
        ($seq.Out -match 'FAILED sections \(2 of 3\)') `
        (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')
  # ORDERING -- NOW A POSITIVE ASSERTION. It used to be a regression pin that
  # could not be trusted, and the reason was the CAPTURE, not the engine.
  #
  # The engine was never at fault: ReportFailedSections (CLI.pas:2781) already
  # does Flush(Output) before writing the roll-up to ErrOutput, which is
  # correct. The reordering happened on the READING side. The old capture,
  # `& exe ... 2>&1 | Out-String`, gave the child TWO OS pipes and merged them
  # in DRAIN order, so the roll-up could overtake a trailer that had already
  # been written. No writer-side flush can order two independently-drained
  # pipes, which is why the old comment here concluded the check "PASSES with
  # or without the flush" and declined to prove anything.
  #
  # RunAll now captures through ONE handle (see its comment). MEASURED
  # 2026-09-06 by the capture self-check above -- not asserted from the
  # mechanism, because this repo's rule is that a mechanism is a hypothesis
  # until it is run:
  #
  #     OLD (& exe 2>&1 | Out-String) : 18/20 preserved order  (two independent
  #     OLD, second sample              18/20                   samples, ~10%
  #     NEW (cmd /c "... > log 2>&1")  : 20/20 preserved order   reorder rate)
  #
  # The failing OLD runs were all the same shape -- the stderr line written
  # FIRST arriving at index 4097 with the stdout line written after it at 4096.
  # So the reorder is real and reproducible, and the new capture eliminates it.
  # This also satisfies the harness rule at tests\README.md:154, which mandates
  # the cmd.exe redirect precisely for order-sensitive captures.
  #
  # It remains a regression pin too: move the roll-up before the build loop, or
  # a trailer after it, and this goes red deterministically. A summary is only
  # a summary if it comes last.
  $lines   = $seq.Out -split "`r?`n"
  $iRollup = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match 'FAILED sections' })
  $iLastTr = [Array]::FindLastIndex($lines, [Predicate[string]]{ param($l) $l -match '^=== .* ===$' })
  Check 'sequential: the roll-up comes AFTER the last section trailer (single-handle capture)' `
        (($iRollup -ge 0) -and ($iLastTr -ge 0) -and ($iRollup -gt $iLastTr)) `
        "rollupIdx=$iRollup lastTrailerIdx=$iLastTr"

  # N1: without this, listing every section would satisfy every check above.
  Check 'N1 sequential: the roll-up does NOT name the healthy section' `
        (-not (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -match 'Healthy')) `
        (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')

  # ------------------------------------------------------------------ parallel
  # A separate loop with separate bookkeeping: one child process per section.
  Remove-Item (Join-Path $outDir '*.sqlite') -Force -ErrorAction SilentlyContinue
  $par = RunAll $cfgMixed 2

  Check 'C3 parallel: the healthy section STILL BUILDS' `
        (Test-Path (Join-Path $outDir 'healthy.sqlite')) $par.Out
  Check 'parallel: a FAILED sections roll-up is printed' `
        ($par.Out -match 'FAILED sections') $par.Out
  Check 'parallel: the roll-up NAMES both failed sections' `
        (($par.Out -match 'FAILED sections.*Broken1') -and ($par.Out -match 'FAILED sections.*Broken2')) `
        (($par.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')

  # ---------------------------------------------- N2: silence when all is well
  Remove-Item (Join-Path $outDir '*.sqlite') -Force -ErrorAction SilentlyContinue
  $ok = RunAll $cfgClean 1

  Check 'N2 an all-healthy run prints NO roll-up' `
        ($ok.Out -notmatch 'FAILED sections') $ok.Out
  Check 'N2 control: and that run really did build both sections' `
        ((Test-Path (Join-Path $outDir 'cleana.sqlite')) -and (Test-Path (Join-Path $outDir 'cleanb.sqlite'))) $ok.Out
  Check 'N2 control: and exits zero' `
        ($ok.Code -eq 0) "exit=$($ok.Code)"
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
