<#
  run_index_stage_markers.ps1 -- the post-parse RESOLVE phase must announce
  itself. Every stage names itself when it starts and reports its duration when
  it ends, on BOTH indexing entry points.

  WHY THIS EXISTS. On 2026-09-08 a full library re-parse ran 6 h 04 m. Its last
  output landed at 10:20 and the next at 11:22 -- 62 minutes, 17% of the entire
  run, with the process at 99% of one core and its working set climbing past
  3 GB. From outside that is indistinguishable from a hang; the monitoring
  session fell back on sampling CPU counters and file mtimes to argue the run
  was alive, and it very nearly got killed on the strength of the quiet.

  BE PRECISE ABOUT THE GAP, because the first version of this header was not.
  The phase did NOT emit nothing. It printed, at 10:20:

      resolve: calls      starting WHOLE-DB pass over all 9593 indexed file(s)
      resolve: calls      ... this is the expensive shape (~37 min on a 2 GB
                          index) -- it is running, not hung

  ...and then went quiet for 3708.9 s until its completion line. So the stage
  ANNOUNCED itself, correctly, and even said in advance that it was not hung.
  What is missing is proof of life DURING the pass -- an announcement made 62
  minutes ago is not evidence that the process is still working now, which is
  exactly why an operator watching it reached for a CPU counter instead.

  THE HEARTBEAT IS THEREFORE THE SUBJECT, not the announcements. The stage
  start/done frame is asserted too, because it must stay uniform across all four
  passes for the beat to be attributable to one -- but a runner that checked
  only the frame would pass against a build whose heartbeat never fires, which
  is the whole defect. See H1/H2.

  WHAT THIS IS NOT ABOUT. It is not about the per-platform section summary. That
  line already exists (`=== Library [Win64] -> ... : files=6993 ... ===`); a
  session searched for it with the wrong pattern, concluded it was missing, and
  filed a defect saying so. It is not missing. This runner asserts the SILENT
  WINDOW BEFORE that line, which is the real gap.

  FOUR CALL SITES, NOT ONE. The resolve quartet appears at four places in
  DRagLint.CLI.pas (the manifest path, DoIndex, the dictionary builder, and the
  reconcile path). Instrumenting one and calling it done is precisely the
  three-parse-entry-points mistake this repo has already paid for once, so this
  runner exercises the TWO that an operator actually waits on: `index <dir>`
  (DoIndex) and `index --all` (BuildPlanItem, the path a 6-hour library run
  takes).

  THE CONTROLS, and why each is here rather than implied:

    C1  the pre-existing summary lines still appear, unchanged in shape. The
        markers must not be bought by disturbing output other runners and the
        operator's own greps key on.
    N1  a stage line must carry a DURATION, not just a name. Without this, an
        implementation that printed only "starting" lines -- leaving "how long
        did it take" as unanswerable as before -- would pass.
    N2  the announcement must PRECEDE the summary. Without this, a run that
        printed all its stage lines in a batch at the very end would pass while
        the operator stared at the same silent window.
    N3  every stage is named individually. Without this, one blanket "resolving
        ..." line would pass and the operator still could not tell which pass is
        the slow one -- which is the question that matters, since the call pass
        is ~99% of the phase.

  POSITIVE CONTROL: this runner was RED-checked against the build that predates
  the fix. If it ever passes against an engine with no stage markers, it has
  stopped testing anything -- see the RED-CHECK note at the bottom.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path

# Unique scratch per run. Remove-Item is permission-blocked in some sessions and
# takes the WHOLE command with it, so this runner never tries to wipe anything.
$scratch = Join-Path C:\TEMP ('draglint_stagemarkers_{0}' -f [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

# Two units with a real uses edge and a real call across them, so the resolve
# passes have actual work: an empty corpus could let a pass no-op and still
# print a marker, which would make the durations meaningless.
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

Write-Ascii (Join-Path $src 'uBase.pas') @"
unit uBase;

interface

type
  TBase = class
  public
    procedure Work;
  end;

implementation

procedure TBase.Work;
begin
end;

end.
"@

Write-Ascii (Join-Path $src 'uDerived.pas') @"
unit uDerived;

interface

uses
  uBase;

type
  TDerived = class(TBase)
  public
    procedure Run;
  end;

implementation

procedure TDerived.Run;
begin
  Work;
end;

end.
"@

# ONE OS HANDLE, DELIBERATELY. This runner asserts ORDER between lines, and
# `& exe 2>&1 | Out-String` hands the child two pipes that PowerShell merges in
# DRAIN order -- the reordering happens on the reading side, so no writer-side
# flush can fix it. cmd's single redirect makes the bytes land in write order.
function RunCapture([string]$ArgLine) {
  $log = Join-Path $scratch ('run-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  cmd /c "`"$exePath`" $ArgLine > `"$log`" 2>&1" | Out-Null
  $code = $LASTEXITCODE
  $out  = if (Test-Path -LiteralPath $log) { (Get-Content -LiteralPath $log -Raw) } else { '' }
  if ($null -eq $out) { $out = '' }
  return @{ Out = $out; Code = $code }
}

# The four passes an operator waits on. 'calls' is the one that costs 2,252 s on
# a library corpus; the other three cost ~21 s together. All four are named
# because "which pass is slow" is the question the silence made unanswerable.
$stages = @('uses-targets','ancestry','helpers','calls')

# A stage line must name the stage AND carry a numeric duration.
function HasStageWithDuration([string]$Text,[string]$Stage) {
  return [bool]([regex]::IsMatch($Text, ('stage:\s*' + [regex]::Escape($Stage) + '\b[^\r\n]*done in\s+\d+(\.\d+)?s')))
}
function HasStageAnnounce([string]$Text,[string]$Stage) {
  return [bool]([regex]::IsMatch($Text, ('stage:\s*' + [regex]::Escape($Stage) + '\b')))
}

Write-Host "`n--- A: bare 'index <dir> --db' (DoIndex entry point) ---" -ForegroundColor Cyan
$dbA = Join-Path $scratch 'a.sqlite'
$rA  = RunCapture ("index `"$src`" --db `"$dbA`"")

Check 'A: exit 0' ($rA.Code -eq 0) ("exit=$($rA.Code)")
Check 'A: C1 the pre-existing Done summary still appears' ([regex]::IsMatch($rA.Out,'Done\.\s*Files:\s*\d+')) 'the summary other tooling greps for must survive'

foreach ($s in $stages) {
  Check ("A: N3 stage '$s' is named" ) (HasStageAnnounce $rA.Out $s) 'each pass names itself, so the slow one is identifiable'
}
foreach ($s in $stages) {
  Check ("A: N1 stage '$s' reports a duration") (HasStageWithDuration $rA.Out $s) 'a name without a duration leaves "how long" unanswerable'
}

# N2: the FIRST stage announcement must precede the final summary.
$idxFirstStage = $rA.Out.IndexOf('stage:')
$idxDone       = $rA.Out.IndexOf('Done. Files:')
Check 'A: N2 stages are announced BEFORE the summary' (($idxFirstStage -ge 0) -and ($idxDone -ge 0) -and ($idxFirstStage -lt $idxDone)) `
  "firstStage=$idxFirstStage done=$idxDone -- batching the lines at the end leaves the silent window intact"

Write-Host "`n--- B: 'index --all' (BuildPlanItem -- the path a library run takes) ---" -ForegroundColor Cyan
$outDir = Join-Path $scratch 'out'
New-Item -ItemType Directory -Path $outDir | Out-Null
$cfg = Join-Path $scratch 'cfg.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 4096, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "$($outDir -replace '\\','\\')",
    "sections": [
      { "name": "StageProbe", "db": "stageprobe.sqlite", "include": ["$($src -replace '\\','\\')"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii

$rB = RunCapture ("index --all --config `"$cfg`" --jobs 1")

Check 'B: exit 0' ($rB.Code -eq 0) ("exit=$($rB.Code)")
Check 'B: C1 the pre-existing section summary still appears' ([regex]::IsMatch($rB.Out,'===\s*StageProbe[^=]*files=\d+\s+symbols=\d+')) `
  'the === Name -> db : files=N symbols=M === line is what other runners key on'

foreach ($s in $stages) {
  Check ("B: N3 stage '$s' is named") (HasStageAnnounce $rB.Out $s) 'the manifest path is the one a 6-hour library run takes'
}
foreach ($s in $stages) {
  Check ("B: N1 stage '$s' reports a duration") (HasStageWithDuration $rB.Out $s) ''
}

# The SUMMARY is the line carrying files=/symbols=, NOT merely '=== StageProbe'.
# The first draft of this runner matched the bare section name and so found the
# new BEGIN line at offset 0, reporting the ordering as broken when it was
# correct. Anchor on what makes the summary a summary.
# NOT [^=]* around the counters: the summary carries several `key=value` fields
# (refs=, parsed=, skipped=) and an "excludes =" pattern silently stops matching
# the moment one is added. It did exactly that when refs/parsed/skipped landed.
# Anchor on the section name and the files= counter, and let the rest be free.
$mSummaryB      = [regex]::Match($rB.Out,'===\s*StageProbe\b[^\r\n]*files=\d+[^\r\n]*===')
$idxFirstStageB = $rB.Out.IndexOf('stage:')
$idxSummaryB    = if ($mSummaryB.Success) { $mSummaryB.Index } else { -1 }
Check 'B: N2 stages are announced BEFORE the section summary' (($idxFirstStageB -ge 0) -and ($idxSummaryB -ge 0) -and ($idxFirstStageB -lt $idxSummaryB)) `
  "firstStage=$idxFirstStageB summary=$idxSummaryB"

# The section must also announce that it has BEGUN, before any of its work. A
# start/end PAIR is what makes a death detectable WHILE it happens: a BEGIN with
# no matching summary is unambiguous, where today a dead platform and an
# unfinished one look identical.
$mBeginB = [regex]::Match($rB.Out,'===\s*StageProbe[^=\r\n]*BEGIN[^=\r\n]*===')
Check 'B: the section announces BEGIN before its summary' `
  ($mBeginB.Success -and ($idxSummaryB -ge 0) -and ($mBeginB.Index -lt $idxSummaryB)) `
  'a start with no end is the only in-flight death signal there can be'
Check 'B: the BEGIN line carries a wall-clock start time' `
  ([regex]::IsMatch($rB.Out,'BEGIN[^\r\n]*started\s+\d{2}:\d{2}:\d{2}')) `
  'every other duration in this output is relative; one absolute stamp per section is what a log can be aligned on'

Write-Host "`n--- H: the heartbeat actually beats ---" -ForegroundColor Cyan
# H1/H2 ARE THE POINT OF THIS RUNNER. A 60-second beat cannot be observed by a
# test that finishes sooner, so the interval is overridable purely so this can
# be proven. Without these two checks a build whose heartbeat never fires --
# indistinguishable from the silence it exists to break -- would pass everything
# above.
# A BIGGER CORPUS, DELIBERATELY. The two-unit corpus above resolves in well
# under a millisecond, so the beat's wait is signalled before it can ever time
# out and NO interval setting can make it fire -- the first version of this
# check failed for exactly that reason and would have been misread as "the
# heartbeat is broken". The beat can only be observed on a pass that outlives
# its own interval, so this builds a corpus with real cross-unit call edges for
# ResolveCallTargets to chew on.
$srcH = Join-Path $scratch 'srcH'
New-Item -ItemType Directory -Path $srcH | Out-Null
foreach ($i in 1..200) {
  $prev = $i - 1
  $usesPrev = if ($i -gt 1) { "uses`r`n  uH$prev;" } else { '' }
  $callPrev = if ($i -gt 1) { "  TH$prev.Create.Step;" } else { '' }
  Write-Ascii (Join-Path $srcH "uH$i.pas") @"
unit uH$i;

interface

$usesPrev

type
  TH$i = class
  public
    procedure Step;
    function Value: Integer;
  end;

implementation

procedure TH$i.Step;
begin
$callPrev
end;

function TH$i.Value: Integer;
begin
  Result := $i;
end;

end.
"@
}

$dbH = Join-Path $scratch 'h.sqlite'
$env:DRAGLINT_STAGE_HEARTBEAT_MS = '1'
# Cleared by assignment, not Remove-Item: Remove-Item is permission-blocked in
# some sessions and takes the WHOLE command with it, which would strand the
# override set for every later runner in the same process.
try   { $rH = RunCapture ("index `"$srcH`" --db `"$dbH`" --rebuild") }
finally { $env:DRAGLINT_STAGE_HEARTBEAT_MS = '' }

Check 'H: exit 0' ($rH.Code -eq 0) ("exit=$($rH.Code)")
Check 'H1 a "still running" beat is emitted when the interval is tiny' `
  ([regex]::IsMatch($rH.Out,'stage:\s*\S+\s*--\s*still running,\s*\d+m\d{2}s elapsed')) `
  'the beat is the whole fix -- without it the run is silent for the duration of the pass'
Check 'H2 the beat names WHICH stage is running' `
  ([regex]::IsMatch($rH.Out,'stage:\s*(uses-targets|ancestry|helpers|calls)\s*--\s*still running')) `
  'an unattributed "still working" line does not say which pass is the slow one'
# NEGATIVE CONTROL for H: the default interval must NOT beat on a fast run.
# Without this, an implementation that printed the beat unconditionally -- on
# every stage regardless of duration -- would satisfy H1 and flood a real log.
Check 'H3 NEGATIVE: no beat at the default interval on a sub-second run' `
  (-not [regex]::IsMatch($rA.Out,'still running')) `
  'a beat that fires on a 0.0s stage is noise, not proof of life'

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0

<#
  RED-CHECK, 2026-09-08: run against the deployed engine BEFORE the stage
  markers were written, this runner failed every N1/N2/N3 assertion on both
  entry points while C1 passed on both -- i.e. it fails for the intended reason
  and not because the corpus or the capture is broken. A guard that has never
  been seen red is a guard that may be incapable of failing.
#>
